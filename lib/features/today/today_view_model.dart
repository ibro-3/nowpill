import '../../data/db/app_database.dart';

/// A habit shown in the Today dashboard, paired with whether it is already
/// checked in today.
class TodayHabit {
  const TodayHabit({required this.habit, required this.checkedToday});

  final Habit habit;
  final bool checkedToday;
}

/// Everything the Today dashboard renders, derived reactively from tasks and
/// habit check-ins.
///
/// Sections follow the plan's order: overdue → habits due → tasks due.
/// Completed-today items stay visible (collapsed at the bottom) so the day's
/// progress — and the all-done celebration — remain meaningful after the last
/// check-off.
class TodayViewModel {
  const TodayViewModel({
    required this.overdueTasks,
    required this.dueTodayTasks,
    required this.completedTodayTasks,
    required this.habits,
  });

  static const TodayViewModel empty = TodayViewModel(
    overdueTasks: [],
    dueTodayTasks: [],
    completedTodayTasks: [],
    habits: [],
  );

  /// Open tasks whose due day is strictly before today (stay until done).
  final List<Task> overdueTasks;

  /// Open tasks due on today's calendar day.
  final List<Task> dueTodayTasks;

  /// Tasks completed today (shown struck-through in the Done section).
  final List<Task> completedTodayTasks;

  /// Active habits due today (weekly-target habits are always due), each with
  /// its today check-in state.
  final List<TodayHabit> habits;

  /// Total items that count toward today's progress.
  int get total =>
      overdueTasks.length +
      dueTodayTasks.length +
      completedTodayTasks.length +
      habits.length;

  /// Items already done today.
  int get done =>
      completedTodayTasks.length + habits.where((h) => h.checkedToday).length;

  /// Open items remaining (overdue + due-today tasks + unchecked habits).
  int get remaining => total - done;

  /// 0…1 completion fraction (0 when there is nothing scheduled).
  double get progress => total == 0 ? 0 : done / total;

  /// Whether there is work scheduled and every item is done.
  bool get allDone => total > 0 && remaining == 0;
}
