import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/export/export_service.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/domain/habit_schedule.dart';
import 'package:nowpill/domain/streak_engine.dart';
import 'package:sqlite3/sqlite3.dart';

import 'test_database.dart';

/// Schema v6: quit habits and planned vacation — migration, relapse CRUD,
/// export/import, and sync identity.
void main() {
  group('migration → v6', () {
    test(
      'adds habit.kind plus relapse/vacation tables without changing streaks',
      () async {
        final raw = sqlite3.openInMemory();
        raw.execute('PRAGMA user_version = 3');
        raw.execute('''
        CREATE TABLE habits (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          uuid TEXT NOT NULL DEFAULT '', updated_at INTEGER NOT NULL DEFAULT 0,
          name TEXT NOT NULL, notes TEXT,
          icon_key TEXT NOT NULL DEFAULT 'spark', color INTEGER NOT NULL,
          schedule_type INTEGER NOT NULL, weekdays TEXT,
          target_per_week INTEGER, reminder_time INTEGER,
          freeze_mode INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL, archived_at INTEGER,
          sort_order INTEGER NOT NULL DEFAULT 0
        )
      ''');
        raw.execute('''
          CREATE TABLE habit_checkins (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            uuid TEXT NOT NULL DEFAULT '', updated_at INTEGER NOT NULL DEFAULT 0,
            habit_id INTEGER NOT NULL REFERENCES habits (id) ON DELETE CASCADE,
            habit_uuid TEXT NOT NULL DEFAULT '',
            date TEXT NOT NULL, note TEXT, UNIQUE (habit_id, date)
          )
        ''');
        raw.execute(
          'INSERT INTO habits (uuid, name, color, schedule_type, created_at) '
          "VALUES ('h-uuid', 'Water', 1, 0, 1000)",
        );

        final db = AppDatabase.withExecutor(
          NativeDatabase.opened(raw, closeUnderlyingOnClose: true),
        );
        final habit = (await db.select(db.habits).get()).single;
        expect(habit.kind, HabitKind.build);
        expect(await db.select(db.habitRelapses).get(), isEmpty);
        expect(await db.select(db.vacationPeriods).get(), isEmpty);

        final version = await db
            .customSelect('PRAGMA user_version')
            .map((r) => r.data.values.first as int)
            .getSingle();
        expect(version, 6);
        await db.close();
      },
    );
  });

  group('quit habits and vacation', () {
    late AppDatabase db;
    late HabitRepository habits;

    setUp(() {
      db = createTestDatabase();
      habits = HabitRepository(db);
    });
    tearDown(() => db.close());

    test('relapse is one per day and removal tombstones it', () async {
      final id = await habits.create(
        name: 'Smoking',
        color: 1,
        kind: HabitKind.quit,
        createdAt: DateTime(2026, 11, 1),
      );
      const day = '2026-11-20';
      expect(await habits.logRelapse(id, day, note: 'stress'), isPositive);
      expect(await habits.logRelapse(id, day), -1);
      expect(await habits.getRelapses(id), hasLength(1));

      expect(await habits.removeRelapse(id, day), 1);
      expect(await habits.getRelapses(id), isEmpty);
      final tombs = await db.select(db.tombstones).get();
      expect(tombs.map((t) => t.sourceTable), contains('habit_relapses'));
    });

    test('quit date is the habit creation date and can be backdated', () async {
      final start = DateTime(2026, 11, 10);
      final id = await habits.create(
        name: 'Quit',
        color: 1,
        kind: HabitKind.quit,
        createdAt: start,
      );
      final habit = (await habits.getById(id))!;
      expect(formatDate(habit.createdAt.toLocal()), formatDate(start));

      final earlier = DateTime(2026, 11, 1);
      expect(await habits.setQuitDate(id, earlier), isTrue);
      expect(
        formatDate((await habits.getById(id))!.createdAt.toLocal()),
        formatDate(earlier),
      );
    });

    test('kind is locked once the habit has history', () async {
      final id = await habits.create(name: 'Water', color: 1);
      expect(await habits.setKind(id, HabitKind.quit), isTrue);
      // Simulate history on a fresh habit.
      final withHistory = await habits.create(name: 'Read', color: 2);
      await habits.checkIn(withHistory, '2026-11-20');
      expect(await habits.setKind(withHistory, HabitKind.quit), isFalse);
    });

    test('vacation rejection, CRUD, and tombstone on delete', () async {
      expect(
        () => habits.createVacation('2026-11-20', '2026-11-10'),
        throwsArgumentError,
      );
      final id = await habits.createVacation('2026-11-20', '2026-11-23');
      final periods = await habits.getAllVacationPeriods();
      expect(periods, hasLength(1));
      expect(periods.single.startDate, '2026-11-20');
      expect(periods.single.endDate, '2026-11-23');

      expect(await habits.deleteVacation(id), 1);
      expect(await habits.getAllVacationPeriods(), isEmpty);
      final tombs = await db.select(db.tombstones).get();
      expect(tombs.map((t) => t.sourceTable), contains('vacation_periods'));
    });

    test('deleting a quit habit tombstones its relapses', () async {
      final id = await habits.create(
        name: 'Quit',
        color: 1,
        kind: HabitKind.quit,
        createdAt: DateTime(2026, 11, 1),
      );
      await habits.logRelapse(id, '2026-11-20');
      await habits.delete(id);
      final tombs = await db.select(db.tombstones).get();
      expect(tombs.map((t) => t.sourceTable), contains('habit_relapses'));
    });

    test('export v6 round-trips kind, relapses, and vacations', () async {
      final id = await habits.create(
        name: 'Quit',
        color: 1,
        kind: HabitKind.quit,
        createdAt: DateTime(2026, 11, 1),
      );
      await habits.logRelapse(id, '2026-11-20', note: 'once');
      await habits.createVacation('2026-11-22', '2026-11-24');

      final json = await ExportService(db).exportToString();
      final target = createTestDatabase();
      addTearDown(target.close);
      await ExportService(target).importFromString(json);

      final restored = HabitRepository(target);
      final habit = (await restored.getAll()).single;
      expect(habit.kind, HabitKind.quit);
      expect(await restored.getRelapses(habit.id), hasLength(1));
      final periods = await restored.getAllVacationPeriods();
      expect(periods.single.startDate, '2026-11-22');
    });

    test('a v5 backup imports as build habits with no relapses', () async {
      final legacy = {
        'schemaVersion': 5,
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
              'targetAmount': null,
              'createdAt': 1000,
              'archivedAt': null,
              'sortOrder': 0,
            },
          ],
          'checkins': <Object>[],
          'freezes': <Object>[],
          'tombstones': <Object>[],
        },
      };
      await ExportService(db).importFromString(jsonEncode(legacy));
      final habit = (await habits.getAll()).single;
      expect(habit.kind, HabitKind.build);
      expect(await habits.getAllRelapses(), isEmpty);
      expect(await habits.getAllVacationPeriods(), isEmpty);
    });

    test(
      'streak replay sees relapses and vacation through the repository',
      () async {
        final id = await habits.create(
          name: 'Quit',
          color: 1,
          kind: HabitKind.quit,
          createdAt: DateTime(2026, 11, 20),
        );
        await habits.logRelapse(id, '2026-11-22');
        final relapses = (await habits.getRelapses(id))
            .map((r) => r.date)
            .toSet();
        final result = replayStreak(
          schedule: const HabitSchedule.daily(),
          checkins: const {},
          today: DateTime(2026, 11, 24),
          startDate: DateTime(2026, 11, 20),
          kind: HabitKind.quit,
          relapses: relapses,
        );
        expect(result.currentStreak, 2);
        expect(result.bestStreak, 2);
      },
    );
  });
}
