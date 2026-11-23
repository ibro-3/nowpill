import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/domain/stats_engine.dart';

void main() {
  // 2026-11-23 is a Monday.
  final today = DateTime(2026, 11, 23);

  group('dailyTrend', () {
    test('returns 30 days ending today, oldest first', () {
      final trend = dailyTrend(
        today: today,
        checkinsByDay: const {},
        tasksDoneByDay: const {},
      );
      expect(trend.length, 30);
      expect(trend.first.day, DateTime(2026, 10, 25));
      expect(trend.last.day, today);
      expect(trend.every((d) => d.total == 0), isTrue);
    });

    test('counts check-ins and tasks per day, zero-fills gaps', () {
      final trend = dailyTrend(
        today: today,
        checkinsByDay: {'2026-11-23': 3, '2026-11-21': 1},
        tasksDoneByDay: {'2026-11-23': 2, '2026-11-22': 1},
        days: 3,
      );
      expect(trend.map((d) => d.habitCheckins).toList(), [1, 0, 3]);
      expect(trend.map((d) => d.tasksDone).toList(), [0, 1, 2]);
      expect(trend.map((d) => d.total).toList(), [1, 1, 5]);
    });

    test('crosses month boundaries correctly', () {
      final trend = dailyTrend(
        today: DateTime(2026, 3, 2),
        checkinsByDay: const {'2026-02-28': 1},
        tasksDoneByDay: const {},
        days: 3,
      );
      expect(trend.map((d) => formatDate(d.day)).toList(), [
        '2026-02-28',
        '2026-03-01',
        '2026-03-02',
      ]);
      expect(trend.first.habitCheckins, 1);
      expect(trend.last.day, DateTime(2026, 3, 2));
    });
  });

  group('tagDistribution', () {
    test('counts links per tag, sorted by count desc then name', () {
      final slices = tagDistribution(
        tagsById: {
          1: (name: 'work', color: 0xFF0000FF),
          2: (name: 'home', color: 0xFF00FF00),
          3: (name: 'health', color: 0xFFFF0000),
        },
        links: [
          (taskId: 10, tagId: 1),
          (taskId: 11, tagId: 1),
          (taskId: 12, tagId: 2),
          (taskId: 13, tagId: 2),
          (taskId: 14, tagId: 3),
        ],
      );
      expect(slices.map((s) => s.name).toList(), ['home', 'work', 'health']);
      expect(slices.map((s) => s.taskCount).toList(), [2, 2, 1]);
    });

    test('omits tags with no tasks and ignores unknown tag ids', () {
      final slices = tagDistribution(
        tagsById: {
          1: (name: 'work', color: 0xFF0000FF),
          2: (name: 'unused', color: 0xFF00FF00),
        },
        links: [(taskId: 10, tagId: 1), (taskId: 11, tagId: 99)],
      );
      expect(slices.length, 1);
      expect(slices.single.name, 'work');
      expect(slices.single.taskCount, 1);
    });

    test('empty links produce no slices', () {
      final slices = tagDistribution(
        tagsById: {1: (name: 'work', color: 0xFF0000FF)},
        links: const [],
      );
      expect(slices, isEmpty);
    });
  });

  group('weeklySummary', () {
    test('returns 8 Monday-start weeks ending with the current week', () {
      final weeks = weeklySummary(
        today: today,
        checkinsByDay: const {},
        tasksDoneByDay: const {},
      );
      expect(weeks.length, 8);
      expect(weeks.last.weekStart, today); // Monday
      expect(weeks.first.weekStart, DateTime(2026, 10, 5));
      expect(
        weeks.every((w) => w.weekStart.weekday == DateTime.monday),
        isTrue,
      );
    });

    test('aggregates a full week of check-ins and tasks', () {
      final weeks = weeklySummary(
        today: today,
        checkinsByDay: {
          '2026-11-23': 2, // Mon (current week)
          '2026-11-22': 5, // Sun (previous week)
          '2026-11-16': 1, // Mon (previous week)
        },
        tasksDoneByDay: {'2026-11-23': 1, '2026-11-20': 2},
        weeks: 2,
      );
      expect(weeks.first.weekStart, DateTime(2026, 11, 16));
      expect(weeks.first.habitCheckins, 6);
      expect(weeks.first.tasksDone, 2);
      expect(weeks.first.total, 8);
      expect(weeks.last.habitCheckins, 2);
      expect(weeks.last.tasksDone, 1);
    });

    test('mid-week today still sums the whole current week so far', () {
      final weeks = weeklySummary(
        today: DateTime(2026, 11, 25), // Wednesday
        checkinsByDay: {'2026-11-23': 1, '2026-11-25': 1},
        tasksDoneByDay: const {},
        weeks: 1,
      );
      expect(weeks.single.weekStart, DateTime(2026, 11, 23));
      expect(weeks.single.habitCheckins, 2);
    });
  });

  group('rankLeaderboard', () {
    LeaderboardEntry entry(
      String name,
      int current,
      int best, {
      bool weekly = false,
    }) {
      return LeaderboardEntry(
        habitId: name.hashCode,
        name: name,
        iconKey: 'spark',
        color: 0xFF2DD4A8,
        currentStreak: current,
        bestStreak: best,
        isWeekly: weekly,
      );
    }

    test('sorts by current streak desc, then best, then name', () {
      final ranked = rankLeaderboard([
        entry('Gym', 5, 10),
        entry('Read', 12, 20),
        entry('Meditate', 12, 25),
        entry('Journal', 0, 3),
      ]);
      expect(ranked.map((e) => e.name).toList(), [
        'Meditate',
        'Read',
        'Gym',
        'Journal',
      ]);
    });

    test('does not mutate the input list', () {
      final input = [entry('B', 1, 1), entry('A', 2, 2)];
      rankLeaderboard(input);
      expect(input.first.name, 'B');
    });
  });
}
