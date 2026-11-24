import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/export/export_service.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/tag_repository.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/domain/sync_merge.dart';
import 'package:sqlite3/sqlite3.dart';

/// Schema v2 → v3 migration: every row gains uuid + updatedAt, children gain
/// parent uuids, and the tombstones table becomes available.
void main() {
  // The applyMerged tests intentionally open two databases (two simulated
  // devices), each with its own executor.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('migration v2 → v3', () {
    test('backfills uuids, parent refs, and updatedAt', () async {
      final raw = sqlite3.openInMemory();
      raw.execute('PRAGMA user_version = 2');
      raw.execute('''
        CREATE TABLE tasks (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL, notes TEXT, due_at INTEGER,
          priority INTEGER NOT NULL, completed_at INTEGER,
          recurrence_rule TEXT, reminder_at INTEGER,
          created_at INTEGER NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0
        )
      ''');
      raw.execute('''
        CREATE TABLE subtasks (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          task_id INTEGER NOT NULL REFERENCES tasks (id) ON DELETE CASCADE,
          title TEXT NOT NULL,
          done INTEGER NOT NULL DEFAULT 0,
          position INTEGER NOT NULL DEFAULT 0
        )
      ''');
      raw.execute('''
        CREATE TABLE tags (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE, color INTEGER NOT NULL
        )
      ''');
      raw.execute('''
        CREATE TABLE task_tags (
          task_id INTEGER NOT NULL REFERENCES tasks (id) ON DELETE CASCADE,
          tag_id INTEGER NOT NULL REFERENCES tags (id) ON DELETE CASCADE,
          PRIMARY KEY (task_id, tag_id)
        )
      ''');
      raw.execute('''
        CREATE TABLE habits (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
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
          habit_id INTEGER NOT NULL REFERENCES habits (id) ON DELETE CASCADE,
          date TEXT NOT NULL, note TEXT, UNIQUE (habit_id, date)
        )
      ''');
      raw.execute('''
        CREATE TABLE habit_freezes (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          habit_id INTEGER NOT NULL REFERENCES habits (id) ON DELETE CASCADE,
          date TEXT NOT NULL, created_at INTEGER NOT NULL,
          UNIQUE (habit_id, date)
        )
      ''');
      raw.execute(
        'INSERT INTO tasks (title, priority, created_at, completed_at) '
        "VALUES ('Legacy task', 0, 1000, 5000)",
      );
      raw.execute("INSERT INTO subtasks (task_id, title) VALUES (1, 'Step')");
      raw.execute("INSERT INTO tags (name, color) VALUES ('home', 1)");
      raw.execute('INSERT INTO task_tags (task_id, tag_id) VALUES (1, 1)');
      raw.execute(
        'INSERT INTO habits (name, color, schedule_type, created_at) '
        "VALUES ('Legacy', 1, 0, 2000)",
      );
      raw.execute(
        "INSERT INTO habit_checkins (habit_id, date) VALUES (1, '2026-11-20')",
      );
      raw.execute(
        'INSERT INTO habit_freezes (habit_id, date, created_at) '
        "VALUES (1, '2026-11-16', 3000)",
      );

      final db = AppDatabase.withExecutor(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: true),
      );

      final task = (await db.select(db.tasks).get()).single;
      expect(task.uuid, isNotEmpty);
      expect(task.updatedAt.millisecondsSinceEpoch, 5000); // completedAt wins

      final habit = (await db.select(db.habits).get()).single;
      expect(habit.uuid, isNotEmpty);
      expect(habit.updatedAt.millisecondsSinceEpoch, 2000);

      final sub = (await db.select(db.subtasks).get()).single;
      expect(sub.taskUuid, task.uuid);
      expect(sub.updatedAt, task.updatedAt);

      final link = (await db.select(db.taskTags).get()).single;
      expect(link.taskUuid, task.uuid);
      expect(link.tagUuid, (await db.select(db.tags).get()).single.uuid);

      final checkin = (await db.select(db.habitCheckins).get()).single;
      expect(checkin.habitUuid, habit.uuid);
      expect(
        checkin.updatedAt.millisecondsSinceEpoch,
        DateTime.parse('2026-11-20T12:00:00Z').millisecondsSinceEpoch,
      );

      final freeze = (await db.select(db.habitFreezes).get()).single;
      expect(freeze.habitUuid, habit.uuid);
      expect(freeze.updatedAt.millisecondsSinceEpoch, 3000);

      // All uuids distinct; tombstones table usable.
      final uuids = [
        task.uuid,
        habit.uuid,
        sub.uuid,
        link.uuid,
        checkin.uuid,
        freeze.uuid,
      ];
      expect(uuids.toSet(), hasLength(uuids.length));
      expect(await db.select(db.tombstones).get(), isEmpty);

      final version = await db
          .customSelect('PRAGMA user_version')
          .map((r) => r.data.values.first as int)
          .getSingle();
      expect(version, 6);
      await db.close();
    });
  });

  group('tombstone writes', () {
    late AppDatabase db;
    late HabitRepository habits;
    late TaskRepository tasks;
    late TagRepository tags;

    setUp(() {
      db = AppDatabase.withExecutor(NativeDatabase.memory(), deviceId: 'devA');
      habits = HabitRepository(db);
      tasks = TaskRepository(db);
      tags = TagRepository(db);
    });
    tearDown(() => db.close());

    test('check-in undo writes a tombstone with the row uuid', () async {
      final id = await habits.create(name: 'Read', color: 1);
      await habits.checkIn(id, '2026-11-20');
      final checkin = (await habits.getAllCheckins()).single;

      await habits.removeCheckIn(id, '2026-11-20');
      final tombs = await db.select(db.tombstones).get();
      expect(tombs, hasLength(1));
      expect(tombs.single.uuid, checkin.uuid);
      expect(tombs.single.sourceTable, 'habit_checkins');
      expect(tombs.single.deviceId, 'devA');
    });

    test('habit delete tombstones the habit and cascaded children', () async {
      final id = await habits.create(name: 'Read', color: 1);
      await habits.checkIn(id, '2026-11-20');
      await habits.placeFreeze(id, '2026-11-16');
      final checkinUuid = (await habits.getAllCheckins()).single.uuid;
      final freezeUuid = (await habits.getAllFreezes()).single.uuid;
      final habitUuid = (await habits.getById(id))!.uuid;

      await habits.delete(id);
      final tombs = await db.select(db.tombstones).get();
      expect(tombs.map((t) => t.uuid).toSet(), {
        habitUuid,
        checkinUuid,
        freezeUuid,
      });
    });

    test('task delete tombstones subtasks and tag links', () async {
      final taskId = await tasks.create(title: 'T');
      await tasks.addSubtask(taskId, 'Step');
      final tagId = await tags.create(name: 'home', color: 1);
      await tasks.setTags(taskId, [tagId]);
      final subUuid = (await tasks.getSubtasks(taskId)).single.uuid;
      final linkUuid = (await db.select(db.taskTags).get()).single.uuid;

      await tasks.delete(taskId);
      final tombs = await db.select(db.tombstones).get();
      expect(tombs.map((t) => t.sourceTable).toSet(), {
        'tasks',
        'subtasks',
        'task_tags',
      });
      expect(tombs.map((t) => t.uuid), contains(subUuid));
      expect(tombs.map((t) => t.uuid), contains(linkUuid));
    });

    test('removing a tag link tombstones only the removed link', () async {
      final taskId = await tasks.create(title: 'T');
      final t1 = await tags.create(name: 'a', color: 1);
      final t2 = await tags.create(name: 'b', color: 2);
      await tasks.setTags(taskId, [t1, t2]);
      final before = await db.select(db.taskTags).get();
      final removedUuid = before.firstWhere((l) => l.tagId == t2).uuid;
      final keptUuid = before.firstWhere((l) => l.tagId == t1).uuid;

      await tasks.setTags(taskId, [t1]);
      final after = await db.select(db.taskTags).get();
      expect(after.single.uuid, keptUuid); // identity preserved
      final tombs = await db.select(db.tombstones).get();
      expect(tombs.single.uuid, removedUuid);
    });

    test('updates stamp updatedAt', () async {
      final id = await habits.create(name: 'Read', color: 1);
      final before = (await habits.getById(id))!.updatedAt;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await habits.archive(id);
      final after = (await habits.getById(id))!.updatedAt;
      expect(after.isAfter(before), isTrue);
    });
  });

  group('applyMerged (upsert by uuid)', () {
    test('two databases converge and preserve local ids', () async {
      final dbA = AppDatabase.withExecutor(
        NativeDatabase.memory(),
        deviceId: 'devA',
      );
      final dbB = AppDatabase.withExecutor(
        NativeDatabase.memory(),
        deviceId: 'devB',
      );
      addTearDown(dbA.close);
      addTearDown(dbB.close);

      final habitsA = HabitRepository(dbA);
      final habitsB = HabitRepository(dbB);

      // A creates a habit + check-in; B starts empty with an unrelated task.
      final idA = await habitsA.create(name: 'Read', color: 1);
      await habitsA.checkIn(idA, '2026-11-20');
      await TaskRepository(dbB).create(title: 'B task');

      final svcA = ExportService(dbA);
      final svcB = ExportService(dbB);
      final envA =
          jsonDecode(await svcA.exportToString()) as Map<String, Object?>;
      final envB =
          jsonDecode(await svcB.exportToString()) as Map<String, Object?>;

      final merged = mergeEnvelopes(
        envelopes: [envA, envB],
        deviceId: 'devB',
        now: DateTime.utc(2026, 11, 23),
      );
      await svcB.applyMerged(merged.envelope);

      // B now has A's habit + check-in plus its own task.
      final bHabits = await habitsB.getAll();
      expect(bHabits, hasLength(1));
      expect(bHabits.single.name, 'Read');
      expect(bHabits.single.uuid, (await habitsA.getById(idA))!.uuid);
      final bCheckins = await habitsB.getAllCheckins();
      expect(bCheckins, hasLength(1));
      expect(bCheckins.single.habitId, bHabits.single.id); // FK remapped
      expect(await TaskRepository(dbB).getAll(), hasLength(1));

      // A's local id is unchanged when A applies the same merge.
      await svcA.applyMerged(
        mergeEnvelopes(
          envelopes: [envA, envB],
          deviceId: 'devA',
          now: DateTime.utc(2026, 11, 23),
        ).envelope,
      );
      expect((await habitsA.getById(idA))!.name, 'Read');
      expect(await habitsA.getAllCheckins(), hasLength(1));
    });

    test('remote delete propagates and removes local children', () async {
      final dbA = AppDatabase.withExecutor(
        NativeDatabase.memory(),
        deviceId: 'devA',
      );
      final dbB = AppDatabase.withExecutor(
        NativeDatabase.memory(),
        deviceId: 'devB',
      );
      addTearDown(dbA.close);
      addTearDown(dbB.close);
      final habitsA = HabitRepository(dbA);
      final habitsB = HabitRepository(dbB);
      final svcA = ExportService(dbA);
      final svcB = ExportService(dbB);

      // Both devices hold the same habit (B imported A's state earlier).
      final idA = await habitsA.create(name: 'Read', color: 1);
      await habitsA.checkIn(idA, '2026-11-20');
      final envA =
          jsonDecode(await svcA.exportToString()) as Map<String, Object?>;
      await svcB.applyMerged(
        mergeEnvelopes(
          envelopes: [envA],
          deviceId: 'devB',
          now: DateTime.utc(2026, 11, 23),
        ).envelope,
      );
      final idB = (await habitsB.getAll()).single.id;
      expect(await habitsB.getAllCheckins(), hasLength(1));

      // A deletes the habit; B merges → habit + check-in gone on B too.
      await habitsA.delete(idA);
      final envA2 =
          jsonDecode(await svcA.exportToString()) as Map<String, Object?>;
      final envB2 =
          jsonDecode(await svcB.exportToString()) as Map<String, Object?>;
      await svcB.applyMerged(
        mergeEnvelopes(
          envelopes: [envA2, envB2],
          deviceId: 'devB',
          now: DateTime.utc(2026, 11, 23),
        ).envelope,
      );
      expect(await habitsB.getAll(), isEmpty);
      expect(await habitsB.getAllCheckins(), isEmpty);
      expect(await dbB.select(dbB.tombstones).get(), isNotEmpty);
      expect(idB, isNotNull);
    });

    test('newer remote edit wins over local copy', () async {
      final dbA = AppDatabase.withExecutor(
        NativeDatabase.memory(),
        deviceId: 'devA',
      );
      final dbB = AppDatabase.withExecutor(
        NativeDatabase.memory(),
        deviceId: 'devB',
      );
      addTearDown(dbA.close);
      addTearDown(dbB.close);
      final habitsA = HabitRepository(dbA);
      final habitsB = HabitRepository(dbB);
      final svcA = ExportService(dbA);
      final svcB = ExportService(dbB);

      final idA = await habitsA.create(name: 'Read', color: 1);
      final envA =
          jsonDecode(await svcA.exportToString()) as Map<String, Object?>;
      await svcB.applyMerged(
        mergeEnvelopes(
          envelopes: [envA],
          deviceId: 'devB',
          now: DateTime.utc(2026, 11, 23),
        ).envelope,
      );
      final idB = (await habitsB.getAll()).single.id;

      // B renames later than A's copy.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await habitsB.update(
        (await habitsB.getById(idB))!.copyWith(name: 'Read books'),
      );

      final envA2 =
          jsonDecode(await svcA.exportToString()) as Map<String, Object?>;
      final envB2 =
          jsonDecode(await svcB.exportToString()) as Map<String, Object?>;
      await svcA.applyMerged(
        mergeEnvelopes(
          envelopes: [envA2, envB2],
          deviceId: 'devA',
          now: DateTime.utc(2026, 11, 23),
        ).envelope,
      );
      expect((await habitsA.getById(idA))!.name, 'Read books');
      expect((await habitsA.getById(idA))!.id, idA); // local id preserved
    });

    test('pre-v4 remote envelope does not cause a rewrite loop', () async {
      // Regression: an older device's envelope omits the v4 nullable columns
      // (targetAmount / amount). Applying it must converge in one pass — a
      // second merge+apply must not write anything (which would re-trigger
      // the data streams and loop forever).
      final db = AppDatabase.withExecutor(
        NativeDatabase.memory(),
        deviceId: 'devA',
      );
      addTearDown(db.close);
      final svc = ExportService(db);
      final habits = HabitRepository(db);
      final id = await habits.create(name: 'Water', color: 1);
      await habits.checkIn(id, '2026-11-20');

      // Build a remote envelope and strip the v4 keys (simulate a pre-v4 file).
      final remoteDb = AppDatabase.withExecutor(
        NativeDatabase.memory(),
        deviceId: 'devB',
      );
      final remoteHabits = HabitRepository(remoteDb);
      final rid = await remoteHabits.create(name: 'Water', color: 1);
      await remoteHabits.checkIn(rid, '2026-11-20');
      // Copy devA's uuids so the rows are the "same" logical rows.
      final localEnv = await svc.collect();
      await remoteHabits.update(
        (await remoteHabits.getById(rid))!.copyWith(
          uuid: localEnv.habits.single.uuid,
          updatedAt: localEnv.habits.single.updatedAt,
        ),
      );
      final remoteJson = jsonDecode(
        await ExportService(remoteDb).exportToString(),
      ) as Map<String, Object?>;
      final data = remoteJson['data'] as Map<String, Object?>;
      for (final h in (data['habits'] as List).cast<Map<String, Object?>>()) {
        h.remove('targetAmount');
      }
      for (final c in (data['checkins'] as List).cast<Map<String, Object?>>()) {
        c.remove('amount');
      }
      await remoteDb.close();

      // Watch the habits + checkins streams and count emissions.
      var habitEmissions = 0;
      var checkinEmissions = 0;
      final hSub = db.select(db.habits).watch().listen((_) => habitEmissions++);
      final cSub = db
          .select(db.habitCheckins)
          .watch()
          .listen((_) => checkinEmissions++);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final hBefore = habitEmissions;
      final cBefore = checkinEmissions;

      // First merge+apply adopts the remote copy (same content, older shape).
      final local1 = (await svc.collect()).toJson();
      await svc.applyMerged(
        mergeEnvelopes(
          envelopes: [local1, remoteJson],
          deviceId: 'devA',
          now: DateTime.utc(2026, 11, 23),
        ).envelope,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Second merge+apply must be a complete no-op (no stream emissions).
      final hMid = habitEmissions;
      final cMid = checkinEmissions;
      final local2 = (await svc.collect()).toJson();
      await svc.applyMerged(
        mergeEnvelopes(
          envelopes: [local2, remoteJson],
          deviceId: 'devA',
          now: DateTime.utc(2026, 11, 23),
        ).envelope,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(habitEmissions, hMid, reason: 'second apply rewrote habits');
      expect(checkinEmissions, cMid, reason: 'second apply rewrote checkins');
      expect(hBefore, lessThanOrEqualTo(hMid));
      expect(cBefore, lessThanOrEqualTo(cMid));

      await hSub.cancel();
      await cSub.cancel();
    });
  });
}
