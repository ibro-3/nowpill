import 'date_utils.dart';

/// Pure statistics computation for the Stats dashboard. No Flutter imports —
/// this is testable Dart. All inputs are plain data; "today" is injected so
/// tests are deterministic.

/// Completions on a single calendar day.
class DayCount {
  const DayCount({
    required this.day,
    required this.habitCheckins,
    required this.tasksDone,
  });

  /// Date-only local day.
  final DateTime day;
  final int habitCheckins;
  final int tasksDone;

  int get total => habitCheckins + tasksDone;
}

/// Builds the last [days] calendar days ending at [today] (oldest first).
///
/// [checkinsByDay] maps `yyyy-MM-dd` → habit check-in count; [tasksDoneByDay]
/// maps `yyyy-MM-dd` → completed-task count. Missing days count as zero.
List<DayCount> dailyTrend({
  required DateTime today,
  required Map<String, int> checkinsByDay,
  required Map<String, int> tasksDoneByDay,
  int days = 30,
}) {
  final end = DateTime(today.year, today.month, today.day);
  final result = <DayCount>[];
  for (var i = days - 1; i >= 0; i--) {
    final day = DateTime(end.year, end.month, end.day - i);
    final key = formatDate(day);
    result.add(
      DayCount(
        day: day,
        habitCheckins: checkinsByDay[key] ?? 0,
        tasksDone: tasksDoneByDay[key] ?? 0,
      ),
    );
  }
  return result;
}

/// One slice of the tag donut: how many tasks carry a tag.
class TagSlice {
  const TagSlice({
    required this.tagId,
    required this.name,
    required this.color,
    required this.taskCount,
  });

  final int tagId;
  final String name;

  /// ARGB color value.
  final int color;
  final int taskCount;
}

/// Counts tasks per tag from the link rows, sorted by count descending
/// (ties broken by name for stable rendering). Tags with zero tasks are
/// omitted. [tagsById] supplies name/color; links to unknown tags are ignored.
List<TagSlice> tagDistribution({
  required Map<int, ({String name, int color})> tagsById,
  required Iterable<({int taskId, int tagId})> links,
}) {
  final counts = <int, int>{};
  for (final link in links) {
    if (!tagsById.containsKey(link.tagId)) continue;
    counts[link.tagId] = (counts[link.tagId] ?? 0) + 1;
  }
  final slices = <TagSlice>[];
  counts.forEach((tagId, count) {
    final tag = tagsById[tagId]!;
    slices.add(
      TagSlice(
        tagId: tagId,
        name: tag.name,
        color: tag.color,
        taskCount: count,
      ),
    );
  });
  slices.sort((a, b) {
    final c = b.taskCount.compareTo(a.taskCount);
    return c != 0 ? c : a.name.compareTo(b.name);
  });
  return slices;
}

/// Completions within one ISO week (Monday-start).
class WeekSummary {
  const WeekSummary({
    required this.weekStart,
    required this.habitCheckins,
    required this.tasksDone,
    this.pausedDays = 0,
  });

  /// The Monday of the week.
  final DateTime weekStart;
  final int habitCheckins;
  final int tasksDone;

  /// Days inside a planned vacation (schema v7). A fully paused week is
  ///excluded from the weekly review so time off is not scored as inactivity.
  final int pausedDays;

  bool get isFullyPaused => pausedDays >= 7;

  int get total => habitCheckins + tasksDone;
}

/// Builds the last [weeks] ISO weeks ending with the week containing [today]
/// (oldest first).
List<WeekSummary> weeklySummary({
  required DateTime today,
  required Map<String, int> checkinsByDay,
  required Map<String, int> tasksDoneByDay,
  Set<String> pausedDates = const {},
  int weeks = 8,
}) {
  final currentWeek = startOfWeek(today);
  final result = <WeekSummary>[];
  for (var i = weeks - 1; i >= 0; i--) {
    final week = DateTime(
      currentWeek.year,
      currentWeek.month,
      currentWeek.day - i * 7,
    );
    var checkins = 0;
    var tasks = 0;
    var paused = 0;
    for (var d = 0; d < 7; d++) {
      final key = formatDate(DateTime(week.year, week.month, week.day + d));
      checkins += checkinsByDay[key] ?? 0;
      tasks += tasksDoneByDay[key] ?? 0;
      if (pausedDates.contains(key)) paused++;
    }
    result.add(
      WeekSummary(
        weekStart: week,
        habitCheckins: checkins,
        tasksDone: tasks,
        pausedDays: paused,
      ),
    );
  }
  return result;
}

/// A habit's standing on the streak leaderboard.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.habitId,
    required this.name,
    required this.iconKey,
    required this.color,
    required this.currentStreak,
    required this.bestStreak,
    required this.isWeekly,
  });

  final int habitId;
  final String name;
  final String iconKey;

  /// ARGB color value.
  final int color;
  final int currentStreak;
  final int bestStreak;

  /// Weekly-target habits count weeks, not days (shown as "N wk").
  final bool isWeekly;
}

/// Sorts habits for the leaderboard: current streak descending, then best
/// streak descending, then name. The caller supplies already-replayed streaks.
List<LeaderboardEntry> rankLeaderboard(List<LeaderboardEntry> entries) {
  final sorted = List.of(entries);
  sorted.sort((a, b) {
    final c = b.currentStreak.compareTo(a.currentStreak);
    if (c != 0) return c;
    final best = b.bestStreak.compareTo(a.bestStreak);
    if (best != 0) return best;
    return a.name.compareTo(b.name);
  });
  return sorted;
}
