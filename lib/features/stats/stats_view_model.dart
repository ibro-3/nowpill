import '../../data/db/app_database.dart';
import '../../domain/stats_engine.dart';

/// Everything the Stats dashboard renders, derived reactively from tasks,
/// habits, check-ins, and tag links.
class StatsViewModel {
  const StatsViewModel({
    required this.trend,
    required this.weeks,
    required this.leaderboard,
    required this.tagSlices,
    required this.totalCheckins,
    required this.totalTasksDone,
    required this.activeHabits,
    required this.bestStreakOverall,
  });

  static const StatsViewModel empty = StatsViewModel(
    trend: [],
    weeks: [],
    leaderboard: [],
    tagSlices: [],
    totalCheckins: 0,
    totalTasksDone: 0,
    activeHabits: 0,
    bestStreakOverall: 0,
  );

  /// Last 30 days of completions (oldest first).
  final List<DayCount> trend;

  /// Last 8 ISO weeks of completions (oldest first).
  final List<WeekSummary> weeks;

  /// Habits ranked by current streak.
  final List<LeaderboardEntry> leaderboard;

  /// Task counts per tag (donut).
  final List<TagSlice> tagSlices;

  final int totalCheckins;
  final int totalTasksDone;
  final int activeHabits;
  final int bestStreakOverall;

  /// Whether there is any data at all to chart.
  bool get hasData =>
      totalCheckins > 0 || totalTasksDone > 0 || leaderboard.isNotEmpty;

  /// Completions in the current (last) week.
  int get thisWeekTotal => weeks.isEmpty ? 0 : weeks.last.total;

  /// Completions in the previous week (for the delta hint).
  int get lastWeekTotal => weeks.length < 2 ? 0 : weeks[weeks.length - 2].total;
}

/// Convenience: the habit row type used to build leaderboard entries.
typedef HabitStreakRow = ({
  Habit habit,
  int currentStreak,
  int bestStreak,
  bool isWeekly,
});
