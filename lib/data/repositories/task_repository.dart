import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import '../../domain/recurrence.dart' as engine;
import '../../domain/recurrence_rule.dart';
import '../db/app_database.dart';
import '../db/daos/tasks_dao.dart';

/// Computes the next due date for a recurring task, anchored to [anchor].
///
/// Defaults to the pure recurrence engine; injectable for testing.
typedef NextDueDateFn = DateTime Function(DateTime anchor, RecurrenceRule rule);

/// Feature-level API for tasks. Wraps `TasksDao` with multi-step operations
/// (completion + recurrence spawn, subtask/tag coordination) and exposes
/// Drift streams for reactive UI.
class TaskRepository {
  TaskRepository(this._db, {NextDueDateFn? nextDueDate})
    : _nextDueDate = nextDueDate ?? engine.nextOccurrence;

  final AppDatabase _db;
  final NextDueDateFn _nextDueDate;

  TasksDao get _tasks => _db.tasksDao;

  // ---------------------------------------------------------------------------
  // Streams
  // ---------------------------------------------------------------------------

  Stream<List<Task>> watchAll() => _tasks.watchAllTasks();
  Stream<List<Task>> watchOpen() => _tasks.watchOpenTasks();
  Stream<List<Task>> watchCompleted() => _tasks.watchCompletedTasks();
  Stream<Task?> watchById(int id) => _tasks.watchTask(id);
  Stream<List<Subtask>> watchSubtasks(int taskId) =>
      _tasks.watchSubtasks(taskId);
  Stream<List<Tag>> watchTags(int taskId) =>
      _db.tagsDao.watchTagsForTask(taskId);

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  Future<int> create({
    required String title,
    String? notes,
    DateTime? dueAt,
    TaskPriority priority = TaskPriority.none,
    RecurrenceRule? recurrence,
    DateTime? reminderAt,
    int sortOrder = 0,
    int? listId,
  }) {
    return _tasks.insertTask(
      TasksCompanion.insert(
        title: title,
        notes: Value(notes),
        dueAt: Value(dueAt),
        priority: priority,
        recurrenceRule: Value(recurrence),
        reminderAt: Value(reminderAt),
        createdAt: DateTime.now().toUtc(),
        sortOrder: Value(sortOrder),
        listId: Value(listId),
      ),
    );
  }

  Future<bool> update(Task task) => _tasks.updateTask(task);

  Future<int> delete(int id) => _tasks.deleteTask(id);

  Future<Task?> getById(int id) => _tasks.getTask(id);

  /// All tasks, one-shot.
  Future<List<Task>> getAll() => _tasks.getAllTasks();

  // ---------------------------------------------------------------------------
  // Completion
  // ---------------------------------------------------------------------------

  /// Marks a task complete. If it is recurring, spawns the next occurrence
  /// using the recurrence engine (history is preserved on the completed row).
  /// Returns the spawned task's id, or null for one-off tasks.
  ///
  /// Runs in a transaction so completion + spawn are atomic.
  Future<int?> complete(int id, {DateTime? at}) async {
    final completedAt = (at ?? DateTime.now()).toUtc();
    return _db.transaction(() async {
      final task = await _tasks.getTask(id);
      if (task == null || task.completedAt != null) return null;

      await _tasks.updateTask(task.copyWith(completedAt: Value(completedAt)));

      final rule = task.recurrenceRule;
      final anchor = task.dueAt;
      if (rule == null || anchor == null) return null;

      final nextDue = _nextDueDate(anchor, rule);
      return _tasks.insertTask(
        TasksCompanion.insert(
          title: task.title,
          notes: Value(task.notes),
          dueAt: Value(nextDue),
          priority: task.priority,
          recurrenceRule: Value(rule),
          reminderAt: Value(task.reminderAt),
          createdAt: completedAt,
          sortOrder: Value(task.sortOrder),
          listId: Value(task.listId),
        ),
      );
    });
  }

  /// Reopens a completed task.
  Future<bool> reopen(int id) async {
    final task = await _tasks.getTask(id);
    if (task == null) return false;
    return _tasks.updateTask(task.copyWith(completedAt: const Value(null)));
  }

  // ---------------------------------------------------------------------------
  // Subtasks
  // ---------------------------------------------------------------------------

  Future<int> addSubtask(int taskId, String title, {int position = 0}) {
    return _tasks.insertSubtask(
      SubtasksCompanion(
        taskId: Value(taskId),
        title: Value(title),
        position: Value(position),
      ),
    );
  }

  Future<bool> setSubtaskDone(int subtaskId, bool done) async {
    final subtask = await (_db.select(
      _db.subtasks,
    )..where((s) => s.id.equals(subtaskId))).getSingleOrNull();
    if (subtask == null) return false;
    return _tasks.updateSubtask(subtask.copyWith(done: done));
  }

  Future<int> deleteSubtask(int id) => _tasks.deleteSubtask(id);

  Future<bool> updateSubtask(Subtask subtask) => _tasks.updateSubtask(subtask);

  Future<List<Subtask>> getSubtasks(int taskId) => _tasks.getSubtasks(taskId);

  // ---------------------------------------------------------------------------
  // Tags
  // ---------------------------------------------------------------------------

  Future<void> setTags(int taskId, Iterable<int> tagIds) =>
      _tasks.setTaskTags(taskId, tagIds);

  /// All task→tag links, reactive (for tag filtering).
  Stream<List<TaskTag>> watchAllTaskTags() => _tasks.watchAllTaskTags();

  /// All task→tag links, one-shot.
  Future<List<TaskTag>> getAllTaskTags() => _tasks.getAllTaskTags();

  /// All subtasks across tasks, reactive (for search).
  Stream<List<Subtask>> watchAllSubtasks() => _tasks.watchAllSubtasks();
}
