import 'date_utils.dart';
import 'enums.dart';

/// A planned time off inside which habits are paused (schema v6, scoped in v7).
///
/// Dates are `yyyy-MM-dd` local-day strings, identical to check-ins, so they
/// are timezone-proof and sort lexicographically. [end] is inclusive.
/// [allHabits] is true for v6 rows and for "pause everything"; when false only
/// the targets listed in [VacationScope] apply.
class VacationPeriod {
  const VacationPeriod({
    required this.start,
    required this.end,
    this.uuid = '',
    this.updatedAt = 0,
    this.allHabits = true,
  });

  final String start;
  final String end;
  final String uuid;
  final int updatedAt;
  final bool allHabits;

  bool get isValid => start.compareTo(end) <= 0;
}

/// A routine or habit targeted by a scoped vacation period (schema v7).
/// All identities are stable uuids so merges never need local-id remapping.
class VacationScope {
  const VacationScope({
    required this.periodUuid,
    required this.targetKind,
    required this.targetUuid,
    this.uuid = '',
    this.updatedAt = 0,
  });

  final String periodUuid;
  final VacationTargetKind targetKind;
  final String targetUuid;
  final String uuid;
  final int updatedAt;
}

/// Resolves the paused day keys for **one** habit over an inclusive window.
///
/// A period applies when it is all-habits or when one of its scopes matches
/// the habit directly or via its current routine. Scopes with unknown uuids
/// simply never match, so deleting a routine or habit can never widen a
/// vacation. An all-habits=false period with no matching scopes pauses
/// nothing.
Set<String> resolvePausedDates({
  required Iterable<VacationPeriod> periods,
  required Iterable<VacationScope> scopes,
  required String habitUuid,
  String? routineUuid,
  required DateTime windowStart,
  required DateTime windowEnd,
}) {
  final from = formatDate(windowStart);
  final to = formatDate(windowEnd);
  final applicable = <VacationPeriod>[];

  for (final period in periods) {
    if (!period.isValid) continue;
    if (period.allHabits) {
      applicable.add(period);
      continue;
    }
    for (final scope in scopes) {
      if (scope.periodUuid != period.uuid) continue;
      final matches = scope.targetKind == VacationTargetKind.habit
          ? scope.targetUuid == habitUuid
          : routineUuid != null && scope.targetUuid == routineUuid;
      if (matches) {
        applicable.add(period);
        break;
      }
    }
  }

  return expandPausedDates(applicable, from: from, to: to);
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
