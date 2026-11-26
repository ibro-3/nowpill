import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/enums.dart';
import '../../domain/recurrence_rule.dart';
import 'connection.dart';
import 'converters.dart';
import 'daos/chat_notes_dao.dart';
import 'daos/habits_dao.dart';
import 'daos/tags_dao.dart';
import 'daos/tasks_dao.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// The NowPill local database. Offline-first; all feature data lives here.
///
/// Schema version 7 (v0.7.0: v3 adds cross-device sync identity — per-row
/// `uuid` + `updatedAt`, parent uuid references, [Tombstones]; v4 adds
/// measurable habits — `Habits.targetAmount` + `HabitCheckins.amount`; v5 adds
/// task lists — [TaskLists], `Tasks.listId` + `Tasks.listUuid`; v6 adds quit
/// habits — [HabitRelapses], `Habits.kind` — and planned vacation
/// [VacationPeriods]; v7 adds [Routines], habit routine links, scoped
/// vacations [VacationScopes], and `VacationPeriods.allHabits`; v8 adds the
/// personal chat thought stream [ChatNotes]).
/// Foreign keys are enabled in [migration] so cascade deletes (subtasks,
/// task_tags, checkins, freezes) work.
@DriftDatabase(
  tables: [
    TaskLists,
    Tasks,
    Subtasks,
    Tags,
    TaskTags,
    Routines,
    Habits,
    HabitCheckins,
    HabitFreezes,
    HabitRelapses,
    VacationPeriods,
    VacationScopes,
    ChatNotes,
    Tombstones,
  ],
  daos: [TasksDao, HabitsDao, TagsDao, ChatNotesDao],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the platform-appropriate persistent connection.
  AppDatabase({this.deviceId = 'local'}) : super(_open());

  /// Opens with an explicit executor (used by tests with in-memory databases).
  AppDatabase.withExecutor(super.executor, {this.deviceId = 'local'});

  /// Identifies this device in tombstones and sync envelopes. The real app
  /// injects a persisted id (Phase 19); tests default to `local`.
  final String deviceId;

  @override
  int get schemaVersion => 8;

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
      if (from < 3) {
        await _migrateToV3(m);
      }
      if (from < 4) {
        // v0.3.0 measurable habits. Null target = classic habit; null amount
        // = full completion, so existing streaks are unchanged.
        await m.addColumn(habits, habits.targetAmount);
        await m.addColumn(habitCheckins, habitCheckins.amount);
      }
      if (from < 5) {
        await _migrateToV5(m);
      }
      if (from < 6) {
        await _migrateToV6(m);
      }
      if (from < 7) {
        await _migrateToV7(m);
      }
      if (from < 8) {
        await _migrateToV8(m);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// v0.5.0 task lists. Both columns are nullable, so existing tasks stay in
  /// the inbox; the FK uses SET NULL when a list is deleted. The existence
  /// guards also make upgrades from hand-built partial test schemas safe.
  Future<void> _migrateToV5(Migrator m) async {
    if (!await _tableExists('task_lists')) {
      await m.createTable(taskLists);
    }
    if (await _tableExists('tasks')) {
      if (!await _columnExists('tasks', 'list_id')) {
        await m.addColumn(tasks, tasks.listId);
      }
      if (!await _columnExists('tasks', 'list_uuid')) {
        await m.addColumn(tasks, tasks.listUuid);
      }
    }
  }

  /// v0.6.0 quit habits + planned vacation. Existing habits keep kind 0
  /// (build), so every derived streak is byte-identical to v5.
  Future<void> _migrateToV6(Migrator m) async {
    if (!await _tableExists('habit_relapses')) {
      await m.createTable(habitRelapses);
    }
    if (!await _tableExists('vacation_periods')) {
      await m.createTable(vacationPeriods);
    }
    if (await _tableExists('habits') &&
        !await _columnExists('habits', 'kind')) {
      await m.addColumn(habits, habits.kind);
    }
  }

  /// v0.7.0 routines + scoped vacation. Existing vacations get allHabits=true
  /// (their v6 meaning); existing habits are Unrouted.
  Future<void> _migrateToV7(Migrator m) async {
    if (!await _tableExists('routines')) {
      await m.createTable(routines);
    }
    if (!await _tableExists('vacation_scopes')) {
      await m.createTable(vacationScopes);
    }
    if (await _tableExists('habits')) {
      if (!await _columnExists('habits', 'routine_id')) {
        await m.addColumn(habits, habits.routineId);
      }
      if (!await _columnExists('habits', 'routine_uuid')) {
        await m.addColumn(habits, habits.routineUuid);
      }
    }
    if (await _tableExists('vacation_periods') &&
        !await _columnExists('vacation_periods', 'all_habits')) {
      await m.addColumn(vacationPeriods, vacationPeriods.allHabits);
    }
  }

  /// v0.10.0 personal chat. A new standalone table needs no backfill; the
  /// existence guard keeps upgrades from hand-built partial test schemas safe.
  Future<void> _migrateToV8(Migrator m) async {
    if (!await _tableExists('chat_notes')) {
      await m.createTable(chatNotes);
    }
  }

  Future<bool> _tableExists(String name) async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(name)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> _columnExists(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info("$table")').get();
    return rows.any((r) => r.read<String>('name') == column);
  }

  /// v0.3.0 sync identity. Every row gains a uuid + updatedAt; child rows gain
  /// parent uuid references; deletes are tracked in [Tombstones]. Existing
  /// rows are backfilled: uuids are fresh, updatedAt seeds from createdAt
  /// (completedAt for tasks — completion is the latest known mutation), and
  /// parent uuids are resolved from the local integer FKs.
  Future<void> _migrateToV3(Migrator m) async {
    const uuid = Uuid();

    Future<bool> tableExists(String name) async {
      final rows = await customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        variables: [Variable.withString(name)],
      ).get();
      return rows.isNotEmpty;
    }

    Future<bool> columnExists(String table, String column) async {
      final rows = await customSelect('PRAGMA table_info($table)').get();
      return rows.any((r) => r.read<String>('name') == column);
    }

    // A table needs the identity upgrade only if it exists and predates v3
    // (no uuid column). Tables created fresh during this upgrade — e.g.
    // habit_freezes via the v1→v2 step — already carry the v3 columns.
    Future<bool> needsIdentity(String name) async =>
        await tableExists(name) && !await columnExists(name, 'uuid');

    Future<void> addIdentity(String sqlName) async {
      await customStatement(
        "ALTER TABLE $sqlName ADD COLUMN uuid TEXT NOT NULL DEFAULT ''",
      );
      await customStatement(
        'ALTER TABLE $sqlName ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
      );
      // task_tags has a composite PK and no `id`; backfill by rowid instead.
      final keyColumn = sqlName == 'task_tags' ? 'rowid' : 'id';
      final rows = await customSelect('SELECT $keyColumn AS k FROM $sqlName')
          .get();
      for (final row in rows) {
        await customStatement(
          'UPDATE $sqlName SET uuid = ? WHERE $keyColumn = ?',
          [uuid.v4(), row.read<int>('k')],
        );
      }
      await customStatement(
        'CREATE UNIQUE INDEX idx_${sqlName}_uuid ON $sqlName (uuid)',
      );
    }

    if (await needsIdentity('tasks')) {
      await addIdentity('tasks');
      await customStatement(
        'UPDATE tasks SET updated_at = '
        'CASE WHEN completed_at IS NOT NULL AND completed_at > created_at '
        'THEN completed_at ELSE created_at END',
      );
    }

    if (await needsIdentity('habits')) {
      await addIdentity('habits');
      await customStatement('UPDATE habits SET updated_at = created_at');
    }

    if (await needsIdentity('tags')) {
      await addIdentity('tags');
      // Tags have no createdAt; seed 0 (any real edit will win the merge).
      await customStatement('UPDATE tags SET updated_at = 0');
    }

    if (await needsIdentity('subtasks')) {
      await addIdentity('subtasks');
      await customStatement(
        "ALTER TABLE subtasks ADD COLUMN task_uuid TEXT NOT NULL DEFAULT ''",
      );
      await customStatement(
        'UPDATE subtasks SET task_uuid = '
        '(SELECT uuid FROM tasks WHERE tasks.id = subtasks.task_id), '
        'updated_at = (SELECT updated_at FROM tasks WHERE tasks.id = subtasks.task_id)',
      );
    }

    if (await needsIdentity('task_tags')) {
      await addIdentity('task_tags');
      await customStatement(
        "ALTER TABLE task_tags ADD COLUMN task_uuid TEXT NOT NULL DEFAULT ''",
      );
      await customStatement(
        "ALTER TABLE task_tags ADD COLUMN tag_uuid TEXT NOT NULL DEFAULT ''",
      );
      await customStatement(
        'UPDATE task_tags SET '
        'task_uuid = (SELECT uuid FROM tasks WHERE tasks.id = task_tags.task_id), '
        'tag_uuid = (SELECT uuid FROM tags WHERE tags.id = task_tags.tag_id)',
      );
    }

    if (await needsIdentity('habit_checkins')) {
      await addIdentity('habit_checkins');
      await customStatement(
        "ALTER TABLE habit_checkins ADD COLUMN habit_uuid TEXT NOT NULL DEFAULT ''",
      );
      await customStatement(
        'UPDATE habit_checkins SET habit_uuid = '
        '(SELECT uuid FROM habits WHERE habits.id = habit_checkins.habit_id)',
      );
      // Check-ins have no timestamp column; the local day is the best proxy.
      await customStatement(
        'UPDATE habit_checkins SET updated_at = '
        "CAST(strftime('%s', date || 'T12:00:00Z') AS INTEGER) * 1000",
      );
    }

    if (await needsIdentity('habit_freezes')) {
      await addIdentity('habit_freezes');
      await customStatement(
        "ALTER TABLE habit_freezes ADD COLUMN habit_uuid TEXT NOT NULL DEFAULT ''",
      );
      await customStatement(
        'UPDATE habit_freezes SET habit_uuid = '
        '(SELECT uuid FROM habits WHERE habits.id = habit_freezes.habit_id), '
        'updated_at = created_at',
      );
    }

    await m.createTable(tombstones);
  }

  static QueryExecutor _open() {
    return LazyDatabase(() async {
      return openConnection();
    });
  }
}
