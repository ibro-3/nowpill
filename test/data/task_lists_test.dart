import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/export/export_service.dart';
import 'package:nowpill/data/repositories/task_list_repository.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/domain/recurrence_rule.dart';
import 'package:nowpill/domain/sync_merge.dart';
import 'package:sqlite3/sqlite3.dart';

import 'test_database.dart';

/// Schema v5 task lists: migration, soft-delete semantics, backup round-trip,
/// and the sync merge rules for a soft parent reference.
void main() {
  group('migration v4 → v5', () {
    test(
      'adds task_lists and nullable task list columns, preserving rows',
      () async {
        final raw = sqlite3.openInMemory();
        raw.execute('PRAGMA user_version = 4');
        raw.execute('''
        CREATE TABLE tasks (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          uuid TEXT NOT NULL DEFAULT '', updated_at INTEGER NOT NULL DEFAULT 0,
          title TEXT NOT NULL, notes TEXT, due_at INTEGER, priority INTEGER NOT NULL,
          completed_at INTEGER, recurrence_rule TEXT, reminder_at INTEGER,
          created_at INTEGER NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0
        )
      ''');
        raw.execute(
          'INSERT INTO tasks (uuid, title, priority, created_at) '
          "VALUES ('t-uuid', 'Old task', 0, 1000)",
        );

        final db = AppDatabase.withExecutor(
          NativeDatabase.opened(raw, closeUnderlyingOnClose: true),
        );
        final task = (await db.select(db.tasks).get()).single;
        expect(task.listId, isNull);
        expect(task.listUuid, isNull);

        final listId = await db
            .into(db.taskLists)
            .insert(TaskListsCompanion.insert(name: 'Home', color: 1));
        await db.tasksDao.updateTask(task.copyWith(listId: Value(listId)));
        final updated = (await db.select(db.tasks).get()).single;
        expect(updated.listId, listId);
        expect(updated.listUuid, isNotNull); // resolved by the DAO

        final version = await db
            .customSelect('PRAGMA user_version')
            .map((r) => r.data.values.first as int)
            .getSingle();
        expect(version, 8);
        await db.close();
      },
    );
  });

  group('task lists', () {
    late AppDatabase db;
    late TaskListRepository lists;
    late TaskRepository tasks;

    setUp(() {
      db = createTestDatabase();
      lists = TaskListRepository(db);
      tasks = TaskRepository(db);
    });
    tearDown(() => db.close());

    test('deleting a list keeps its tasks and clears the soft link', () async {
      final listId = await lists.create(name: 'Home', color: 0xFF5B8DEF);
      final taskId = await tasks.create(title: 'Water plants', listId: listId);
      final linked = (await tasks.getById(taskId))!;
      expect(linked.listId, listId);
      expect(linked.listUuid, isNotNull);

      await lists.delete(listId);

      final task = (await tasks.getById(taskId))!;
      expect(task.listId, isNull);
      expect(task.listUuid, isNull);
    });

    test('recurring spawn keeps the task in its list', () async {
      final listId = await lists.create(name: 'Home', color: 1);
      final taskId = await tasks.create(
        title: 'Water plants',
        listId: listId,
        dueAt: DateTime(2026, 11, 23, 9),
        recurrence: const RecurrenceRule(unit: RecurrenceUnit.day),
      );
      final spawnedId = await tasks.complete(taskId);
      final spawned = (await tasks.getById(spawnedId!))!;
      expect(spawned.listId, listId);
      expect(spawned.listUuid, isNotNull);
    });

    test('export v5 round-trips lists and task links', () async {
      final listId = await lists.create(name: 'Home', color: 0xFF5B8DEF);
      await tasks.create(title: 'Water plants', listId: listId);
      final json = await ExportService(db).exportToString();

      final target = createTestDatabase();
      addTearDown(target.close);
      await ExportService(target).importFromString(json);

      final restoredLists = await TaskListRepository(target).getAll();
      expect(restoredLists, hasLength(1));
      expect(restoredLists.single.name, 'Home');
      final restoredTask = (await TaskRepository(target).getAll()).single;
      expect(restoredTask.listUuid, restoredLists.single.uuid);
      expect(restoredTask.listId, restoredLists.single.id);
    });

    test('pre-v5 backups import tasks into the inbox', () async {
      final legacy = {
        'schemaVersion': 4,
        'exportedAt': DateTime.utc(2026, 11, 23).millisecondsSinceEpoch,
        'deviceId': 'old',
        'data': {
          'tasks': [
            {
              'id': 1,
              'uuid': 't1',
              'updatedAt': 1000,
              'title': 'Old task',
              'notes': null,
              'dueAt': null,
              'priority': 0,
              'completedAt': null,
              'recurrenceRule': null,
              'reminderAt': null,
              'createdAt': 1000,
              'sortOrder': 0,
            },
          ],
          'subtasks': <Object>[],
          'tags': <Object>[],
          'taskTags': <Object>[],
          'habits': <Object>[],
          'checkins': <Object>[],
          'freezes': <Object>[],
          'tombstones': <Object>[],
        },
      };
      await ExportService(db).importFromString(jsonEncode(legacy));
      final task = (await tasks.getAll()).single;
      expect(task.listId, isNull);
      expect(task.listUuid, isNull);
      expect(await lists.getAll(), isEmpty);
    });
  });

  group('sync merge (soft list parent)', () {
    final now = DateTime.utc(2026, 11, 23, 12);

    Map<String, Object?> env(
      String device,
      List<Object?> taskLists,
      List<Object?> taskRows,
    ) => {
      'schemaVersion': 5,
      'exportedAt': now.millisecondsSinceEpoch,
      'deviceId': device,
      'data': {
        'tasks': taskRows,
        'taskLists': taskLists,
        'habits': <Object>[],
        'tags': <Object>[],
        'subtasks': <Object>[],
        'taskTags': <Object>[],
        'checkins': <Object>[],
        'freezes': <Object>[],
        'tombstones': <Object>[],
      },
    };

    Map<String, Object?> list(String uuid, int updatedAt, String name) => {
      'id': 1,
      'uuid': uuid,
      'updatedAt': updatedAt,
      'name': name,
      'color': 1,
      'sortOrder': 0,
    };

    Map<String, Object?> taskRow(String uuid, String? listUuid) => {
      'id': 1,
      'uuid': uuid,
      'updatedAt': 100,
      'title': 'Task',
      'notes': null,
      'dueAt': null,
      'priority': 0,
      'completedAt': null,
      'recurrenceRule': null,
      'reminderAt': null,
      'createdAt': 100,
      'sortOrder': 0,
      'listId': 1,
      'listUuid': listUuid,
    };

    test('duplicate list names converge and task links are remapped', () {
      final result = mergeEnvelopes(
        envelopes: [
          env('a', [list('la', 200, 'Home')], [taskRow('t1', 'la')]),
          env('b', [list('lb', 100, 'Home')], [taskRow('t2', 'lb')]),
        ],
        deviceId: 'a',
        now: now,
      );
      final data = result.envelope['data'] as Map<String, Object?>;
      final lists = data['taskLists'] as List;
      expect(lists, hasLength(1));
      expect((lists.single as Map)['uuid'], 'la');

      final tasks = data['tasks'] as List;
      final byUuid = {for (final r in tasks) (r as Map)['uuid']: r};
      expect((byUuid['t1'] as Map)['listUuid'], 'la');
      expect((byUuid['t2'] as Map)['listUuid'], 'la');
    });

    test('tasks referencing a missing list stay with a cleared link', () {
      final result = mergeEnvelopes(
        envelopes: [
          env('a', const [], [taskRow('t1', 'ghost')]),
        ],
        deviceId: 'a',
        now: now,
      );
      final data = result.envelope['data'] as Map<String, Object?>;
      final task = (data['tasks'] as List).single as Map;
      expect(task['listUuid'], isNull);
      expect(task['listId'], isNull);
    });
  });
}
