import 'date_utils.dart';
import 'enums.dart';
import 'habit_schedule.dart';

export 'habit_schedule.dart' show HabitSchedule;

/// Builds a pure [HabitSchedule] from stored habit fields.
HabitSchedule scheduleFromFields({
  required HabitScheduleType type,
  List<int>? weekdays,
  int? targetPerWeek,
}) {
  switch (type) {
    case HabitScheduleType.daily:
      return const HabitSchedule.daily();
    case HabitScheduleType.weekdays:
      return HabitSchedule.weekdays(weekdays ?? const []);
    case HabitScheduleType.weeklyTarget:
      return HabitSchedule.weeklyTarget(targetPerWeek ?? 1);
  }
}

/// Whether a habit is due on [day] (delegates to its schedule).
bool habitDueOn(HabitSchedule schedule, DateTime day) => schedule.isDueOn(day);

/// Whether an open task with due date [dueAt] is overdue as of [now].
///
/// A task is overdue when its due *calendar day* is strictly before today.
/// Tasks due today are not overdue (they still have the whole day). A task
/// with no due date is never overdue. Completed tasks are never overdue.
bool isTaskOverdue({
  required DateTime? dueAt,
  required DateTime now,
  required bool completed,
}) {
  if (completed || dueAt == null) return false;
  return daysBetween(dueAt, now) > 0;
}

/// Whether an open task is due on the calendar day of [now] (due today).
bool isTaskDueToday({required DateTime? dueAt, required DateTime now}) {
  if (dueAt == null) return false;
  return daysBetween(dueAt, now) == 0;
}

/// Whether an open task belongs in the "Today" view: due today or overdue.
bool isTaskInToday({
  required DateTime? dueAt,
  required DateTime now,
  required bool completed,
}) {
  if (completed || dueAt == null) return false;
  return daysBetween(dueAt, now) >= 0;
}
