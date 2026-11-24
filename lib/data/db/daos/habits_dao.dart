import 'package:drift/drift.dart';

import '../../../domain/enums.dart';
import '../../../domain/vacation.dart' as vacation_domain;
import '../app_database.dart';
import '../tables.dart';

part 'habits_dao.g.dart';

/// Data access for habits, their daily check-ins, and manual freezes.
///
/// Sync-aware (schema v3): updates stamp `updatedAt`, deletes record
/// tombstones (including cascaded check-ins/freezes) so devices converge.
@DriftAccessor(
  tables: [
    Routines,
    Habits,
    HabitCheckins,
    HabitFreezes,
    HabitRelapses,
    VacationPeriods,
    VacationScopes,
    Tombstones,
  ],
)
class HabitsDao extends DatabaseAccessor<AppDatabase> with _$HabitsDaoMixin {
  HabitsDao(super.db);

  // ---------------------------------------------------------------------------
  // Habits
  // ---------------------------------------------------------------------------

  /// Active (non-archived) habits.
  Stream<List<Habit>> watchActiveHabits() {
    return (select(habits)
          ..where((h) => h.archivedAt.isNull())
          ..orderBy([
            (h) => OrderingTerm(expression: h.sortOrder),
            (h) => OrderingTerm(expression: h.createdAt),
          ]))
        .watch();
  }

  /// All habits including archived (for export / management).
  Stream<List<Habit>> watchAllHabits() {
    return (select(habits)..orderBy([
          (h) => OrderingTerm(expression: h.sortOrder),
          (h) => OrderingTerm(expression: h.createdAt),
        ]))
        .watch();
  }

  Stream<Habit?> watchHabit(int id) {
    return (select(habits)..where((h) => h.id.equals(id))).watchSingleOrNull();
  }

  Future<Habit?> getHabit(int id) {
    return (select(habits)..where((h) => h.id.equals(id))).getSingleOrNull();
  }

  /// All habits including archived, one-shot (for the reminder coordinator).
  Future<List<Habit>> getAllHabits() => select(habits).get();

  Future<int> insertHabit(HabitsCompanion entry) => into(habits).insert(entry);

  Future<bool> updateHabit(Habit entry) =>
      update(habits).replace(entry.copyWith(updatedAt: DateTime.now().toUtc()));

  Future<int> deleteHabit(int id) async {
    return attachedDatabase.transaction(() async {
      final habit = await getHabit(id);
      if (habit == null) return 0;
      final now = DateTime.now().toUtc();
      final deviceId = attachedDatabase.deviceId;

      // Tombstone cascaded children before the parent delete removes them.
      final checkins = await (select(
        habitCheckins,
      )..where((c) => c.habitId.equals(id))).get();
      final freezes = await (select(
        habitFreezes,
      )..where((f) => f.habitId.equals(id))).get();
      final relapses = await (select(
        habitRelapses,
      )..where((r) => r.habitId.equals(id))).get();
      final scopes =
          await (select(vacationScopes)..where(
                (s) =>
                    s.targetKind.equals(VacationTargetKind.habit.index) &
                    s.targetUuid.equals(habit.uuid),
              ))
              .get();
      await batch((b) {
        b.insertAll(tombstones, [
          TombstonesCompanion.insert(
            uuid: habit.uuid,
            sourceTable: 'habits',
            deletedAt: now,
            deviceId: deviceId,
          ),
          for (final c in checkins)
            TombstonesCompanion.insert(
              uuid: c.uuid,
              sourceTable: 'habit_checkins',
              deletedAt: now,
              deviceId: deviceId,
            ),
          for (final f in freezes)
            TombstonesCompanion.insert(
              uuid: f.uuid,
              sourceTable: 'habit_freezes',
              deletedAt: now,
              deviceId: deviceId,
            ),
          for (final r in relapses)
            TombstonesCompanion.insert(
              uuid: r.uuid,
              sourceTable: 'habit_relapses',
              deletedAt: now,
              deviceId: deviceId,
            ),
          for (final s in scopes)
            TombstonesCompanion.insert(
              uuid: s.uuid,
              sourceTable: 'vacation_scopes',
              deletedAt: now,
              deviceId: deviceId,
            ),
        ], mode: InsertMode.insertOrReplace);
      });
      await (delete(vacationScopes)..where(
            (s) =>
                s.targetKind.equals(VacationTargetKind.habit.index) &
                s.targetUuid.equals(habit.uuid),
          ))
          .go();
      return (delete(habits)..where((h) => h.id.equals(id))).go();
    });
  }

  // ---------------------------------------------------------------------------
  // Check-ins
  // ---------------------------------------------------------------------------

  /// All check-ins for a habit, oldest first (the streak engine replays these).
  Stream<List<HabitCheckin>> watchCheckins(int habitId) {
    return (select(habitCheckins)
          ..where((c) => c.habitId.equals(habitId))
          ..orderBy([(c) => OrderingTerm(expression: c.date)]))
        .watch();
  }

  Future<List<HabitCheckin>> getCheckins(int habitId) {
    return (select(habitCheckins)
          ..where((c) => c.habitId.equals(habitId))
          ..orderBy([(c) => OrderingTerm(expression: c.date)]))
        .get();
  }

  /// Check-ins for a habit within an inclusive date range (`yyyy-MM-dd`).
  Future<List<HabitCheckin>> getCheckinsInRange(
    int habitId,
    String from,
    String to,
  ) {
    return (select(habitCheckins)
          ..where(
            (c) =>
                c.habitId.equals(habitId) &
                c.date.isBiggerOrEqualValue(from) &
                c.date.isSmallerOrEqualValue(to),
          )
          ..orderBy([(c) => OrderingTerm(expression: c.date)]))
        .get();
  }

  /// All check-ins (for export and cross-habit stats).
  Stream<List<HabitCheckin>> watchAllCheckins() {
    return (select(
      habitCheckins,
    )..orderBy([(c) => OrderingTerm(expression: c.date)])).watch();
  }

  Future<List<HabitCheckin>> getAllCheckins() => select(habitCheckins).get();

  /// Adds or updates a check-in. Returns the row id, or -1 when a classic
  /// (non-measurable) check-in already exists for that habit+date. The unique
  /// constraint is the source of truth; the pre-check gives a stable "already
  /// exists" signal (drift's DO NOTHING returns the connection's last rowid,
  /// which is not a reliable sentinel).
  ///
  /// When the companion's `amount` is present (measurable habits, schema v4)
  /// an existing row is updated in place — keeping its uuid so the change
  /// merges as an edit, not a delete+recreate — and stamped with a fresh
  /// `updatedAt`.
  ///
  /// Re-checking a previously removed day revives the original row uuid (the
  /// row is gone locally but its tombstone may have propagated) and stamps a
  /// fresh `updatedAt`, so the new check-in wins the merge on other devices.
  Future<int> checkIn(HabitCheckinsCompanion entry) async {
    final existing =
        await (select(habitCheckins)..where(
              (c) =>
                  c.habitId.equals(entry.habitId.value) &
                  c.date.equals(entry.date.value),
            ))
            .getSingleOrNull();
    final habit = await getHabit(entry.habitId.value);
    if (habit == null) {
      throw StateError('Cannot check in missing habit ${entry.habitId.value}');
    }
    if (existing != null) {
      // Only a non-null amount (measurable habit) updates in place; classic
      // check-ins stay idempotent.
      if (entry.amount.value == null) return -1;
      await (update(
        habitCheckins,
      )..where((c) => c.id.equals(existing.id))).write(
        HabitCheckinsCompanion(
          amount: entry.amount,
          note: entry.note.present ? entry.note : const Value.absent(),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      return existing.id;
    }
    return into(habitCheckins).insert(
      entry.copyWith(habitUuid: Value(habit.uuid)),
      onConflict: DoNothing(
        target: [habitCheckins.habitId, habitCheckins.date],
      ),
    );
  }

  /// Removes a check-in for a specific day (backfill undo). Tombstones the row
  /// so the undo propagates to other devices.
  Future<int> removeCheckIn(int habitId, String date) async {
    return attachedDatabase.transaction(() async {
      final row =
          await (select(habitCheckins)
                ..where((c) => c.habitId.equals(habitId) & c.date.equals(date)))
              .getSingleOrNull();
      if (row == null) return 0;
      await into(tombstones).insert(
        TombstonesCompanion.insert(
          uuid: row.uuid,
          sourceTable: 'habit_checkins',
          deletedAt: DateTime.now().toUtc(),
          deviceId: attachedDatabase.deviceId,
        ),
        mode: InsertMode.insertOrReplace,
      );
      return (delete(
        habitCheckins,
      )..where((c) => c.habitId.equals(habitId) & c.date.equals(date))).go();
    });
  }

  Future<int> deleteCheckIn(int id) async {
    return attachedDatabase.transaction(() async {
      final row = await (select(
        habitCheckins,
      )..where((c) => c.id.equals(id))).getSingleOrNull();
      if (row == null) return 0;
      await into(tombstones).insert(
        TombstonesCompanion.insert(
          uuid: row.uuid,
          sourceTable: 'habit_checkins',
          deletedAt: DateTime.now().toUtc(),
          deviceId: attachedDatabase.deviceId,
        ),
        mode: InsertMode.insertOrReplace,
      );
      return (delete(habitCheckins)..where((c) => c.id.equals(id))).go();
    });
  }

  // ---------------------------------------------------------------------------
  // Manual freezes (schema v2)
  // ---------------------------------------------------------------------------

  /// Explicit freezes for a habit, oldest first.
  Stream<List<HabitFreeze>> watchFreezes(int habitId) {
    return (select(habitFreezes)
          ..where((f) => f.habitId.equals(habitId))
          ..orderBy([(f) => OrderingTerm(expression: f.date)]))
        .watch();
  }

  Future<List<HabitFreeze>> getFreezes(int habitId) {
    return (select(habitFreezes)
          ..where((f) => f.habitId.equals(habitId))
          ..orderBy([(f) => OrderingTerm(expression: f.date)]))
        .get();
  }

  /// All freezes (for export).
  Future<List<HabitFreeze>> getAllFreezes() => select(habitFreezes).get();

  /// Places an explicit freeze. Returns the new row id, or -1 if one already
  /// exists for that habit+date (idempotent, mirrors [checkIn]).
  Future<int> placeFreeze(HabitFreezesCompanion entry) async {
    final existing =
        await (select(habitFreezes)..where(
              (f) =>
                  f.habitId.equals(entry.habitId.value) &
                  f.date.equals(entry.date.value),
            ))
            .getSingleOrNull();
    if (existing != null) return -1;
    final habit = await getHabit(entry.habitId.value);
    if (habit == null) {
      throw StateError('Cannot freeze missing habit ${entry.habitId.value}');
    }
    return into(habitFreezes).insert(
      entry.copyWith(habitUuid: Value(habit.uuid)),
      onConflict: DoNothing(target: [habitFreezes.habitId, habitFreezes.date]),
    );
  }

  /// Removes an explicit freeze (refund). Returns rows removed. Tombstones the
  /// row so the refund propagates to other devices.
  Future<int> removeFreeze(int habitId, String date) async {
    return attachedDatabase.transaction(() async {
      final row =
          await (select(habitFreezes)
                ..where((f) => f.habitId.equals(habitId) & f.date.equals(date)))
              .getSingleOrNull();
      if (row == null) return 0;
      await into(tombstones).insert(
        TombstonesCompanion.insert(
          uuid: row.uuid,
          sourceTable: 'habit_freezes',
          deletedAt: DateTime.now().toUtc(),
          deviceId: attachedDatabase.deviceId,
        ),
        mode: InsertMode.insertOrReplace,
      );
      return (delete(
        habitFreezes,
      )..where((f) => f.habitId.equals(habitId) & f.date.equals(date))).go();
    });
  }

  // ---------------------------------------------------------------------------
  // Quit-habit relapses (schema v6)
  // ---------------------------------------------------------------------------

  Stream<List<HabitRelapse>> watchRelapses(int habitId) {
    return (select(habitRelapses)
          ..where((r) => r.habitId.equals(habitId))
          ..orderBy([(r) => OrderingTerm(expression: r.date)]))
        .watch();
  }

  Future<List<HabitRelapse>> getRelapses(int habitId) {
    return (select(habitRelapses)
          ..where((r) => r.habitId.equals(habitId))
          ..orderBy([(r) => OrderingTerm(expression: r.date)]))
        .get();
  }

  Stream<List<HabitRelapse>> watchAllRelapses() =>
      select(habitRelapses).watch();

  Future<List<HabitRelapse>> getAllRelapses() => select(habitRelapses).get();

  /// Logs one relapse per habit per day. Idempotent: re-logging the same day
  /// is a no-op rather than a second event.
  Future<int> logRelapse(HabitRelapsesCompanion entry) async {
    final existing =
        await (select(habitRelapses)..where(
              (r) =>
                  r.habitId.equals(entry.habitId.value) &
                  r.date.equals(entry.date.value),
            ))
            .getSingleOrNull();
    if (existing != null) return -1;
    final habit = await getHabit(entry.habitId.value);
    if (habit == null) {
      throw StateError(
        'Cannot log relapse for missing habit ${entry.habitId.value}',
      );
    }
    return into(habitRelapses).insert(
      entry.copyWith(habitUuid: Value(habit.uuid)),
      onConflict: DoNothing(
        target: [habitRelapses.habitId, habitRelapses.date],
      ),
    );
  }

  /// Removes a relapse entry (undo). Tombstoned so the undo propagates.
  Future<int> removeRelapse(int habitId, String date) async {
    return attachedDatabase.transaction(() async {
      final row =
          await (select(habitRelapses)
                ..where((r) => r.habitId.equals(habitId) & r.date.equals(date)))
              .getSingleOrNull();
      if (row == null) return 0;
      await into(tombstones).insert(
        TombstonesCompanion.insert(
          uuid: row.uuid,
          sourceTable: 'habit_relapses',
          deletedAt: DateTime.now().toUtc(),
          deviceId: attachedDatabase.deviceId,
        ),
        mode: InsertMode.insertOrReplace,
      );
      return (delete(
        habitRelapses,
      )..where((r) => r.habitId.equals(habitId) & r.date.equals(date))).go();
    });
  }

  // ---------------------------------------------------------------------------
  // Planned vacation (schema v6)
  // ---------------------------------------------------------------------------

  Stream<List<VacationPeriod>> watchVacationPeriods() {
    return (select(
      vacationPeriods,
    )..orderBy([(p) => OrderingTerm(expression: p.startDate)])).watch();
  }

  Future<List<VacationPeriod>> getAllVacationPeriods() =>
      select(vacationPeriods).get();

  Future<int> insertVacationPeriod(VacationPeriodsCompanion entry) =>
      into(vacationPeriods).insert(entry);

  Future<bool> updateVacationPeriod(VacationPeriod entry) =>
      update(vacationPeriods)
          .replace(entry.copyWith(updatedAt: DateTime.now().toUtc()));

  /// Deleting a planned vacation tombstones its scopes too.
  Future<int> deleteVacationPeriod(int id) async {
    return attachedDatabase.transaction(() async {
      final row = await (select(
        vacationPeriods,
      )..where((p) => p.id.equals(id))).getSingleOrNull();
      if (row == null) return 0;
      final now = DateTime.now().toUtc();
      final scopes = await (select(
        vacationScopes,
      )..where((s) => s.periodUuid.equals(row.uuid))).get();
      await batch((b) {
        b.insertAll(tombstones, [
          TombstonesCompanion.insert(
            uuid: row.uuid,
            sourceTable: 'vacation_periods',
            deletedAt: now,
            deviceId: attachedDatabase.deviceId,
          ),
          for (final s in scopes)
            TombstonesCompanion.insert(
              uuid: s.uuid,
              sourceTable: 'vacation_scopes',
              deletedAt: now,
              deviceId: attachedDatabase.deviceId,
            ),
        ], mode: InsertMode.insertOrReplace);
      });
      await (delete(
        vacationScopes,
      )..where((s) => s.periodUuid.equals(row.uuid))).go();
      return (delete(vacationPeriods)..where((p) => p.id.equals(id))).go();
    });
  }

  // ---------------------------------------------------------------------------
  // Routines (schema v7)
  // ---------------------------------------------------------------------------

  Stream<List<Routine>> watchRoutines() {
    return (select(routines)..orderBy([
          (r) => OrderingTerm(expression: r.sortOrder),
          (r) => OrderingTerm(expression: r.name),
        ]))
        .watch();
  }

  Future<List<Routine>> getAllRoutines() => select(routines).get();

  Future<int> insertRoutine(RoutinesCompanion entry) =>
      into(routines).insert(entry);

  Future<bool> updateRoutine(Routine entry) =>
      update(routines)
          .replace(entry.copyWith(updatedAt: DateTime.now().toUtc()));

  /// Deleting a routine never deletes habits: the FK clears `routine_id`, and
  /// we explicitly clear `routine_uuid` + drop scopes targeting the routine.
  Future<int> deleteRoutine(int id) async {
    return attachedDatabase.transaction(() async {
      final routine = await (select(
        routines,
      )..where((r) => r.id.equals(id))).getSingleOrNull();
      if (routine == null) return 0;
      final now = DateTime.now().toUtc();
      final scopes =
          await (select(vacationScopes)..where(
                (s) =>
                    s.targetKind.equals(VacationTargetKind.routine.index) &
                    s.targetUuid.equals(routine.uuid),
              ))
              .get();
      await batch((b) {
        b.insertAll(tombstones, [
          TombstonesCompanion.insert(
            uuid: routine.uuid,
            sourceTable: 'routines',
            deletedAt: now,
            deviceId: attachedDatabase.deviceId,
          ),
          for (final s in scopes)
            TombstonesCompanion.insert(
              uuid: s.uuid,
              sourceTable: 'vacation_scopes',
              deletedAt: now,
              deviceId: attachedDatabase.deviceId,
            ),
        ], mode: InsertMode.insertOrReplace);
      });
      await (update(
        habits,
      )..where((h) => h.routineUuid.equals(routine.uuid))).write(
        HabitsCompanion(routineUuid: const Value(null), updatedAt: Value(now)),
      );
      await (delete(vacationScopes)..where(
            (s) =>
                s.targetKind.equals(VacationTargetKind.routine.index) &
                s.targetUuid.equals(routine.uuid),
          ))
          .go();
      return (delete(routines)..where((r) => r.id.equals(id))).go();
    });
  }

  /// Assigns a habit to a routine (or clears it with null). Both local ids
  /// are device-private; `routineUuid` is the sync identity.
  Future<bool> setHabitRoutine(int habitId, Routine? routine) async {
    final habit = await getHabit(habitId);
    if (habit == null) return false;
    return update(habits).replace(
      habit.copyWith(
        routineId: Value(routine?.id),
        routineUuid: Value(routine?.uuid),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Vacation scopes (schema v7)
  // ---------------------------------------------------------------------------

  Stream<List<VacationScope>> watchVacationScopes() =>
      select(vacationScopes).watch();

  Future<List<VacationScope>> getAllVacationScopes() =>
      select(vacationScopes).get();

  /// Replaces all scopes for a period. Removed rows are tombstoned so remote
  /// devices cannot resurrect them on the next merge.
  Future<void> replaceVacationScopes(
    String periodUuid,
    List<vacation_domain.VacationScope> targets,
  ) async {
    await attachedDatabase.transaction(() async {
      final existing = await (select(
        vacationScopes,
      )..where((s) => s.periodUuid.equals(periodUuid))).get();
      final wanted = targets
          .map((t) => '${t.targetKind.index}:${t.targetUuid}')
          .toSet();
      final removed = existing.where(
        (s) => !wanted.contains('${s.targetKind.index}:${s.targetUuid}'),
      );
      final now = DateTime.now().toUtc();
      if (removed.isNotEmpty) {
        await batch((b) {
          b.insertAll(tombstones, [
            for (final s in removed)
              TombstonesCompanion.insert(
                uuid: s.uuid,
                sourceTable: 'vacation_scopes',
                deletedAt: now,
                deviceId: attachedDatabase.deviceId,
              ),
          ], mode: InsertMode.insertOrReplace);
        });
        await (delete(
          vacationScopes,
        )..where((s) => s.id.isIn(removed.map((s) => s.id)))).go();
      }
      for (final target in targets) {
        final exists = existing.any(
          (s) =>
              s.targetKind == target.targetKind &&
              s.targetUuid == target.targetUuid,
        );
        if (exists) continue;
        await into(vacationScopes).insert(
          VacationScopesCompanion.insert(
            periodUuid: periodUuid,
            targetKind: target.targetKind,
            targetUuid: target.targetUuid,
            uuid: Value(target.uuid.isEmpty ? syncUuid.v4() : target.uuid),
            updatedAt: Value(
              target.updatedAt == 0
                  ? now
                  : DateTime.fromMillisecondsSinceEpoch(
                      target.updatedAt,
                      isUtc: true,
                    ),
            ),
          ),
        );
      }
    });
  }
}
