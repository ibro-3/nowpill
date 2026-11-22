/// Pure calendar-day helpers. All domain engines operate on local calendar
/// days represented as `yyyy-MM-dd` strings (timezone-proof) or date-only
/// [DateTime]s (time components ignored).
///
/// No Flutter imports — this is testable Dart.
library;

/// Formats a [DateTime] as a local calendar day `yyyy-MM-dd`.
String formatDate(DateTime day) {
  final y = day.year.toString().padLeft(4, '0');
  final m = day.month.toString().padLeft(2, '0');
  final d = day.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Parses a `yyyy-MM-dd` string into a date-only local [DateTime].
///
/// Throws [FormatException] if the string is not a valid calendar day.
DateTime parseDate(String date) {
  final parts = date.split('-');
  if (parts.length != 3) {
    throw FormatException('Expected yyyy-MM-dd', date);
  }
  final year = int.parse(parts[0]);
  final month = int.parse(parts[1]);
  final day = int.parse(parts[2]);
  final result = DateTime(year, month, day);
  // Reject overflow (e.g. 2026-02-30 silently becoming March).
  if (result.year != year || result.month != month || result.day != day) {
    throw FormatException('Invalid calendar day', date);
  }
  return result;
}

/// Returns the calendar day after [day].
DateTime nextDay(DateTime day) => DateTime(day.year, day.month, day.day + 1);

/// Returns the calendar day before [day].
DateTime previousDay(DateTime day) =>
    DateTime(day.year, day.month, day.day - 1);

/// Whole days from [a] to [b] (positive when [b] is later). Time ignored.
int daysBetween(DateTime a, DateTime b) {
  final da = DateTime(a.year, a.month, a.day);
  final db = DateTime(b.year, b.month, b.day);
  return db.difference(da).inDays;
}

/// The Monday of the week containing [day] (ISO weeks start Monday).
DateTime startOfWeek(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

/// Number of days in the given [year]/[month].
int daysInMonth(int year, int month) {
  // Day 0 of the next month is the last day of this month.
  return DateTime(year, month + 1, 0).day;
}
