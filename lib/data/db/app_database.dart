import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import '../../domain/recurrence_rule.dart';
import 'connection.dart';
import 'converters.dart';
import 'daos/habits_dao.dart';
import 'daos/tags_dao.dart';
import 'daos/tasks_dao.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// The NowPill local database. Offline-first; all feature data lives here.
///
/// Schema version 1. Foreign keys are enabled in [migration] so cascade
/// deletes (subtasks, task_tags, checkins) work.
@DriftDatabase(
  tables: [Tasks, Subtasks, Tags, TaskTags, Habits, HabitCheckins],
  daos: [TasksDao, HabitsDao, TagsDao],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the platform-appropriate persistent connection.
  AppDatabase() : super(_open());

  /// Opens with an explicit executor (used by tests with in-memory databases).
  AppDatabase.withExecutor(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static QueryExecutor _open() {
    return LazyDatabase(() async {
      return openConnection();
    });
  }
}
