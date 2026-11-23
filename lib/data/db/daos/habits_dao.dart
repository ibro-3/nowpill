import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'habits_dao.g.dart';

/// Data access for habits, their daily check-ins, and manual freezes.
@DriftAccessor(tables: [Habits, HabitCheckins, HabitFreezes])
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

  Future<bool> updateHabit(Habit entry) => update(habits).replace(entry);

  Future<int> deleteHabit(int id) {
    return (delete(habits)..where((h) => h.id.equals(id))).go();
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

  /// Adds a check-in. Returns the new row id, or -1 if one already exists for
  /// that habit+date. The unique constraint is the source of truth; the
  /// pre-check gives a stable "already exists" signal (drift's DO NOTHING
  /// returns the connection's last rowid, which is not a reliable sentinel).
  Future<int> checkIn(HabitCheckinsCompanion entry) async {
    final existing =
        await (select(habitCheckins)..where(
              (c) =>
                  c.habitId.equals(entry.habitId.value) &
                  c.date.equals(entry.date.value),
            ))
            .getSingleOrNull();
    if (existing != null) return -1;
    return into(habitCheckins).insert(
      entry,
      onConflict: DoNothing(
        target: [habitCheckins.habitId, habitCheckins.date],
      ),
    );
  }

  /// Removes a check-in for a specific day (backfill undo).
  Future<int> removeCheckIn(int habitId, String date) {
    return (delete(
      habitCheckins,
    )..where((c) => c.habitId.equals(habitId) & c.date.equals(date))).go();
  }

  Future<int> deleteCheckIn(int id) {
    return (delete(habitCheckins)..where((c) => c.id.equals(id))).go();
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
    return into(habitFreezes).insert(
      entry,
      onConflict: DoNothing(target: [habitFreezes.habitId, habitFreezes.date]),
    );
  }

  /// Removes an explicit freeze (refund). Returns rows removed.
  Future<int> removeFreeze(int habitId, String date) {
    return (delete(
      habitFreezes,
    )..where((f) => f.habitId.equals(habitId) & f.date.equals(date))).go();
  }
}
