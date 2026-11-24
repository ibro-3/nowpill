import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'tasks_dao.g.dart';

/// Data access for tasks, their subtasks, and tag links.
///
/// Sync-aware (schema v3): updates stamp `updatedAt`, deletes record
/// tombstones (including cascaded children) so other devices converge.
@DriftAccessor(tables: [TaskLists, Tasks, Subtasks, TaskTags, Tags, Tombstones])
class TasksDao extends DatabaseAccessor<AppDatabase> with _$TasksDaoMixin {
  TasksDao(super.db);

  // ---------------------------------------------------------------------------
  // Tasks
  // ---------------------------------------------------------------------------

  /// All tasks, newest first.
  Stream<List<Task>> watchAllTasks() {
    return (select(tasks)..orderBy([
          (t) => OrderingTerm(expression: t.sortOrder),
          (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
        ]))
        .watch();
  }

  /// All tasks, one-shot (for the reminder coordinator).
  Future<List<Task>> getAllTasks() => select(tasks).get();

  /// Tasks that are not completed.
  Stream<List<Task>> watchOpenTasks() {
    return (select(tasks)
          ..where((t) => t.completedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm(expression: t.sortOrder),
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  /// Completed tasks, most recently completed first.
  Stream<List<Task>> watchCompletedTasks() {
    return (select(tasks)
          ..where((t) => t.completedAt.isNotNull())
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.completedAt,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  Stream<Task?> watchTask(int id) {
    return (select(tasks)..where((t) => t.id.equals(id))).watchSingleOrNull();
  }

  Future<Task?> getTask(int id) {
    return (select(tasks)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Looks up the stable uuid for a task's list id. A missing/unknown list
  /// produces a null uuid (inbox), never a dangling reference.
  Future<String?> _listUuid(int? listId) async {
    if (listId == null) return null;
    final list = await (select(
      taskLists,
    )..where((l) => l.id.equals(listId))).getSingleOrNull();
    return list?.uuid;
  }

  Future<int> insertTask(TasksCompanion entry) async {
    final resolved = entry.copyWith(
      listUuid: Value(
        await _listUuid(entry.listId.present ? entry.listId.value : null),
      ),
    );
    return into(tasks).insert(resolved);
  }

  Future<bool> updateTask(Task entry) async {
    final resolved = entry.copyWith(
      listUuid: Value(await _listUuid(entry.listId)),
    );
    return update(tasks)
        .replace(resolved.copyWith(updatedAt: DateTime.now().toUtc()));
  }

  Future<int> deleteTask(int id) async {
    return attachedDatabase.transaction(() async {
      final task = await getTask(id);
      if (task == null) return 0;
      final now = DateTime.now().toUtc();
      final deviceId = attachedDatabase.deviceId;

      // Tombstone cascaded children before the parent delete removes them.
      final subs = await (select(
        subtasks,
      )..where((s) => s.taskId.equals(id))).get();
      final links = await (select(
        taskTags,
      )..where((tt) => tt.taskId.equals(id))).get();
      await batch((b) {
        b.insertAll(tombstones, [
          TombstonesCompanion.insert(
            uuid: task.uuid,
            sourceTable: 'tasks',
            deletedAt: now,
            deviceId: deviceId,
          ),
          for (final s in subs)
            TombstonesCompanion.insert(
              uuid: s.uuid,
              sourceTable: 'subtasks',
              deletedAt: now,
              deviceId: deviceId,
            ),
          for (final l in links)
            TombstonesCompanion.insert(
              uuid: l.uuid,
              sourceTable: 'task_tags',
              deletedAt: now,
              deviceId: deviceId,
            ),
        ], mode: InsertMode.insertOrReplace);
      });
      return (delete(tasks)..where((t) => t.id.equals(id))).go();
    });
  }

  // ---------------------------------------------------------------------------
  // Subtasks
  // ---------------------------------------------------------------------------

  Stream<List<Subtask>> watchSubtasks(int taskId) {
    return (select(subtasks)
          ..where((s) => s.taskId.equals(taskId))
          ..orderBy([(s) => OrderingTerm(expression: s.position)]))
        .watch();
  }

  Future<List<Subtask>> getSubtasks(int taskId) {
    return (select(subtasks)
          ..where((s) => s.taskId.equals(taskId))
          ..orderBy([(s) => OrderingTerm(expression: s.position)]))
        .get();
  }

  /// All subtasks across tasks (for search).
  Stream<List<Subtask>> watchAllSubtasks() => select(subtasks).watch();

  /// Inserts a subtask, resolving the parent task's uuid for sync.
  Future<int> insertSubtask(SubtasksCompanion entry) async {
    final parent = await getTask(entry.taskId.value);
    if (parent == null) {
      throw StateError(
        'Cannot add a subtask to missing task ${entry.taskId.value}',
      );
    }
    return into(subtasks).insert(entry.copyWith(taskUuid: Value(parent.uuid)));
  }

  Future<bool> updateSubtask(Subtask entry) =>
      update(subtasks)
          .replace(entry.copyWith(updatedAt: DateTime.now().toUtc()));

  Future<int> deleteSubtask(int id) async {
    return attachedDatabase.transaction(() async {
      final sub = await (select(
        subtasks,
      )..where((s) => s.id.equals(id))).getSingleOrNull();
      if (sub == null) return 0;
      await into(tombstones).insert(
        TombstonesCompanion.insert(
          uuid: sub.uuid,
          sourceTable: 'subtasks',
          deletedAt: DateTime.now().toUtc(),
          deviceId: attachedDatabase.deviceId,
        ),
        mode: InsertMode.insertOrReplace,
      );
      return (delete(subtasks)..where((s) => s.id.equals(id))).go();
    });
  }

  // ---------------------------------------------------------------------------
  // Tag links
  // ---------------------------------------------------------------------------

  Stream<List<TaskTag>> watchTaskTags(int taskId) {
    return (select(taskTags)..where((tt) => tt.taskId.equals(taskId))).watch();
  }

  /// Replaces the full set of tag links for a task. Removed links are
  /// tombstoned so other devices drop them; kept links keep their identity.
  Future<void> setTaskTags(int taskId, Iterable<int> tagIds) async {
    await attachedDatabase.transaction(() async {
      final task = await getTask(taskId);
      if (task == null) return;
      final wanted = tagIds.toSet();
      final existing = await (select(
        taskTags,
      )..where((tt) => tt.taskId.equals(taskId))).get();
      final now = DateTime.now().toUtc();

      final removed = existing.where((l) => !wanted.contains(l.tagId));
      await batch((b) {
        b.insertAll(
          tombstones,
          removed.map(
            (l) => TombstonesCompanion.insert(
              uuid: l.uuid,
              sourceTable: 'task_tags',
              deletedAt: now,
              deviceId: attachedDatabase.deviceId,
            ),
          ),
          mode: InsertMode.insertOrReplace,
        );
      });
      await (delete(
            taskTags,
          )..where((tt) => tt.taskId.equals(taskId) & tt.tagId.isNotIn(wanted)))
          .go();

      final kept = existing.map((l) => l.tagId).toSet();
      final added = wanted.where((tagId) => !kept.contains(tagId));
      for (final tagId in added) {
        final tag = await (select(
          tags,
        )..where((t) => t.id.equals(tagId))).getSingleOrNull();
        if (tag == null) continue;
        await into(taskTags).insert(
          TaskTagsCompanion.insert(
            taskId: taskId,
            tagId: tagId,
            taskUuid: task.uuid,
            tagUuid: tag.uuid,
          ),
        );
      }
    });
  }

  /// All tag links (for export and aggregate views).
  Future<List<TaskTag>> getAllTaskTags() => select(taskTags).get();

  /// All tag links, reactive (for tag filtering).
  Stream<List<TaskTag>> watchAllTaskTags() => select(taskTags).watch();

  // ---------------------------------------------------------------------------
  // Task lists (schema v5)
  // ---------------------------------------------------------------------------

  Stream<List<TaskList>> watchAllTaskLists() {
    return (select(taskLists)..orderBy([
          (l) => OrderingTerm(expression: l.sortOrder),
          (l) => OrderingTerm(expression: l.name),
        ]))
        .watch();
  }

  Future<List<TaskList>> getAllTaskLists() => select(taskLists).get();

  Future<int> insertTaskList(TaskListsCompanion entry) =>
      into(taskLists).insert(entry);

  Future<bool> updateTaskList(TaskList entry) =>
      update(taskLists)
          .replace(entry.copyWith(updatedAt: DateTime.now().toUtc()));

  /// Deleting a list never deletes its tasks: the FK clears `listId`, and we
  /// clear `listUuid` explicitly so the rows stay inbox-style after a sync.
  Future<int> deleteTaskList(int id) async {
    return attachedDatabase.transaction(() async {
      final list = await (select(
        taskLists,
      )..where((l) => l.id.equals(id))).getSingleOrNull();
      if (list == null) return 0;

      await into(tombstones).insert(
        TombstonesCompanion.insert(
          uuid: list.uuid,
          sourceTable: 'task_lists',
          deletedAt: DateTime.now().toUtc(),
          deviceId: attachedDatabase.deviceId,
        ),
        mode: InsertMode.insertOrReplace,
      );

      await (update(tasks)..where((t) => t.listUuid.equals(list.uuid))).write(
        TasksCompanion(
          listUuid: const Value(null),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

      return (delete(taskLists)..where((l) => l.id.equals(id))).go();
    });
  }
}
