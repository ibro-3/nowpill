import 'package:drift/drift.dart';

import '../../domain/enums.dart';
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
    int sortOrder = 0,
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
        createdAt: DateTime.now().toUtc(),
        sortOrder: Value(sortOrder),
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
  /// Idempotent: returns the row id, or -1 if already checked in.
  Future<int> checkIn(int habitId, String date, {String? note}) {
    return _habits.checkIn(
      HabitCheckinsCompanion.insert(
        habitId: habitId,
        date: date,
        note: Value(note),
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
}
