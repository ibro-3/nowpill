import 'date_utils.dart';
import 'enums.dart';
import 'recurrence_rule.dart';

/// Computes the next occurrence of a recurring task, anchored to the original
/// due date [anchor] so the cadence is preserved regardless of when the task
/// was actually completed.
///
/// * [RecurrenceUnit.day] — add `interval` days.
/// * [RecurrenceUnit.week] — add `interval * 7` days (same weekday).
/// * [RecurrenceUnit.month] — add `interval` months, clamping the day to the
///   target month's length (Jan 31 → Feb 28/29). The anchor's day-of-month is
///   the intended day; clamping only applies when the target month is shorter.
///
/// The time-of-day of [anchor] is preserved. Throws [ArgumentError] for a
/// non-positive interval.
DateTime nextOccurrence(DateTime anchor, RecurrenceRule rule) {
  if (rule.interval <= 0) {
    throw ArgumentError.value(rule.interval, 'interval', 'must be positive');
  }
  switch (rule.unit) {
    case RecurrenceUnit.day:
      return _addDays(anchor, rule.interval);
    case RecurrenceUnit.week:
      return _addDays(anchor, rule.interval * 7);
    case RecurrenceUnit.month:
      return _addMonths(anchor, rule.interval);
  }
}

DateTime _addDays(DateTime anchor, int days) {
  return _construct(anchor, anchor.year, anchor.month, anchor.day + days);
}

DateTime _addMonths(DateTime anchor, int months) {
  final totalMonths = anchor.year * 12 + (anchor.month - 1) + months;
  final year = totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;
  final day = anchor.day.clamp(1, daysInMonth(year, month));
  return _construct(anchor, year, month, day);
}

/// Builds a date preserving the anchor's time-of-day and UTC/local flag, so a
/// UTC anchor (as stored in the database) yields a UTC result without a
/// timezone shift.
DateTime _construct(DateTime anchor, int year, int month, int day) {
  if (anchor.isUtc) {
    return DateTime.utc(
      year,
      month,
      day,
      anchor.hour,
      anchor.minute,
      anchor.second,
      anchor.millisecond,
      anchor.microsecond,
    );
  }
  return DateTime(
    year,
    month,
    day,
    anchor.hour,
    anchor.minute,
    anchor.second,
    anchor.millisecond,
    anchor.microsecond,
  );
}
