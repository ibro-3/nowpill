import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/domain/habit_schedule.dart';
import 'package:nowpill/domain/streak_engine.dart';

/// Measurable-habit engine matrix: only 100% of the numeric goal counts toward
/// the streak; partial progress is UI-only. Null target = byte-identical to
/// the classic engine.
void main() {
  final today = DateTime(2026, 11, 23);
  final start = DateTime(2026, 11, 14); // 10 days of history
  const daily = HabitSchedule.daily();

  String day(int offset) => formatDate(today.subtract(Duration(days: offset)));

  group('day-based measurable', () {
    test('null target reproduces classic output exactly', () {
      final checkins = {day(0), day(1), day(2)};
      final classic = replayStreak(
        schedule: daily,
        checkins: checkins,
        today: today,
        startDate: start,
      );
      final withNulls = replayStreak(
        schedule: daily,
        checkins: checkins,
        today: today,
        startDate: start,
        targetAmount: null,
        amounts: {day(0): 0.5}, // ignored when target is null
      );
      expect(withNulls.currentStreak, classic.currentStreak);
      expect(withNulls.bestStreak, classic.bestStreak);
      expect(withNulls.tokens, classic.tokens);
      expect(withNulls.completedDays, classic.completedDays);
    });

    test('full-goal days build the streak; partial days do not', () {
      final result = replayStreak(
        schedule: daily,
        checkins: {day(0), day(1), day(2)},
        today: today,
        startDate: start,
        targetAmount: 8,
        amounts: {day(0): 8, day(1): 3, day(2): 8},
      );
      // day(1) partial → streak broken; only today counts.
      expect(result.currentStreak, 1);
      expect(result.completedDays, 2);
    });

    test('overachieving counts as met', () {
      final result = replayStreak(
        schedule: daily,
        checkins: {day(0), day(1)},
        today: today,
        startDate: start,
        targetAmount: 8,
        amounts: {day(0): 12, day(1): 8},
      );
      expect(result.currentStreak, 2);
    });

    test('check-in without amount counts as full (one-tap / legacy)', () {
      final result = replayStreak(
        schedule: daily,
        checkins: {day(0), day(1)},
        today: today,
        startDate: start,
        targetAmount: 8,
        amounts: {day(0): 8}, // day(1) has no amount → full
      );
      expect(result.currentStreak, 2);
    });

    test('partial today leaves the streak intact but not extended', () {
      final result = replayStreak(
        schedule: daily,
        checkins: {day(0), day(1), day(2)},
        today: today,
        startDate: start,
        targetAmount: 8,
        amounts: {day(0): 2, day(1): 8, day(2): 8},
      );
      // Today partial: streak stays at the 2 prior full days (today never
      // counts as missed).
      expect(result.currentStreak, 2);
      expect(result.completedDays, 2);
    });

    test('a fully elapsed partial day is a miss (freeze can bridge)', () {
      // 7 full days earn a token, then a partial day consumes it.
      final checkins = <String>{};
      final amounts = <String, double>{};
      for (var i = 9; i >= 3; i--) {
        checkins.add(day(i));
        amounts[day(i)] = 8;
      }
      checkins.add(day(2));
      amounts[day(2)] = 1; // partial miss
      checkins.add(day(1));
      amounts[day(1)] = 8;
      checkins.add(day(0));
      amounts[day(0)] = 8;

      final result = replayStreak(
        schedule: daily,
        checkins: checkins,
        today: today,
        startDate: start,
        targetAmount: 8,
        amounts: amounts,
      );
      expect(result.frozenDates, contains(day(2)));
      expect(result.currentStreak, 10); // bridged, unbroken
    });

    test('tokens earned only on full-goal streak days', () {
      final checkins = <String>{};
      final amounts = <String, double>{};
      for (var i = 6; i >= 0; i--) {
        checkins.add(day(i));
        amounts[day(i)] = i == 3 ? 1 : 8; // one partial mid-run
      }
      final result = replayStreak(
        schedule: daily,
        checkins: checkins,
        today: today,
        startDate: start,
        targetAmount: 8,
        amounts: amounts,
      );
      // Partial day breaks the run: longest full run is 3 (days 2..0) or 3
      // (days 6..4) — never 7, so no token.
      expect(result.tokens, 0);
      expect(result.bestStreak, 3);
    });
  });

  group('weekly-target measurable', () {
    // Use the previous (fully elapsed) week so day offsets stay in the past.
    final lastMonday = startOfWeek(today).subtract(const Duration(days: 7));

    test('only full-goal days count toward the weekly target', () {
      // Weekly target 3; last week has 3 check-ins but one is partial.
      const schedule = HabitSchedule.weeklyTarget(3);
      final d0 = formatDate(lastMonday);
      final d1 = formatDate(lastMonday.add(const Duration(days: 1)));
      final d2 = formatDate(lastMonday.add(const Duration(days: 2)));
      final result = replayStreak(
        schedule: schedule,
        checkins: {d0, d1, d2},
        today: today,
        startDate: lastMonday,
        targetAmount: 8,
        amounts: {d0: 8, d1: 8, d2: 2},
      );
      expect(result.currentStreak, 0); // only 2 full days < target 3
      expect(result.completedDays, 2);
    });

    test('full-goal days meet the weekly target', () {
      const schedule = HabitSchedule.weeklyTarget(3);
      final days = {
        formatDate(lastMonday),
        formatDate(lastMonday.add(const Duration(days: 1))),
        formatDate(lastMonday.add(const Duration(days: 2))),
      };
      final result = replayStreak(
        schedule: schedule,
        checkins: days,
        today: today,
        startDate: lastMonday,
        targetAmount: 8,
        amounts: {for (final d in days) d: 8},
      );
      // Last week met (1); the current week is in progress (no penalty).
      expect(result.currentStreak, 1);
    });
  });

  group('dayMeetsGoal', () {
    test('null target always met', () {
      expect(dayMeetsGoal('2026-11-23', null, const {}), isTrue);
    });
    test('missing amount counts full', () {
      expect(dayMeetsGoal('2026-11-23', 8, const {}), isTrue);
    });
    test('partial below target not met', () {
      expect(dayMeetsGoal('2026-11-23', 8, {'2026-11-23': 7.5}), isFalse);
    });
    test('exact and above met', () {
      expect(dayMeetsGoal('2026-11-23', 8, {'2026-11-23': 8}), isTrue);
      expect(dayMeetsGoal('2026-11-23', 8, {'2026-11-23': 9}), isTrue);
    });
  });
}
