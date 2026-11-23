import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'tasks_dao.g.dart';

/// Data access for tasks, their subtasks, and tag links.
///
/// Sync-aware (schema v3): updates stamp `updatedAt`, deletes record
/// tombstones (including cascaded children) so other devices converge.
@DriftAccessor(tables: [Tasks, Subtasks, TaskTags, Tags, Tombstones])
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

  Future<int> insertTask(TasksCompanion entry) => into(tasks).insert(entry);

  Future<bool> updateTask(Task entry) =>
      update(tasks).replace(entry.copyWith(updatedAt: DateTime.now().toUtc()));

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
}
