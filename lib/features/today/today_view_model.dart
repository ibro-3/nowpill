import '../../data/db/app_database.dart';
import '../../domain/date_utils.dart';
import '../../domain/schedule.dart';

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

/// Computes the Today view model from raw rows. Shared by the dashboard
/// provider and the home-screen widget snapshot so both stay in lockstep.
TodayViewModel computeTodayViewModel({
  required List<Task> tasks,
  required List<Habit> habits,
  required List<HabitCheckin> checkins,
  required DateTime now,
}) {
  final todayKey = formatDate(now);

  final overdue = <Task>[];
  final dueToday = <Task>[];
  final completedToday = <Task>[];
  for (final task in tasks) {
    final completed = task.completedAt != null;
    if (completed) {
      if (formatDate(task.completedAt!.toLocal()) == todayKey) {
        completedToday.add(task);
      }
      continue;
    }
    if (isTaskOverdue(dueAt: task.dueAt, now: now, completed: false)) {
      overdue.add(task);
    } else if (isTaskDueToday(dueAt: task.dueAt, now: now)) {
      dueToday.add(task);
    }
  }

  // Overdue: most-overdue first. Due today / completed: by due / completion.
  overdue.sort((a, b) => (a.dueAt ?? now).compareTo(b.dueAt ?? now));
  dueToday.sort((a, b) => (a.dueAt ?? now).compareTo(b.dueAt ?? now));
  completedToday.sort(
    (a, b) => (b.completedAt ?? now).compareTo(a.completedAt ?? now),
  );

  final checkedTodayByHabit = <int>{};
  for (final c in checkins) {
    if (c.date == todayKey) checkedTodayByHabit.add(c.habitId);
  }

  final dueHabits = <TodayHabit>[];
  for (final habit in habits) {
    final schedule = scheduleFromFields(
      type: habit.scheduleType,
      weekdays: habit.weekdays,
      targetPerWeek: habit.targetPerWeek,
    );
    if (!schedule.isDueOn(now)) continue;
    dueHabits.add(
      TodayHabit(
        habit: habit,
        checkedToday: checkedTodayByHabit.contains(habit.id),
      ),
    );
  }
  // Unchecked habits first so the actionable ones lead the section.
  dueHabits.sort((a, b) {
    if (a.checkedToday != b.checkedToday) return a.checkedToday ? 1 : -1;
    return a.habit.sortOrder.compareTo(b.habit.sortOrder);
  });

  return TodayViewModel(
    overdueTasks: overdue,
    dueTodayTasks: dueToday,
    completedTodayTasks: completedToday,
    habits: dueHabits,
  );
}
