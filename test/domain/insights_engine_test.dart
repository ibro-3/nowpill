import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/domain/habit_schedule.dart';
import 'package:nowpill/domain/insights_engine.dart';

void main() {
  // Wednesday, so partial weeks and weekday grouping are predictable.
  final today = DateTime(2026, 11, 25);

  String day(int offset) => formatDate(DateTime(2026, 11, 25 - offset));

  Set<String> lastDays(int count) => {for (var i = 0; i < count; i++) day(i)};

  HabitInsight daily({
    required int ageDays,
    required Set<String> checkins,
    InsightRange range = InsightRange.last30Days,
    Set<String> paused = const {},
    Set<String> frozen = const {},
    double? targetAmount,
    Map<String, double> amounts = const {},
    HabitSchedule? schedule,
    HabitKind kind = HabitKind.build,
  }) {
    return buildHabitInsight(
      schedule: schedule ?? const HabitSchedule.daily(),
      kind: kind,
      startDate: DateTime(2026, 11, 25 - (ageDays - 1)),
      today: today,
      checkins: checkins,
      pausedDates: paused,
      frozenDates: frozen,
      relapseDates: const {},
      targetAmount: targetAmount,
      amounts: amounts,
      range: range,
    );
  }

  group('day-based insights', () {
    test('counts scheduled days and completions in the window', () {
      final insight = daily(ageDays: 10, checkins: lastDays(4));
      expect(insight.tracked, 10);
      expect(insight.completed, 4);
      expect(insight.rate, 0.4);
      expect(insight.percent, 40);
      expect(insight.hasHistory, isTrue);
    });

    test('clamps the window to the habit start date', () {
      final insight = daily(ageDays: 5, checkins: lastDays(5));
      expect(insight.tracked, 5);
      expect(insight.completed, 5);
      expect(insight.rate, 1.0);
    });

    test('the 90-day window includes older history', () {
      final insight = daily(
        ageDays: 60,
        checkins: lastDays(10),
        range: InsightRange.last90Days,
      );
      expect(InsightRange.last90Days.days, 90);
      expect(insight.tracked, 60);
      expect(insight.completed, 10);
    });

    test('future start date yields an empty insight', () {
      final insight = buildHabitInsight(
        schedule: const HabitSchedule.daily(),
        kind: HabitKind.build,
        startDate: DateTime(2026, 11, 26),
        today: today,
        checkins: const {},
        pausedDates: const {},
        frozenDates: const {},
        relapseDates: const {},
        targetAmount: null,
        amounts: const {},
      );
      expect(insight.rate, isNull);
      expect(insight.percent, 0);
    });

    test('weekday schedules only count due days', () {
      // 2026-11-01 is a Sunday; Mon/Wed/Fri from then to 11-25 = 11 days.
      final insight = daily(
        ageDays: 25,
        checkins: {
          formatDate(DateTime(2026, 11, 2)),
          formatDate(DateTime(2026, 11, 4)),
          formatDate(DateTime(2026, 11, 9)),
          formatDate(DateTime(2026, 11, 25)),
        },
        schedule: const HabitSchedule.weekdays([
          DateTime.monday,
          DateTime.wednesday,
          DateTime.friday,
        ]),
      );
      expect(insight.tracked, 11);
      expect(insight.completed, 4);
    });

    test('paused and frozen days are neutral, not misses', () {
      final insight = daily(
        ageDays: 10,
        checkins: lastDays(8)
          ..remove(day(2))
          ..remove(day(5)),
        paused: {day(2)},
        frozen: {day(5)},
      );
      expect(insight.tracked, 8);
      expect(insight.completed, 6);
      expect(insight.rate, 0.75);
    });

    test('partial measurable amounts do not count as completions', () {
      final insight = daily(
        ageDays: 3,
        checkins: lastDays(3),
        targetAmount: 2,
        amounts: {day(2): 1.5, day(1): 2, day(0): 3},
      );
      expect(insight.tracked, 3);
      expect(insight.completed, 2);
    });

    test('best weekday uses completion rate, ties go to more occurrences', () {
      final insight = daily(
        ageDays: 17,
        checkins: {
          formatDate(DateTime(2026, 11, 9)),
          formatDate(DateTime(2026, 11, 11)),
          formatDate(DateTime(2026, 11, 16)),
          formatDate(DateTime(2026, 11, 18)),
          formatDate(DateTime(2026, 11, 23)),
          formatDate(DateTime(2026, 11, 25)),
        },
      );
      expect(insight.bestWeekday, DateTime.monday);
      expect(insight.bestWeekdayRate, 1.0);
    });

    test('best weekday is null when there is no history', () {
      final insight = daily(ageDays: 10, checkins: const {});
      expect(insight.bestWeekday, isNull);
      expect(insight.bestWeekdayRate, isNull);
    });
  });

  group('weekly-target insights', () {
    test('counts weeks that meet the goal', () {
      final insight = daily(
        ageDays: 25,
        checkins: {
          formatDate(DateTime(2026, 11, 2)),
          formatDate(DateTime(2026, 11, 4)),
          formatDate(DateTime(2026, 11, 6)),
          formatDate(DateTime(2026, 11, 9)),
          formatDate(DateTime(2026, 11, 11)),
        },
        schedule: const HabitSchedule.weeklyTarget(3),
      );
      expect(insight.isWeekly, isTrue);
      expect(insight.tracked, 5);
      expect(insight.completed, 1);
    });

    test('shortened weeks get a pro-rated goal', () {
      final insight = buildHabitInsight(
        schedule: const HabitSchedule.weeklyTarget(3),
        kind: HabitKind.build,
        startDate: DateTime(2026, 11, 19),
        today: today,
        checkins: {
          formatDate(DateTime(2026, 11, 23)),
          formatDate(DateTime(2026, 11, 24)),
          formatDate(DateTime(2026, 11, 25)),
        },
        pausedDates: const {},
        frozenDates: const {},
        relapseDates: const {},
        targetAmount: null,
        amounts: const {},
        range: InsightRange.last30Days,
      );
      // Window starts 11-19: weeks 11-16 (4 available days) and 11-23 (3).
      expect(insight.tracked, 2);
      expect(insight.completed, 1);
      expect(insight.rate, 0.5);
    });

    test('weekly habits report the most active weekday without a rate', () {
      final insight = daily(
        ageDays: 25,
        checkins: {
          for (var d in [6, 13, 20]) formatDate(DateTime(2026, 11, d)),
          formatDate(DateTime(2026, 11, 2)),
        },
        schedule: const HabitSchedule.weeklyTarget(2),
      );
      expect(insight.bestWeekday, DateTime.friday);
      expect(insight.bestWeekdayRate, isNull);
    });
  });

  group('quit habits', () {
    test('counts clean days and relapses, ignoring freezes', () {
      final insight = buildHabitInsight(
        schedule: const HabitSchedule.daily(),
        kind: HabitKind.quit,
        startDate: DateTime(2026, 11, 16),
        today: today,
        checkins: const {},
        pausedDates: {day(3)},
        frozenDates: {day(4)},
        relapseDates: {day(1), day(5)},
        targetAmount: null,
        amounts: const {},
      );
      expect(insight.isQuit, isTrue);
      expect(insight.tracked, 9);
      expect(insight.completed, 7);
      expect(insight.relapses, 2);
      expect(insight.bestWeekday, isNull);
    });
  });

  group('routine aggregation', () {
    test('weights by tracked days and sorts by rate', () {
      const high = HabitInsight(
        completed: 9,
        tracked: 10,
        bestWeekday: null,
        bestWeekdayRate: null,
        relapses: 0,
        scheduleType: HabitScheduleType.daily,
        kind: HabitKind.build,
      );
      const low = HabitInsight(
        completed: 1,
        tracked: 10,
        bestWeekday: null,
        bestWeekdayRate: null,
        relapses: 0,
        scheduleType: HabitScheduleType.daily,
        kind: HabitKind.build,
      );
      final groups = buildRoutineInsights(
        labels: {1: 'Morning', null: 'Unrouted'},
        habits: [
          (routineId: 1, insight: high),
          (routineId: 1, insight: low),
          (routineId: null, insight: high),
        ],
      );
      expect(groups.map((g) => g.name), ['Unrouted', 'Morning']);
      expect(groups.last.habitCount, 2);
      expect(groups.last.completed, 10);
      expect(groups.last.tracked, 20);
      expect(groups.last.percent, 50);
    });

    test('groups without history sort last', () {
      const empty = HabitInsight.empty;
      final groups = buildRoutineInsights(
        labels: {1: 'Z', 2: 'A', null: 'None'},
        habits: [
          (routineId: 1, insight: empty),
          (routineId: 2, insight: empty),
          (routineId: null, insight: empty),
        ],
      );
      expect(groups.map((g) => g.name), ['A', 'None', 'Z']);
      expect(groups.first.rate, isNull);
    });
  });
}
