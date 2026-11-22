import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/domain/recurrence_rule.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late TaskRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = TaskRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('TaskRepository CRUD', () {
    test('create and read a task', () async {
      final id = await repo.create(
        title: 'Write tests',
        notes: 'cover the data layer',
        priority: TaskPriority.high,
      );
      final task = await repo.getById(id);
      expect(task, isNotNull);
      expect(task!.title, 'Write tests');
      expect(task.notes, 'cover the data layer');
      expect(task.priority, TaskPriority.high);
      expect(task.completedAt, isNull);
      expect(task.createdAt.isUtc, isTrue);
    });

    test('update a task', () async {
      final id = await repo.create(title: 'Original');
      final task = await repo.getById(id);
      await repo.update(task!.copyWith(title: 'Renamed'));
      final updated = await repo.getById(id);
      expect(updated!.title, 'Renamed');
    });

    test('delete a task', () async {
      final id = await repo.create(title: 'Doomed');
      await repo.delete(id);
      expect(await repo.getById(id), isNull);
    });

    test('dueAt round-trips as UTC millis', () async {
      final due = DateTime.utc(2026, 11, 22, 9, 30, 15, 500);
      final id = await repo.create(title: 'Due', dueAt: due);
      final task = await repo.getById(id);
      expect(task!.dueAt, due);
      expect(task.dueAt!.isUtc, isTrue);
    });
  });

  group('completion', () {
    test('complete sets completedAt', () async {
      final id = await repo.create(title: 'Finish me');
      await repo.complete(id, at: DateTime.utc(2026, 11, 22));
      final task = await repo.getById(id);
      expect(task!.completedAt, DateTime.utc(2026, 11, 22));
    });

    test('complete is idempotent', () async {
      final id = await repo.create(title: 'Once');
      await repo.complete(id, at: DateTime.utc(2026, 11, 22));
      final second = await repo.complete(id, at: DateTime.utc(2026, 11, 23));
      expect(second, isNull);
      final task = await repo.getById(id);
      expect(task!.completedAt, DateTime.utc(2026, 11, 22));
    });

    test('reopen clears completedAt', () async {
      final id = await repo.create(title: 'Reopen me');
      await repo.complete(id);
      await repo.reopen(id);
      final task = await repo.getById(id);
      expect(task!.completedAt, isNull);
    });

    test('recurring task spawns next occurrence on complete', () async {
      final due = DateTime.utc(2026, 11, 22);
      final id = await repo.create(
        title: 'Daily standup',
        dueAt: due,
        recurrence: const RecurrenceRule(unit: RecurrenceUnit.day),
      );
      final withEngine = TaskRepository(
        db,
        nextDueDate: (anchor, rule) => anchor.add(const Duration(days: 1)),
      );
      final spawnedId = await withEngine.complete(id);
      expect(spawnedId, isNotNull);

      final original = await repo.getById(id);
      expect(original!.completedAt, isNotNull);

      final spawned = await repo.getById(spawnedId!);
      expect(spawned!.title, 'Daily standup');
      expect(spawned.dueAt, DateTime.utc(2026, 11, 23));
      expect(spawned.completedAt, isNull);
      expect(
        spawned.recurrenceRule,
        const RecurrenceRule(unit: RecurrenceUnit.day),
      );
    });

    test('non-recurring task does not spawn', () async {
      final id = await repo.create(
        title: 'One-off',
        dueAt: DateTime.utc(2026, 11, 22),
      );
      final withEngine = TaskRepository(
        db,
        nextDueDate: (anchor, rule) => anchor.add(const Duration(days: 1)),
      );
      expect(await withEngine.complete(id), isNull);
    });
  });

  group('subtasks', () {
    test('add, toggle, and list subtasks', () async {
      final taskId = await repo.create(title: 'Parent');
      final s1 = await repo.addSubtask(taskId, 'step 1', position: 0);
      await repo.addSubtask(taskId, 'step 2', position: 1);

      var subtasks = await repo.getSubtasks(taskId);
      expect(subtasks.length, 2);
      expect(subtasks.every((s) => !s.done), isTrue);

      await repo.setSubtaskDone(s1, true);
      subtasks = await repo.getSubtasks(taskId);
      expect(subtasks.firstWhere((s) => s.id == s1).done, isTrue);
    });

    test('deleting a task cascades to subtasks', () async {
      final taskId = await repo.create(title: 'Parent');
      await repo.addSubtask(taskId, 'child');
      await repo.delete(taskId);
      final remaining = await db.select(db.subtasks).get();
      expect(remaining, isEmpty);
    });
  });

  group('tags', () {
    test('set and read task tags', () async {
      final taskId = await repo.create(title: 'Tagged');
      final tagA = await db.tagsDao.insertTag(
        TagsCompanion.insert(name: 'work', color: 0xFF2DD4A8),
      );
      final tagB = await db.tagsDao.insertTag(
        TagsCompanion.insert(name: 'urgent', color: 0xFFFF6B5E),
      );
      await repo.setTags(taskId, [tagA, tagB]);

      final tags = await db.tagsDao.watchTagsForTask(taskId).first;
      expect(tags.map((t) => t.name), containsAll(['work', 'urgent']));
    });

    test('deleting a tag cascades to task_tags links', () async {
      final taskId = await repo.create(title: 'Tagged');
      final tagId = await db.tagsDao.insertTag(
        TagsCompanion.insert(name: 'temp', color: 0xFF000000),
      );
      await repo.setTags(taskId, [tagId]);
      await db.tagsDao.deleteTag(tagId);
      final links = await db.select(db.taskTags).get();
      expect(links, isEmpty);
    });
  });

  group('streams', () {
    test('watchOpen emits on insert and completion', () async {
      final emissions = <List<Task>>[];
      final sub = repo.watchOpen().listen(emissions.add);
      await pumpEventQueue();

      final id = await repo.create(title: 'Streamed');
      await pumpEventQueue();
      expect(emissions.last.length, 1);

      await repo.complete(id);
      await pumpEventQueue();
      expect(emissions.last, isEmpty);

      await sub.cancel();
    });
  });
}
