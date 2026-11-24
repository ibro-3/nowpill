import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/daos/tasks_dao.dart';

/// Feature-level API for task lists (projects, schema v5).
///
/// A list is a soft grouping: deleting one keeps its tasks and moves them to
/// the inbox. Sync identity comes from the table's client defaults.
class TaskListRepository {
  TaskListRepository(this._db);

  final AppDatabase _db;

  TasksDao get _tasks => _db.tasksDao;

  Stream<List<TaskList>> watchAll() => _tasks.watchAllTaskLists();

  Future<List<TaskList>> getAll() => _tasks.getAllTaskLists();

  Future<TaskList?> getById(int id) async {
    final lists = await getAll();
    for (final list in lists) {
      if (list.id == id) return list;
    }
    return null;
  }

  Future<int> create({
    required String name,
    required int color,
    int sortOrder = 0,
  }) {
    return _tasks.insertTaskList(
      TaskListsCompanion.insert(
        name: name,
        color: color,
        sortOrder: Value(sortOrder),
      ),
    );
  }

  Future<bool> update(TaskList list) => _tasks.updateTaskList(list);

  Future<int> delete(int id) => _tasks.deleteTaskList(id);
}
