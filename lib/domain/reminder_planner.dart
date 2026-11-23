import 'date_utils.dart';
import 'habit_schedule.dart';

/// A single planned reminder occurrence, produced purely from a habit/task's
/// schedule and reminder time. The notification layer turns these into
/// platform schedules; keeping the computation pure makes it testable without
/// any plugin or clock.
class ReminderOccurrence {
  const ReminderOccurrence({required this.when, required this.label});

  /// The local date-time the reminder should fire.
  final DateTime when;

  /// Human-readable subject (habit name or task title) for the notification.
  final String label;
}

/// Plans the next [count] reminder occurrences for a habit, starting from
/// [now], honoring its schedule and skipping days already checked in.
///
/// [reminderTime] supplies the time-of-day (only hour/minute are used).
/// [checkedDays] is the set of `yyyy-MM-dd` days already completed — a
/// reminder is never planned for a day the habit is already done.
///
/// * daily / weeklyTarget — every day is eligible.
/// * weekdays — only the listed ISO weekdays.
///
/// Returns at most [count] occurrences, soonest first. If [reminderTime] is
/// null the result is empty (no reminder configured).
List<ReminderOccurrence> planHabitReminders({
  required String habitName,
  required HabitSchedule schedule,
  required DateTime? reminderTime,
  required DateTime now,
  required Set<String> checkedDays,
  int count = 7,
}) {
  if (reminderTime == null || count <= 0) return const [];
  final local = reminderTime.toLocal();
  final result = <ReminderOccurrence>[];
  var day = DateTime(now.year, now.month, now.day);

  // Scan forward enough days to find `count` eligible occurrences. Weekday
  // schedules may skip many days, so bound the scan generously.
  for (var i = 0; i < 366 && result.length < count; i++) {
    final key = formatDate(day);
    final eligible = schedule.isDueOn(day) && !checkedDays.contains(key);
    if (eligible) {
      final when = DateTime(
        day.year,
        day.month,
        day.day,
        local.hour,
        local.minute,
      );
      // Only future occurrences (a reminder earlier today has already passed).
      if (when.isAfter(now)) {
        result.add(ReminderOccurrence(when: when, label: habitName));
      }
    }
    day = nextDay(day);
  }
  return result;
}

/// Plans a single reminder for a one-off or recurring task at [reminderAt].
/// Returns an empty list when the reminder is null, already past, or the task
/// is completed.
List<ReminderOccurrence> planTaskReminder({
  required String taskTitle,
  required DateTime? reminderAt,
  required DateTime now,
  required bool completed,
}) {
  if (reminderAt == null || completed) return const [];
  final local = reminderAt.toLocal();
  if (!local.isAfter(now)) return const [];
  return [ReminderOccurrence(when: local, label: taskTitle)];
}

/// Stable notification id for a habit's reminder slot. Slots are numbered so
/// the next N occurrences can be cancelled/replaced independently.
int habitReminderId(int habitId, int slot) => 100000 + habitId * 100 + slot;

/// Stable notification id for a task's reminder.
int taskReminderId(int taskId) => 900000 + taskId;
