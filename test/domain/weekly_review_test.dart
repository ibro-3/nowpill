import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/stats_engine.dart';
import 'package:nowpill/domain/weekly_review.dart';

void main() {
  final today = DateTime(2026, 11, 24, 15);

  LeaderboardEntry entry(int id, String name, int current, int best) =>
      LeaderboardEntry(
        habitId: id,
        name: name,
        iconKey: 'spark',
        color: 1,
        currentStreak: current,
        bestStreak: best,
        isWeekly: false,
      );

  test('uses the last complete week and compares to the one before', () {
    final weeks = [
      WeekSummary(
        weekStart: DateTime(2026, 11, 2),
        habitCheckins: 3,
        tasksDone: 1,
      ),
      WeekSummary(
        weekStart: DateTime(2026, 11, 9),
        habitCheckins: 8,
        tasksDone: 2,
      ),
      // Current, incomplete week — never used as "last week".
      WeekSummary(
        weekStart: DateTime(2026, 11, 16),
        habitCheckins: 99,
        tasksDone: 99,
      ),
    ];
    final review = buildWeeklyReview(
      today: today,
      weeks: weeks,
      leaderboard: [entry(1, 'Water', 5, 9)],
      checkedTodayHabitIds: const {1},
      dueDates: const [],
    );
    expect(review.lastWeekTotal, 10);
    expect(review.previousWeekTotal, 4);
    expect(review.tasksDoneLastWeek, 2);
    expect(review.delta, 6);
    expect(review.bestStreak, 9);
    expect(review.atRisk, isEmpty);
  });

  test('flags unchecked streaks and counts tasks due in the next 7 days', () {
    final review = buildWeeklyReview(
      today: today,
      weeks: const [],
      leaderboard: [
        entry(1, 'Water', 5, 9),
        entry(2, 'Read', 0, 2),
        entry(3, 'Move', 3, 4),
      ],
      checkedTodayHabitIds: const {1},
      dueDates: [
        DateTime(2026, 11, 23), // yesterday
        DateTime(2026, 11, 24, 9), // today
        DateTime(2026, 11, 30), // inside horizon
        DateTime(2026, 12, 5), // outside horizon
        null,
      ],
    );
    expect(review.atRisk, ['Move']);
    expect(review.dueAhead, 2);
    expect(review.lastWeekTotal, 0);
  });

  test('fully paused weeks are skipped in the comparison', () {
    final review = buildWeeklyReview(
      today: today,
      weeks: [
        WeekSummary(
          weekStart: DateTime(2026, 11, 2),
          habitCheckins: 3,
          tasksDone: 1,
        ),
        // Fully paused last week: must not become "last week".
        WeekSummary(
          weekStart: DateTime(2026, 11, 9),
          habitCheckins: 0,
          tasksDone: 0,
          pausedDays: 7,
        ),
        WeekSummary(
          weekStart: DateTime(2026, 11, 16),
          habitCheckins: 99,
          tasksDone: 99,
        ),
      ],
      leaderboard: const [],
      checkedTodayHabitIds: const {},
      dueDates: const [],
    );
    expect(review.lastWeekTotal, 4);
    expect(review.previousWeekTotal, 0);
  });

  test('quit habits can be excluded from the at-risk list', () {
    final review = buildWeeklyReview(
      today: today,
      weeks: const [],
      leaderboard: [entry(1, 'Water', 5, 9), entry(2, 'Stop smoking', 30, 30)],
      checkedTodayHabitIds: const {},
      dueDates: const [],
      excludedHabitIds: const {2},
    );
    expect(review.atRisk, ['Water']);
  });
}
