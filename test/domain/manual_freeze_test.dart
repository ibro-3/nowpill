import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/domain/habit_schedule.dart';
import 'package:nowpill/domain/streak_engine.dart';

/// Manual freeze mode: tokens are spent only on explicit user-placed freezes.
/// Auto mode (the default) must remain byte-for-byte identical to v0.1.0.
void main() {
  // 2026-11-16 is a Monday; 2026-11-22 a Sunday.
  final today = DateTime(2026, 11, 22);
  final start = DateTime(2026, 11, 16);

  StreakResult replay(
    Set<String> checkins, {
    FreezeMode mode = FreezeMode.manual,
    Set<String> freezes = const {},
    HabitSchedule schedule = const HabitSchedule.daily(),
    DateTime? asOf,
    DateTime? from,
  }) {
    return replayStreak(
      schedule: schedule,
      checkins: checkins,
      today: asOf ?? today,
      startDate: from ?? start,
      freezeMode: mode,
      manualFreezes: freezes,
    );
  }

  group('auto mode is unchanged', () {
    test('default params auto-consume a token on a miss', () {
      // Mon–Sat checked (6), Sun today checked → 7 streak, 1 token earned.
      // Use a longer history: 7 checked then a miss then checked.
      final r = replayStreak(
        schedule: const HabitSchedule.daily(),
        checkins: {
          '2026-11-09', '2026-11-10', '2026-11-11', '2026-11-12',
          '2026-11-13', '2026-11-14', '2026-11-15', // 7 → earn token
          '2026-11-17', '2026-11-18', '2026-11-19', '2026-11-20',
          '2026-11-21', '2026-11-22',
        },
        today: today,
        startDate: DateTime(2026, 11, 9),
      );
      // 11-16 missed → auto freeze bridges it. 14 elapsed days, streak 14
      // earns a second token at day 14.
      expect(r.frozenDates, contains('2026-11-16'));
      expect(r.currentStreak, 14);
      expect(r.tokens, 1);
    });

    test('explicit manualFreezes are ignored in auto mode', () {
      final r = replay(
        {
          '2026-11-16',
          '2026-11-17',
          '2026-11-18',
          '2026-11-19',
          '2026-11-20',
          '2026-11-21',
        },
        mode: FreezeMode.auto,
        freezes: {'2026-11-22'}, // today; irrelevant
      );
      expect(r.currentStreak, 6);
      expect(r.frozenDates, isEmpty);
    });
  });

  group('manual mode', () {
    test('a miss without an explicit freeze resets the streak', () {
      // Earn a token over the first 7 days, then miss a day with no freeze.
      final r = replay(
        {
          '2026-11-09',
          '2026-11-10',
          '2026-11-11',
          '2026-11-12',
          '2026-11-13',
          '2026-11-14',
          '2026-11-15',
          '2026-11-17',
          '2026-11-18',
          '2026-11-19',
          '2026-11-20',
          '2026-11-21',
          '2026-11-22',
        },
        from: DateTime(2026, 11, 9),
        freezes: {}, // no explicit freeze on 11-16
      );
      expect(r.frozenDates, isEmpty);
      expect(r.currentStreak, 6); // reset at 11-16, rebuilt 17–22
      expect(r.tokens, 1); // earned but unspent
    });

    test('an explicit freeze bridges the miss and spends a token', () {
      final r = replay(
        {
          '2026-11-09',
          '2026-11-10',
          '2026-11-11',
          '2026-11-12',
          '2026-11-13',
          '2026-11-14',
          '2026-11-15',
          '2026-11-17',
          '2026-11-18',
          '2026-11-19',
          '2026-11-20',
          '2026-11-21',
          '2026-11-22',
        },
        from: DateTime(2026, 11, 9),
        freezes: {'2026-11-16'},
      );
      expect(r.frozenDates, contains('2026-11-16'));
      expect(r.currentStreak, 14);
      expect(r.tokens, 1); // spent 1 on the freeze, earned another at streak 14
    });

    test('an explicit freeze with no token available still resets', () {
      // Only 3 checked days → no token earned; freeze on the miss can't spend.
      final r = replay(
        {
          '2026-11-16',
          '2026-11-17',
          '2026-11-18',
          '2026-11-20',
          '2026-11-21',
          '2026-11-22',
        },
        freezes: {'2026-11-19'},
      );
      expect(r.frozenDates, isEmpty);
      expect(r.currentStreak, 3); // reset at 11-19
      expect(r.tokens, 0);
    });

    test('backfilling a frozen day refunds the token', () {
      final checkins = {
        '2026-11-09',
        '2026-11-10',
        '2026-11-11',
        '2026-11-12',
        '2026-11-13',
        '2026-11-14',
        '2026-11-15',
        '2026-11-17',
        '2026-11-18',
        '2026-11-19',
        '2026-11-20',
        '2026-11-21',
        '2026-11-22',
      };
      final frozen = replay(
        checkins,
        from: DateTime(2026, 11, 9),
        freezes: {'2026-11-16'},
      );
      expect(frozen.tokens, 1); // earned 2 (streak 7 & 14), spent 1
      // Add the real check-in for the frozen day → freeze no longer needed.
      final backfilled = replay(
        {...checkins, '2026-11-16'},
        from: DateTime(2026, 11, 9),
        freezes: {'2026-11-16'},
      );
      expect(backfilled.frozenDates, isEmpty);
      expect(backfilled.tokens, 2); // refunded: nothing spent
      expect(backfilled.currentStreak, 14);
    });

    test('tokens still accrue while unspent (cap 3)', () {
      // 21 consecutive checked days → 3 tokens, no misses.
      final checkins = <String>{};
      for (var i = 0; i < 21; i++) {
        checkins.add(formatDate(DateTime(2026, 11, 1).add(Duration(days: i))));
      }
      final r = replay(
        checkins,
        from: DateTime(2026, 11, 1),
        asOf: DateTime(2026, 11, 21),
      );
      expect(r.tokens, 3);
      expect(r.currentStreak, 21);
    });
  });

  group('manual weekly-target', () {
    test('explicit freeze on the week Monday bridges a missed week', () {
      // Week of 11-09 complete (target 2), week of 11-16 missed, current week
      // of 11-23 in progress. Earn cadence is 4 weeks so seed a longer history.
      final r = replayStreak(
        schedule: const HabitSchedule.weeklyTarget(2),
        checkins: {
          // 4 completed weeks to earn a token (Oct 19 .. Nov 15).
          '2026-10-19', '2026-10-20',
          '2026-10-26', '2026-10-27',
          '2026-11-02', '2026-11-03',
          '2026-11-09', '2026-11-10',
          // week of 11-16 missed; current week 11-23 met.
          '2026-11-23', '2026-11-24',
        },
        today: DateTime(2026, 11, 25),
        startDate: DateTime(2026, 10, 19),
        freezeMode: FreezeMode.manual,
        manualFreezes: {'2026-11-16'},
      );
      expect(r.frozenDates, contains('2026-11-16'));
      expect(r.tokens, 0);
      expect(r.currentStreak, 6); // 4 + frozen week + current
    });

    test('missed week without explicit freeze resets', () {
      final r = replayStreak(
        schedule: const HabitSchedule.weeklyTarget(2),
        checkins: {
          '2026-10-19',
          '2026-10-20',
          '2026-10-26',
          '2026-10-27',
          '2026-11-02',
          '2026-11-03',
          '2026-11-09',
          '2026-11-10',
          '2026-11-23',
          '2026-11-24',
        },
        today: DateTime(2026, 11, 25),
        startDate: DateTime(2026, 10, 19),
        freezeMode: FreezeMode.manual,
        manualFreezes: {},
      );
      expect(r.frozenDates, isEmpty);
      expect(r.currentStreak, 1); // only current week
      expect(r.tokens, 1);
    });
  });
}
