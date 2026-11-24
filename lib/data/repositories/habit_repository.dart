import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import '../../domain/vacation.dart' as vacation_domain;
import '../db/app_database.dart';
import '../db/daos/habits_dao.dart';

/// Feature-level API for habits and check-ins. Streak/freeze computation is
/// delegated to the pure domain engine (Phase 3); this layer only stores and
/// streams the raw check-in history.
class HabitRepository {
  HabitRepository(this._db);

  final AppDatabase _db;

  HabitsDao get _habits => _db.habitsDao;

  // ---------------------------------------------------------------------------
  // Streams
  // ---------------------------------------------------------------------------

  Stream<List<Habit>> watchActive() => _habits.watchActiveHabits();
  Stream<List<Habit>> watchAll() => _habits.watchAllHabits();
  Stream<Habit?> watchById(int id) => _habits.watchHabit(id);
  Stream<List<HabitCheckin>> watchCheckins(int habitId) =>
      _habits.watchCheckins(habitId);
  Stream<List<HabitCheckin>> watchAllCheckins() => _habits.watchAllCheckins();
  Stream<List<HabitRelapse>> watchRelapses(int habitId) =>
      _habits.watchRelapses(habitId);
  Stream<List<HabitRelapse>> watchAllRelapses() => _habits.watchAllRelapses();
  Stream<List<VacationPeriod>> watchVacationPeriods() =>
      _habits.watchVacationPeriods();
  Stream<List<Routine>> watchRoutines() => _habits.watchRoutines();
  Stream<List<VacationScope>> watchVacationScopes() =>
      _habits.watchVacationScopes();

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  Future<int> create({
    required String name,
    required int color,
    String? notes,
    String iconKey = 'spark',
    HabitScheduleType scheduleType = HabitScheduleType.daily,
    List<int>? weekdays,
    int? targetPerWeek,
    DateTime? reminderTime,
    FreezeMode freezeMode = FreezeMode.auto,
    double? targetAmount,
    int sortOrder = 0,
    HabitKind kind = HabitKind.build,
    DateTime? createdAt,
  }) {
    return _habits.insertHabit(
      HabitsCompanion.insert(
        name: name,
        notes: Value(notes),
        iconKey: Value(iconKey),
        color: color,
        scheduleType: scheduleType,
        weekdays: Value(weekdays),
        targetPerWeek: Value(targetPerWeek),
        reminderTime: Value(reminderTime),
        freezeMode: Value(freezeMode),
        targetAmount: Value(targetAmount),
        // Quit habits use this as the quit date and may backdate it.
        createdAt: (createdAt ?? DateTime.now()).toUtc(),
        sortOrder: Value(sortOrder),
        kind: Value(kind),
      ),
    );
  }

  Future<bool> update(Habit habit) => _habits.updateHabit(habit);

  Future<Habit?> getById(int id) => _habits.getHabit(id);

  /// All habits including archived, one-shot.
  Future<List<Habit>> getAll() => _habits.getAllHabits();

  /// All check-ins across habits, one-shot.
  Future<List<HabitCheckin>> getAllCheckins() => _habits.getAllCheckins();

  /// Archives a habit (keeps history). Returns false if not found.
  Future<bool> archive(int id, {DateTime? at}) async {
    final habit = await _habits.getHabit(id);
    if (habit == null) return false;
    return _habits.updateHabit(
      habit.copyWith(archivedAt: Value((at ?? DateTime.now()).toUtc())),
    );
  }

  /// Restores an archived habit.
  Future<bool> unarchive(int id) async {
    final habit = await _habits.getHabit(id);
    if (habit == null) return false;
    return _habits.updateHabit(habit.copyWith(archivedAt: const Value(null)));
  }

  /// Hard-deletes a habit and (via cascade) all its check-ins.
  Future<int> delete(int id) => _habits.deleteHabit(id);

  // ---------------------------------------------------------------------------
  // Check-ins
  // ---------------------------------------------------------------------------

  /// Checks in a habit for a local calendar day ([date] = `yyyy-MM-dd`).
  ///
  /// Classic habits: idempotent — returns the row id, or -1 if already checked
  /// in. Measurable habits ([amount] given): creates or updates the day's
  /// logged amount in place (returns the row id).
  Future<int> checkIn(
    int habitId,
    String date, {
    String? note,
    double? amount,
  }) {
    return _habits.checkIn(
      HabitCheckinsCompanion(
        habitId: Value(habitId),
        date: Value(date),
        note: Value(note),
        amount: Value(amount),
      ),
    );
  }

  /// Removes a check-in (backfill undo). Returns rows removed.
  Future<int> removeCheckIn(int habitId, String date) =>
      _habits.removeCheckIn(habitId, date);

  Future<List<HabitCheckin>> getCheckins(int habitId) =>
      _habits.getCheckins(habitId);

  Future<List<HabitCheckin>> getCheckinsInRange(
    int habitId,
    String from,
    String to,
  ) => _habits.getCheckinsInRange(habitId, from, to);

  // ---------------------------------------------------------------------------
  // Manual freezes (schema v2)
  // ---------------------------------------------------------------------------

  Stream<List<HabitFreeze>> watchFreezes(int habitId) =>
      _habits.watchFreezes(habitId);

  Future<List<HabitFreeze>> getFreezes(int habitId) =>
      _habits.getFreezes(habitId);

  Future<List<HabitFreeze>> getAllFreezes() => _habits.getAllFreezes();

  /// Sets a habit's freeze mode (auto/manual). Returns false if not found.
  Future<bool> setFreezeMode(int id, FreezeMode mode) async {
    final habit = await _habits.getHabit(id);
    if (habit == null) return false;
    return _habits.updateHabit(habit.copyWith(freezeMode: mode));
  }

  /// Places an explicit freeze for a missed day. Idempotent: returns the row id,
  /// or -1 if one already exists.
  Future<int> placeFreeze(int habitId, String date) {
    return _habits.placeFreeze(
      HabitFreezesCompanion(
        habitId: Value(habitId),
        date: Value(date),
        createdAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Removes an explicit freeze (refund). Returns rows removed.
  Future<int> removeFreeze(int habitId, String date) =>
      _habits.removeFreeze(habitId, date);

  // ---------------------------------------------------------------------------
  // Quit habits (schema v6)
  // ---------------------------------------------------------------------------

  /// Changes a habit's kind. Refused once the habit has history: converting
  /// check-ins to clean days (or vice versa) would change the meaning of its
  /// existing streak data.
  Future<bool> setKind(int id, HabitKind kind) async {
    final habit = await _habits.getHabit(id);
    if (habit == null || habit.kind == kind) return false;
    if ((await _habits.getCheckins(id)).isNotEmpty ||
        (await _habits.getRelapses(id)).isNotEmpty) {
      return false;
    }
    return _habits.updateHabit(habit.copyWith(kind: kind));
  }

  /// Backdates or corrects the quit date (the habit's `createdAt`).
  Future<bool> setQuitDate(int id, DateTime date) async {
    final habit = await _habits.getHabit(id);
    if (habit == null || habit.kind != HabitKind.quit) return false;
    return _habits.updateHabit(habit.copyWith(createdAt: date.toUtc()));
  }

  Future<List<HabitRelapse>> getRelapses(int habitId) =>
      _habits.getRelapses(habitId);

  Future<List<HabitRelapse>> getAllRelapses() => _habits.getAllRelapses();

  /// Logs a relapse for a local day (`yyyy-MM-dd`). Idempotent.
  Future<int> logRelapse(int habitId, String date, {String? note}) {
    return _habits.logRelapse(
      HabitRelapsesCompanion(
        habitId: Value(habitId),
        date: Value(date),
        note: Value(note),
      ),
    );
  }

  /// Removes a relapse entry (undo). Returns rows removed.
  Future<int> removeRelapse(int habitId, String date) =>
      _habits.removeRelapse(habitId, date);

  // ---------------------------------------------------------------------------
  // Routines (schema v7)
  // ---------------------------------------------------------------------------

  Future<List<Routine>> getAllRoutines() => _habits.getAllRoutines();

  Future<int> createRoutine(String name, int color, {int sortOrder = 0}) =>
      _habits.insertRoutine(
        RoutinesCompanion.insert(
          name: name,
          color: color,
          sortOrder: Value(sortOrder),
        ),
      );

  Future<bool> updateRoutine(Routine routine) => _habits.updateRoutine(routine);

  /// Deleting a routine ungroups its habits; it never deletes them.
  Future<int> deleteRoutine(int id) => _habits.deleteRoutine(id);

  Future<bool> setHabitRoutine(int habitId, int? routineId) async {
    Routine? routine;
    if (routineId != null) {
      routine = await (_db.select(
        _db.routines,
      )..where((r) => r.id.equals(routineId))).getSingleOrNull();
      if (routine == null) return false;
    }
    return _habits.setHabitRoutine(habitId, routine);
  }

  // ---------------------------------------------------------------------------
  // Planned vacation (schema v6, scoped in v7)
  // ---------------------------------------------------------------------------

  Future<List<VacationPeriod>> getAllVacationPeriods() =>
      _habits.getAllVacationPeriods();

  /// Adds an inclusive date range. Rejects inverted ranges. [allHabits] false
  /// scopes the period to explicit targets (set via [replaceVacationScopes]).
  Future<int> createVacation(
    String start,
    String end, {
    bool allHabits = true,
    String? uuid,
  }) {
    if (start.compareTo(end) > 0) {
      throw ArgumentError.value(end, 'end', 'must not be before start');
    }
    return _habits.insertVacationPeriod(
      VacationPeriodsCompanion.insert(
        startDate: start,
        endDate: end,
        allHabits: Value(allHabits),
        uuid: uuid == null ? const Value.absent() : Value(uuid),
      ),
    );
  }

  Future<bool> updateVacation(VacationPeriod period) =>
      _habits.updateVacationPeriod(period);

  Future<List<VacationScope>> getVacationScopes() =>
      _habits.getAllVacationScopes();

  Future<void> replaceVacationScopes(
    String periodUuid,
    List<vacation_domain.VacationScope> targets,
  ) => _habits.replaceVacationScopes(periodUuid, targets);

  Future<int> deleteVacation(int id) => _habits.deleteVacationPeriod(id);
}
