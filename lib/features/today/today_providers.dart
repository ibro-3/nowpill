import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../domain/vacation.dart' as vacation_domain;
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
  final periods =
      ref.watch(vacationPeriodsProvider).value ?? const <VacationPeriod>[];

  return computeTodayViewModel(
    tasks: tasks,
    habits: habits,
    checkins: checkins,
    now: DateTime.now(),
    pausedDates: vacation_domain.expandPausedDates(
      periods.map(
        (p) =>
            vacation_domain.VacationPeriod(start: p.startDate, end: p.endDate),
      ),
    ),
  );
});
