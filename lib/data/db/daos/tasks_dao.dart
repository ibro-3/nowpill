import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'tasks_dao.g.dart';

/// Data access for tasks, their subtasks, and tag links.
@DriftAccessor(tables: [Tasks, Subtasks, TaskTags])
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

  Future<bool> updateTask(Task entry) => update(tasks).replace(entry);

  Future<int> deleteTask(int id) {
    return (delete(tasks)..where((t) => t.id.equals(id))).go();
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

  Future<int> insertSubtask(SubtasksCompanion entry) =>
      into(subtasks).insert(entry);

  Future<bool> updateSubtask(Subtask entry) => update(subtasks).replace(entry);

  Future<int> deleteSubtask(int id) {
    return (delete(subtasks)..where((s) => s.id.equals(id))).go();
  }

  // ---------------------------------------------------------------------------
  // Tag links
  // ---------------------------------------------------------------------------

  Stream<List<TaskTag>> watchTaskTags(int taskId) {
    return (select(taskTags)..where((tt) => tt.taskId.equals(taskId))).watch();
  }

  /// Replaces the full set of tag links for a task.
  Future<void> setTaskTags(int taskId, Iterable<int> tagIds) async {
    await (delete(taskTags)..where((tt) => tt.taskId.equals(taskId))).go();
    await batch((b) {
      b.insertAll(
        taskTags,
        tagIds.map(
          (tagId) => TaskTagsCompanion.insert(taskId: taskId, tagId: tagId),
        ),
      );
    });
  }

  /// All tag links (for export and aggregate views).
  Future<List<TaskTag>> getAllTaskTags() => select(taskTags).get();

  /// All tag links, reactive (for tag filtering).
  Stream<List<TaskTag>> watchAllTaskTags() => select(taskTags).watch();
}
