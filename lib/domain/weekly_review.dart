import 'stats_engine.dart';

/// A compact "how was last week?" summary for the Stats dashboard.
///
/// Pure and deterministic: `today` is injected and every input is data already
/// computed by the stats engine / streak replay, so this is trivially testable.
class WeeklyReview {
  const WeeklyReview({
    required this.lastWeekTotal,
    required this.previousWeekTotal,
    required this.tasksDoneLastWeek,
    required this.bestStreak,
    required this.atRisk,
    required this.dueAhead,
  });

  /// Habit check-ins + completed tasks in the last *complete* ISO week.
  final int lastWeekTotal;

  /// Same, for the week before (for the comparison line).
  final int previousWeekTotal;

  /// Tasks completed in the last complete week.
  final int tasksDoneLastWeek;

  /// Best streak across active habits.
  final int bestStreak;

  /// Names of habits with an active streak that have not been checked today.
  final List<String> atRisk;

  /// Open tasks due in the next seven days.
  final int dueAhead;

  int get delta => lastWeekTotal - previousWeekTotal;
}

/// Builds a [WeeklyReview] from the existing stats aggregates.
///
/// [weeks] is oldest-first with the current (incomplete) week last, as
/// produced by `weeklySummary`. [dueDates] contains due dates of open tasks;
/// nulls are ignored.
WeeklyReview buildWeeklyReview({
  required DateTime today,
  required List<WeekSummary> weeks,
  required List<LeaderboardEntry> leaderboard,
  required Set<int> checkedTodayHabitIds,
  required Iterable<DateTime?> dueDates,
}) {
  final completeWeeks = weeks.length >= 2
      ? weeks.sublist(0, weeks.length - 1)
      : const <WeekSummary>[];
  final lastWeek = completeWeeks.isEmpty ? null : completeWeeks.last;
  final previousWeek = completeWeeks.length < 2
      ? null
      : completeWeeks[completeWeeks.length - 2];

  final day = DateTime(today.year, today.month, today.day);
  final horizon = day.add(const Duration(days: 7));
  var dueAhead = 0;
  for (final due in dueDates) {
    if (due == null) continue;
    final local = due.toLocal();
    final dueDay = DateTime(local.year, local.month, local.day);
    if (!dueDay.isBefore(day) && dueDay.isBefore(horizon)) dueAhead++;
  }

  final atRisk = <String>[];
  for (final entry in leaderboard) {
    if (entry.currentStreak > 0 &&
        !checkedTodayHabitIds.contains(entry.habitId)) {
      atRisk.add(entry.name);
    }
  }

  return WeeklyReview(
    lastWeekTotal: lastWeek?.total ?? 0,
    previousWeekTotal: previousWeek?.total ?? 0,
    tasksDoneLastWeek: lastWeek?.tasksDone ?? 0,
    bestStreak: leaderboard.fold(
      0,
      (max, e) => e.bestStreak > max ? e.bestStreak : max,
    ),
    atRisk: atRisk,
    dueAhead: dueAhead,
  );
}
