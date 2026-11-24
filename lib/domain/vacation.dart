import 'date_utils.dart';

/// A planned time off inside which habits are paused (schema v6).
///
/// Dates are `yyyy-MM-dd` local-day strings, identical to check-ins, so they
/// are timezone-proof and sort lexicographically. [end] is inclusive.
class VacationPeriod {
  const VacationPeriod({
    required this.start,
    required this.end,
    this.uuid = '',
    this.updatedAt = 0,
  });

  final String start;
  final String end;
  final String uuid;
  final int updatedAt;

  bool get isValid => start.compareTo(end) <= 0;
}

/// Expands [periods] into a set of paused day keys.
///
/// [from]/[to] are optional inclusive `yyyy-MM-dd` bounds. Passing the habit's
/// lifetime keeps the set small even if a period spans years. A period whose
/// end precedes its start is ignored rather than looping forever.
Set<String> expandPausedDates(
  Iterable<VacationPeriod> periods, {
  String? from,
  String? to,
}) {
  final result = <String>{};
  for (final period in periods) {
    if (!period.isValid) continue;
    var day = parseDate(period.start);
    final last = parseDate(period.end);
    while (!day.isAfter(last)) {
      final key = formatDate(day);
      if ((from == null || key.compareTo(from) >= 0) &&
          (to == null || key.compareTo(to) <= 0)) {
        result.add(key);
      }
      day = nextDay(day);
    }
  }
  return result;
}

/// Whether every active day of the ISO week containing [weekStart] is paused.
///
/// A weekly-target habit misses only a *fully* elapsed week — a Mon–Wed
/// vacation must not excuse Thu–Sun. Active days are clamped to the habit's
/// lifetime ([habitStart]) and elapsed time ([today]) so a habit created
/// mid-week, or the current week, never demands future pause coverage.
bool isWeekFullyPaused({
  required DateTime weekStart,
  required DateTime habitStart,
  required DateTime today,
  required Set<String> pausedDates,
}) {
  final first = weekStart.isAfter(habitStart) ? weekStart : habitStart;
  final weekEnd = weekStart.add(const Duration(days: 6));
  final last = weekEnd.isBefore(today) ? weekEnd : today;
  var day = DateTime(first.year, first.month, first.day);
  final end = DateTime(last.year, last.month, last.day);
  if (day.isAfter(end)) return false;
  while (!day.isAfter(end)) {
    if (!pausedDates.contains(formatDate(day))) return false;
    day = nextDay(day);
  }
  return true;
}

/// Whether [day] falls in any planned vacation.
bool isDayPaused(DateTime day, Iterable<VacationPeriod> periods) {
  final key = formatDate(day);
  for (final period in periods) {
    if (period.isValid &&
        key.compareTo(period.start) >= 0 &&
        key.compareTo(period.end) <= 0) {
      return true;
    }
  }
  return false;
}
