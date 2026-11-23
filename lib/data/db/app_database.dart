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
/// Schema version 2 (v0.2.0 adds manual freeze mode + the HabitFreezes table).
/// Foreign keys are enabled in [migration] so cascade deletes (subtasks,
/// task_tags, checkins, freezes) work.
@DriftDatabase(
  tables: [
    Tasks,
    Subtasks,
    Tags,
    TaskTags,
    Habits,
    HabitCheckins,
    HabitFreezes,
  ],
  daos: [TasksDao, HabitsDao, TagsDao],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the platform-appropriate persistent connection.
  AppDatabase() : super(_open());

  /// Opens with an explicit executor (used by tests with in-memory databases).
  AppDatabase.withExecutor(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v0.2.0: manual freeze mode. Existing habits default to auto (0), so
        // their derived streaks are unchanged.
        await m.addColumn(habits, habits.freezeMode);
        await m.createTable(habitFreezes);
      }
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
