import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/export/export_service.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/domain/vacation.dart' as vacation_domain;
import 'package:sqlite3/sqlite3.dart';

import 'test_database.dart';

/// Schema v7: routines, scoped vacation, and the guarded v6→v7 migration.
void main() {
  group('migration → v7', () {
    test(
      'adds routine links and allHabits without changing v6 semantics',
      () async {
        final raw = sqlite3.openInMemory();
        raw.execute('PRAGMA user_version = 6');
        raw.execute('''
        CREATE TABLE habits (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          uuid TEXT NOT NULL DEFAULT '', updated_at INTEGER NOT NULL DEFAULT 0,
          name TEXT NOT NULL, notes TEXT,
          icon_key TEXT NOT NULL DEFAULT 'spark', color INTEGER NOT NULL,
          schedule_type INTEGER NOT NULL, weekdays TEXT,
          target_per_week INTEGER, reminder_time INTEGER,
          freeze_mode INTEGER NOT NULL DEFAULT 0,
          kind INTEGER NOT NULL DEFAULT 0,
          target_amount REAL, created_at INTEGER NOT NULL,
          archived_at INTEGER, sort_order INTEGER NOT NULL DEFAULT 0
        )
      ''');
        raw.execute('''
        CREATE TABLE vacation_periods (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          uuid TEXT NOT NULL DEFAULT '', updated_at INTEGER NOT NULL DEFAULT 0,
          start_date TEXT NOT NULL, end_date TEXT NOT NULL
        )
      ''');
        raw.execute(
          'INSERT INTO habits (uuid, name, color, schedule_type, created_at) '
          "VALUES ('h1', 'Water', 1, 0, 1000)",
        );
        raw.execute(
          'INSERT INTO vacation_periods (uuid, start_date, end_date) '
          "VALUES ('p1', '2026-11-20', '2026-11-22')",
        );

        final db = AppDatabase.withExecutor(
          NativeDatabase.opened(raw, closeUnderlyingOnClose: true),
        );
        final habit = (await db.select(db.habits).get()).single;
        expect(habit.routineId, isNull);
        expect(habit.routineUuid, isNull);
        final period = (await db.select(db.vacationPeriods).get()).single;
        expect(period.allHabits, isTrue);
        expect(await db.select(db.routines).get(), isEmpty);
        expect(await db.select(db.vacationScopes).get(), isEmpty);

        final version = await db
            .customSelect('PRAGMA user_version')
            .map((r) => r.data.values.first as int)
            .getSingle();
        expect(version, 8);
        await db.close();
      },
    );
  });

  group('routines and scoped vacation', () {
    late AppDatabase db;
    late HabitRepository repo;

    setUp(() {
      db = createTestDatabase();
      repo = HabitRepository(db);
    });
    tearDown(() => db.close());

    test('routine CRUD, assignment, and soft delete', () async {
      final routineId = await repo.createRoutine('Morning', 0xFF2DD4A8);
      final habitId = await repo.create(name: 'Meditate', color: 1);
      expect(await repo.setHabitRoutine(habitId, routineId), isTrue);
      var habit = (await repo.getById(habitId))!;
      expect(habit.routineId, routineId);
      expect(habit.routineUuid, isNotEmpty);

      final routine = (await repo.getAllRoutines()).single;
      expect(await repo.setHabitRoutine(habitId, null), isTrue);
      expect((await repo.getById(habitId))!.routineId, isNull);
      expect(await repo.setHabitRoutine(habitId, routine.id), isTrue);

      expect(await repo.deleteRoutine(routine.id), 1);
      habit = (await repo.getById(habitId))!;
      expect(habit.name, 'Meditate');
      expect(habit.routineId, isNull);
      expect(habit.routineUuid, isNull);
      expect(await repo.getAllRoutines(), isEmpty);
      expect(
        (await db.select(db.tombstones).get()).map((t) => t.sourceTable),
        contains('routines'),
      );
    });

    test('replacing scopes tombstones removed rows', () async {
      const periodUuid = 'period-1';
      const scope = vacation_domain.VacationScope(
        periodUuid: periodUuid,
        targetKind: VacationTargetKind.habit,
        targetUuid: 'h1',
      );
      await repo.replaceVacationScopes(periodUuid, [scope]);
      expect(await repo.getVacationScopes(), hasLength(1));

      await repo.replaceVacationScopes(periodUuid, []);
      expect(await repo.getVacationScopes(), isEmpty);
      expect(
        (await db.select(db.tombstones).get()).map((t) => t.sourceTable),
        contains('vacation_scopes'),
      );
    });

    test('deleting a vacation removes its scopes', () async {
      final id = await repo.createVacation(
        '2026-11-20',
        '2026-11-22',
        allHabits: false,
      );
      final period = (await repo.getAllVacationPeriods()).single;
      await repo.replaceVacationScopes(period.uuid, [
        vacation_domain.VacationScope(
          periodUuid: period.uuid,
          targetKind: VacationTargetKind.routine,
          targetUuid: 'r1',
        ),
      ]);
      expect(await repo.deleteVacation(id), 1);
      expect(await repo.getVacationScopes(), isEmpty);
    });

    test('v7 export round-trips routines and scopes', () async {
      final routineId = await repo.createRoutine('Evening', 0xFFFFB454);
      final habitId = await repo.create(name: 'Read', color: 1);
      await repo.setHabitRoutine(habitId, routineId);
      final routine = (await repo.getAllRoutines()).single;
      final id = await repo.createVacation(
        '2026-11-20',
        '2026-11-22',
        allHabits: false,
      );
      final period = (await repo.getAllVacationPeriods()).single;
      await repo.replaceVacationScopes(period.uuid, [
        vacation_domain.VacationScope(
          periodUuid: period.uuid,
          targetKind: VacationTargetKind.routine,
          targetUuid: routine.uuid,
        ),
      ]);
      expect(id, isPositive);

      final target = createTestDatabase();
      addTearDown(target.close);
      await ExportService(target)
          .importFromString(await ExportService(db).exportToString());

      final restored = HabitRepository(target);
      expect((await restored.getAllRoutines()).single.name, 'Evening');
      final habit = (await restored.getAll()).single;
      expect(habit.routineUuid, routine.uuid);
      expect(habit.routineId, isNotNull);
      final restoredPeriod = (await restored.getAllVacationPeriods()).single;
      expect(restoredPeriod.allHabits, isFalse);
      expect(
        (await restored.getVacationScopes()).single.targetUuid,
        routine.uuid,
      );
    });

    test('a v6 backup imports as all-habits with no routines', () async {
      final legacy = {
        'schemaVersion': 6,
        'exportedAt': DateTime.utc(2026, 11, 23).millisecondsSinceEpoch,
        'deviceId': 'old',
        'data': {
          'tasks': <Object>[],
          'subtasks': <Object>[],
          'taskLists': <Object>[],
          'tags': <Object>[],
          'taskTags': <Object>[],
          'habits': [
            {
              'id': 1,
              'uuid': 'h1',
              'updatedAt': 1000,
              'name': 'Water',
              'notes': null,
              'iconKey': 'spark',
              'color': 1,
              'scheduleType': 0,
              'weekdays': null,
              'targetPerWeek': null,
              'reminderTime': null,
              'freezeMode': 0,
              'kind': 0,
              'targetAmount': null,
              'createdAt': 1000,
              'archivedAt': null,
              'sortOrder': 0,
            },
          ],
          'checkins': <Object>[],
          'freezes': <Object>[],
          'relapses': <Object>[],
          'vacations': [
            {
              'id': 1,
              'uuid': 'p1',
              'updatedAt': 1000,
              'startDate': '2026-11-20',
              'endDate': '2026-11-22',
            },
          ],
          'tombstones': <Object>[],
        },
      };
      await ExportService(db).importFromString(jsonEncode(legacy));
      expect(await repo.getAllRoutines(), isEmpty);
      expect(await repo.getVacationScopes(), isEmpty);
      expect((await repo.getAllVacationPeriods()).single.allHabits, isTrue);
      expect((await repo.getAll()).single.routineId, isNull);
    });
  });
}
