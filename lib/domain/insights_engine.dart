/// Pure completion-rate insights for habits and routines. No Flutter imports
/// and no database types — callers feed plain day-set snapshots, and `today`
/// is injected so tests are deterministic.
///
/// Vacation-paused days and explicitly frozen days are neutral: they are
/// excluded from the denominator rather than counted as misses. Beta/partial
/// check-ins for measurable habits do not count as completions.
library;

import 'date_utils.dart';
import 'enums.dart';
import 'habit_schedule.dart';

/// The trailing window an insight covers.
enum InsightRange {
  last30Days,
  last90Days;

  int get days => switch (this) {
    InsightRange.last30Days => 30,
    InsightRange.last90Days => 90,
  };
}

/// One habit's completion standing over an [InsightRange].
class HabitInsight {
  const HabitInsight({
    required this.completed,
    required this.tracked,
    required this.bestWeekday,
    required this.bestWeekdayRate,
    required this.relapses,
    required this.scheduleType,
    required this.kind,
  });

  static const HabitInsight empty = HabitInsight(
    completed: 0,
    tracked: 0,
    bestWeekday: null,
    bestWeekdayRate: null,
    relapses: 0,
    scheduleType: HabitScheduleType.daily,
    kind: HabitKind.build,
  );

  /// Full completions (or clean days for quit habits).
  final int completed;

  /// Days/weeks that could have been completed after excluding neutral days.
  final int tracked;

  /// ISO weekday (1 = Mon … 7 = Sun) with the best completion rate. For
  /// weekly-target habits this is the weekday with the most check-ins; quit
  /// habits leave it null.
  final int? bestWeekday;

  /// Completion rate on [bestWeekday]. Null for weekly-target and quit habits.
  final double? bestWeekdayRate;

  /// Relapse events inside the window (quit habits only).
  final int relapses;

  final HabitScheduleType scheduleType;
  final HabitKind kind;

  double? get rate => tracked == 0 ? null : completed / tracked;

  /// Rounded percentage for display; 0 when there is no history yet.
  int get percent => rate == null ? 0 : (rate! * 100).round();

  bool get hasHistory => tracked > 0;
  bool get isWeekly => scheduleType == HabitScheduleType.weeklyTarget;
  bool get isQuit => kind == HabitKind.quit;
}

/// Computes one habit's insight from day-key snapshots.
///
/// [checkins] contains `yyyy-MM-dd` keys (presence = checked in), [amounts]
/// carries logged values for measurable habits, [pausedDates] are vacation
/// days, [frozenDates] are explicitly placed freezes, and [relapseDates] are
/// quit-habit relapse events.
HabitInsight buildHabitInsight({
  required HabitSchedule schedule,
  required HabitKind kind,
  required DateTime startDate,
  required DateTime today,
  required Set<String> checkins,
  required Set<String> pausedDates,
  required Set<String> frozenDates,
  required Set<String> relapseDates,
  required double? targetAmount,
  required Map<String, double> amounts,
  InsightRange range = InsightRange.last30Days,
}) {
  final end = DateTime(today.year, today.month, today.day);
  final start = DateTime(startDate.year, startDate.month, startDate.day);
  final windowStart = DateTime(end.year, end.month, end.day - (range.days - 1));
  final first = start.isAfter(windowStart) ? start : windowStart;
  if (first.isAfter(end)) return HabitInsight.empty;

  bool isComplete(String key) {
    if (!checkins.contains(key)) return false;
    if (targetAmount == null || targetAmount <= 0) return true;
    final amount = amounts[key];
    return amount == null || amount >= targetAmount;
  }

  bool isNeutral(String key) =>
      pausedDates.contains(key) || frozenDates.contains(key);

  if (schedule.type == HabitScheduleType.weeklyTarget) {
    return _weeklyInsight(
      schedule: schedule,
      first: first,
      end: end,
      isComplete: isComplete,
      isNeutral: isNeutral,
    );
  }

  if (kind == HabitKind.quit) {
    return _quitInsight(
      first: first,
      end: end,
      pausedDates: pausedDates,
      relapseDates: relapseDates,
      scheduleType: schedule.type,
    );
  }

  return _dayInsight(
    schedule: schedule,
    kind: kind,
    first: first,
    end: end,
    isComplete: isComplete,
    isNeutral: isNeutral,
  );
}

HabitInsight _dayInsight({
  required HabitSchedule schedule,
  required HabitKind kind,
  required DateTime first,
  required DateTime end,
  required bool Function(String key) isComplete,
  required bool Function(String key) isNeutral,
}) {
  final trackedByWeekday = List<int>.filled(8, 0);
  final completedByWeekday = List<int>.filled(8, 0);
  var tracked = 0;
  var completed = 0;

  for (var day = first; !day.isAfter(end); day = nextDay(day)) {
    if (!schedule.isDueOn(day)) continue;
    final key = formatDate(day);
    if (isNeutral(key)) continue;
    tracked++;
    trackedByWeekday[day.weekday]++;
    if (isComplete(key)) {
      completed++;
      completedByWeekday[day.weekday]++;
    }
  }

  int? bestWeekday;
  var bestRate = -1.0;
  var bestTracked = 0;
  for (var weekday = 1; weekday <= 7; weekday++) {
    final den = trackedByWeekday[weekday];
    if (den == 0 || completedByWeekday[weekday] == 0) continue;
    final rate = completedByWeekday[weekday] / den;
    if (rate > bestRate || (rate == bestRate && den > bestTracked)) {
      bestWeekday = weekday;
      bestRate = rate;
      bestTracked = den;
    }
  }

  return HabitInsight(
    completed: completed,
    tracked: tracked,
    bestWeekday: bestWeekday,
    bestWeekdayRate: bestWeekday == null ? null : bestRate,
    relapses: 0,
    scheduleType: schedule.type,
    kind: kind,
  );
}

HabitInsight _weeklyInsight({
  required HabitSchedule schedule,
  required DateTime first,
  required DateTime end,
  required bool Function(String key) isComplete,
  required bool Function(String key) isNeutral,
}) {
  final target = schedule.targetPerWeek ?? 1;
  var tracked = 0;
  var completed = 0;
  final checkinsByWeekday = <int, int>{};

  var week = startOfWeek(first);
  final lastWeek = startOfWeek(end);
  while (!week.isAfter(lastWeek)) {
    var available = 0;
    var met = 0;
    for (var d = 0; d < 7; d++) {
      final day = DateTime(week.year, week.month, week.day + d);
      if (day.isBefore(first) || day.isAfter(end)) continue;
      final key = formatDate(day);
      if (isNeutral(key)) continue;
      available++;
      if (isComplete(key)) {
        met++;
        checkinsByWeekday[day.weekday] =
            (checkinsByWeekday[day.weekday] ?? 0) + 1;
      }
    }
    if (available > 0) {
      tracked++;
      // A shortened week by vacation/freeze needs a proportionally smaller
      // goal so time off does not punish the habit.
      if (met >= (target < available ? target : available)) completed++;
    }
    week = DateTime(week.year, week.month, week.day + 7);
  }

  return HabitInsight(
    completed: completed,
    tracked: tracked,
    bestWeekday: _mostActiveWeekday(checkinsByWeekday),
    bestWeekdayRate: null,
    relapses: 0,
    scheduleType: schedule.type,
    kind: HabitKind.build,
  );
}

int? _mostActiveWeekday(Map<int, int> counts) {
  int? best;
  var bestCount = 0;
  counts.forEach((weekday, count) {
    if (best == null ||
        count > bestCount ||
        (count == bestCount && weekday < best!)) {
      best = weekday;
      bestCount = count;
    }
  });
  return best;
}

HabitInsight _quitInsight({
  required DateTime first,
  required DateTime end,
  required Set<String> pausedDates,
  required Set<String> relapseDates,
  required HabitScheduleType scheduleType,
}) {
  var tracked = 0;
  var clean = 0;
  var relapses = 0;
  for (var day = first; !day.isAfter(end); day = nextDay(day)) {
    final key = formatDate(day);
    if (pausedDates.contains(key)) continue;
    tracked++;
    if (relapseDates.contains(key)) {
      relapses++;
    } else {
      clean++;
    }
  }
  return HabitInsight(
    completed: clean,
    tracked: tracked,
    bestWeekday: null,
    bestWeekdayRate: null,
    relapses: relapses,
    scheduleType: scheduleType,
    kind: HabitKind.quit,
  );
}

/// One routine's aggregate completion standing. Null [key] means Unrouted.
class RoutineInsight {
  const RoutineInsight({
    required this.key,
    required this.name,
    required this.habitCount,
    required this.completed,
    required this.tracked,
  });

  final int? key;
  final String name;
  final int habitCount;
  final int completed;
  final int tracked;

  double? get rate => tracked == 0 ? null : completed / tracked;
  int get percent => rate == null ? 0 : (rate! * 100).round();
}

class _Accumulator {
  _Accumulator(this.name);

  final String name;
  int habitCount = 0;
  int completed = 0;
  int tracked = 0;
}

/// Groups per-habit insights into weighted routine averages, sorted by rate
/// descending (groups without history last, then by name). [labels] must
/// include a null key when unrouted habits are present.
List<RoutineInsight> buildRoutineInsights({
  required Map<int?, String> labels,
  required Iterable<({int? routineId, HabitInsight insight})> habits,
}) {
  final groups = <int?, _Accumulator>{};
  for (final habit in habits) {
    final acc = groups.putIfAbsent(
      habit.routineId,
      () => _Accumulator(labels[habit.routineId] ?? ''),
    );
    acc.habitCount++;
    acc.completed += habit.insight.completed;
    acc.tracked += habit.insight.tracked;
  }

  final result = [
    for (final entry in groups.entries)
      RoutineInsight(
        key: entry.key,
        name: entry.value.name,
        habitCount: entry.value.habitCount,
        completed: entry.value.completed,
        tracked: entry.value.tracked,
      ),
  ];
  result.sort((a, b) {
    final ar = a.rate;
    final br = b.rate;
    if (ar == null && br == null) return a.name.compareTo(b.name);
    if (ar == null) return 1;
    if (br == null) return -1;
    final c = br.compareTo(ar);
    return c != 0 ? c : a.name.compareTo(b.name);
  });
  return result;
}
