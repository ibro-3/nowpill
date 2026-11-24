import '../../data/db/app_database.dart';
import '../../domain/date_utils.dart';
import '../../domain/enums.dart';
import '../../domain/schedule.dart';

/// A habit shown in the Today dashboard, paired with whether it is already
/// checked in today.
class TodayHabit {
  const TodayHabit({
    required this.habit,
    required this.checkedToday,
    this.amountToday,
  });

  final Habit habit;

  /// Whether today's check-in satisfies the habit (measurable habits: the
  /// logged amount reached the numeric goal; classic habits: any check-in).
  final bool checkedToday;

  /// Today's logged amount for measurable habits (null when none yet).
  final double? amountToday;

  /// The numeric daily goal, when this is a measurable habit.
  double? get targetAmount => habit.targetAmount;

  /// 0…1 progress toward today's numeric goal (measurable habits only).
  double get amountProgress {
    final target = targetAmount;
    if (target == null || target <= 0) return checkedToday ? 1 : 0;
    return ((amountToday ?? 0) / target).clamp(0.0, 1.0);
  }
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
  Set<int> pausedHabitIds = const {},
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

  // Today's check-in rows per habit (a row's presence = checked; amount is
  // null for classic one-tap check-ins).
  final todayCheckins = <int, HabitCheckin>{};
  for (final c in checkins) {
    if (c.date == todayKey) todayCheckins[c.habitId] = c;
  }

  final dueHabits = <TodayHabit>[];
  for (final habit in habits) {
    // Quit habits are tracked through their clean-day streak, not a daily
    // check-in; they get their own section on Today.
    if (habit.kind == HabitKind.quit) continue;
    if (pausedHabitIds.contains(habit.id)) continue;
    final schedule = scheduleFromFields(
      type: habit.scheduleType,
      weekdays: habit.weekdays,
      targetPerWeek: habit.targetPerWeek,
    );
    if (!schedule.isDueOn(now)) continue;
    final row = todayCheckins[habit.id];
    final amount = row?.amount;
    // Measurable habits count as done only at 100% of the goal; a check-in
    // without an amount (one-tap / legacy) counts as full.
    final target = habit.targetAmount;
    final checked =
        row != null && (target == null || amount == null || amount >= target);
    dueHabits.add(
      TodayHabit(habit: habit, checkedToday: checked, amountToday: amount),
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
