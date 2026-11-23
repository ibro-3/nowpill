import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../domain/date_utils.dart';
import '../../domain/schedule.dart';
import '../habits/habit_providers.dart';
import '../tasks/task_providers.dart';
import 'today_view_model.dart';

/// The Today dashboard's derived view model: overdue tasks, habits due today,
/// tasks due today, and items completed today — all reactive.
final todayViewModelProvider = Provider<TodayViewModel>((ref) {
  final tasks = ref.watch(allTasksProvider).value ?? const <Task>[];
  final habits = ref.watch(activeHabitsProvider).value ?? const <Habit>[];
  final checkins =
      ref.watch(allCheckinsProvider).value ?? const <HabitCheckin>[];

  final now = DateTime.now();
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
});
