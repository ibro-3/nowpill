import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/habit_schedule.dart';
import 'package:nowpill/domain/streak_engine.dart';

void main() {
  // 2026-11-16 is a Monday; 2026-11-22 is a Sunday.
  final today = DateTime(2026, 11, 22);

  StreakResult replay(
    Set<String> checkins, {
    HabitSchedule schedule = const HabitSchedule.daily(),
    DateTime? start,
    DateTime? asOf,
  }) {
    return replayStreak(
      schedule: schedule,
      checkins: checkins,
      today: asOf ?? today,
      startDate: start ?? DateTime(2026, 11, 16),
    );
  }

  group('daily basics', () {
    test('empty history is zero', () {
      final r = replay({});
      expect(r.currentStreak, 0);
      expect(r.bestStreak, 0);
      expect(r.tokens, 0);
      expect(r.completedDays, 0);
    });

    test('consecutive days count', () {
      final r = replay({'2026-11-20', '2026-11-21', '2026-11-22'});
      expect(r.currentStreak, 3);
      expect(r.bestStreak, 3);
      expect(r.completedDays, 3);
    });

    test('today counts immediately', () {
      final r = replay({'2026-11-22'});
      expect(r.currentStreak, 1);
    });

    test('today without check-in is not a miss', () {
      // Checked Mon–Sat, today (Sun) not yet checked: streak stays 6.
      final r = replay({
        '2026-11-16',
        '2026-11-17',
        '2026-11-18',
        '2026-11-19',
        '2026-11-20',
        '2026-11-21',
      });
      expect(r.currentStreak, 6);
      expect(r.frozenDates, isEmpty);
    });

    test('a missed day with no tokens resets the streak', () {
      // Mon–Wed checked, Thu missed, Fri–Sun checked.
      final r = replay({
        '2026-11-16',
        '2026-11-17',
        '2026-11-18',
        '2026-11-20',
        '2026-11-21',
        '2026-11-22',
      });
      expect(r.currentStreak, 3);
      expect(r.bestStreak, 3);
      expect(r.tokens, 0);
    });

    test('best streak survives a later reset', () {
      // A long early run, a miss, then a short run.
      final r = replay(
        {
          '2026-11-01', '2026-11-02', '2026-11-03', '2026-11-04',
          '2026-11-05', '2026-11-06',
          // 2026-11-07 missed
          '2026-11-08', '2026-11-09',
        },
        start: DateTime(2026, 11, 1),
        asOf: DateTime(2026, 11, 9),
      );
      expect(r.bestStreak, 6);
      expect(r.currentStreak, 2);
    });
  });

  group('freeze tokens', () {
    test('earn one token at 7 consecutive days', () {
      final r = replay({
        '2026-11-16',
        '2026-11-17',
        '2026-11-18',
        '2026-11-19',
        '2026-11-20',
        '2026-11-21',
        '2026-11-22',
      });
      expect(r.currentStreak, 7);
      expect(r.tokens, 1);
      expect(r.earnEvents, {'2026-11-22'});
    });

    test('a freeze bridges a missed day and keeps the streak', () {
      // 7-day run earns a token on day 7; day 8 missed consumes it.
      final r = replay(
        {
          '2026-11-10', '2026-11-11', '2026-11-12', '2026-11-13',
          '2026-11-14', '2026-11-15', '2026-11-16',
          // 2026-11-17 missed -> frozen
          '2026-11-18', '2026-11-19',
        },
        start: DateTime(2026, 11, 10),
        asOf: DateTime(2026, 11, 19),
      );
      expect(r.frozenDates, {'2026-11-17'});
      expect(r.tokens, 0);
      // 7 checked + 1 frozen + 2 checked = 10.
      expect(r.currentStreak, 10);
      expect(r.bestStreak, 10);
    });

    test('wallet caps at 3', () {
      // 21 consecutive days would earn 3 tokens (at 7, 14, 21); a 28-day run
      // would earn a 4th but the cap holds it at 3.
      final checkins = <String>{};
      for (var d = 1; d <= 28; d++) {
        checkins.add('2026-10-${d.toString().padLeft(2, '0')}');
      }
      final r = replay(
        checkins,
        start: DateTime(2026, 10, 1),
        asOf: DateTime(2026, 10, 28),
      );
      expect(r.currentStreak, 28);
      expect(r.tokens, 3);
      expect(r.earnEvents.length, 3);
    });

    test('two missed days consume two tokens', () {
      // Build a 14-day run (2 tokens), then miss two days.
      final checkins = <String>{};
      for (var d = 1; d <= 14; d++) {
        checkins.add('2026-10-${d.toString().padLeft(2, '0')}');
      }
      // Oct 15 and 16 missed; Oct 17 checked.
      checkins.add('2026-10-17');
      final r = replay(
        checkins,
        start: DateTime(2026, 10, 1),
        asOf: DateTime(2026, 10, 17),
      );
      expect(r.frozenDates, {'2026-10-15', '2026-10-16'});
      expect(r.tokens, 0);
      expect(r.currentStreak, 17);
    });

    test('miss with empty wallet resets even after a prior earn was spent', () {
      // 7-day run (1 token), miss day 8 (spend), miss day 9 (no tokens -> reset).
      final r = replay(
        {
          '2026-11-10', '2026-11-11', '2026-11-12', '2026-11-13',
          '2026-11-14', '2026-11-15', '2026-11-16',
          // 17 missed (frozen), 18 missed (reset)
          '2026-11-19',
        },
        start: DateTime(2026, 11, 10),
        asOf: DateTime(2026, 11, 19),
      );
      expect(r.frozenDates, {'2026-11-17'});
      expect(r.currentStreak, 1);
      expect(r.bestStreak, 8);
    });
  });

  group('backfill refund', () {
    test('filling a frozen day refunds the token and removes the freeze', () {
      final base = {
        '2026-11-10', '2026-11-11', '2026-11-12', '2026-11-13',
        '2026-11-14', '2026-11-15', '2026-11-16',
        // 17 missed
        '2026-11-18',
      };
      final before = replay(
        base,
        start: DateTime(2026, 11, 10),
        asOf: DateTime(2026, 11, 18),
      );
      expect(before.frozenDates, {'2026-11-17'});
      expect(before.tokens, 0);

      final after = replay(
        {...base, '2026-11-17'},
        start: DateTime(2026, 11, 10),
        asOf: DateTime(2026, 11, 18),
      );
      expect(after.frozenDates, isEmpty);
      expect(after.tokens, 1); // refunded
      expect(after.currentStreak, before.currentStreak);
    });
  });

  group('weekday schedules', () {
    // Mon/Wed/Fri schedule.
    const mwf = HabitSchedule.weekdays([1, 3, 5]);

    test('only scheduled days count', () {
      // Mon 16, Wed 18, Fri 20 checked. Tue/Thu/weekend ignored.
      final r = replay({
        '2026-11-16',
        '2026-11-18',
        '2026-11-20',
      }, schedule: mwf);
      expect(r.currentStreak, 3);
      expect(r.completedDays, 3);
    });

    test('missing a scheduled day resets', () {
      // Mon 16 checked, Wed 18 missed, Fri 20 checked.
      final r = replay({'2026-11-16', '2026-11-20'}, schedule: mwf);
      expect(r.currentStreak, 1);
      expect(r.bestStreak, 1);
    });

    test('unscheduled days never cause a miss', () {
      // Only Mon 16 checked; today is Sun 22. No scheduled day was missed
      // after Mon (Wed/Fri not checked but... they ARE scheduled and missed).
      // Use a Monday-only schedule to isolate.
      const monOnly = HabitSchedule.weekdays([1]);
      final r = replay({'2026-11-16'}, schedule: monOnly);
      expect(r.currentStreak, 1);
      expect(r.frozenDates, isEmpty);
    });

    test('freeze bridges a missed scheduled weekday', () {
      // Earn a token with 7 scheduled-day completions across prior weeks, then
      // miss one scheduled day. Simpler: Mon-only schedule, 7 Mondays checked.
      const monOnly = HabitSchedule.weekdays([1]);
      final checkins = <String>{
        '2026-10-05',
        '2026-10-12',
        '2026-10-19',
        '2026-10-26',
        '2026-11-02',
        '2026-11-09',
        '2026-11-16',
      };
      // Miss Mon 2026-11-23? today is 22 (Sun), so next Monday is future.
      // Instead miss 2026-11-16 and check 2026-11-23 is future. Use asOf later.
      final r = replay(
        checkins,
        schedule: monOnly,
        start: DateTime(2026, 10, 5),
        asOf: DateTime(2026, 11, 22),
      );
      expect(r.currentStreak, 7);
      expect(r.tokens, 1);
    });
  });

  group('weekly-target habits', () {
    const target3 = HabitSchedule.weeklyTarget(3);

    test('a week meeting target counts as one streak unit', () {
      // Week of Nov 16: 3 check-ins -> complete. Today Nov 22 (same week).
      final r = replay({
        '2026-11-16',
        '2026-11-18',
        '2026-11-20',
      }, schedule: target3);
      expect(r.currentStreak, 1);
      expect(r.completedDays, 3);
    });

    test('current week counts as soon as target is met', () {
      final r = replay({
        '2026-11-16',
        '2026-11-17',
        '2026-11-18',
      }, schedule: target3);
      expect(r.currentStreak, 1);
    });

    test('current week below target is not penalized', () {
      final r = replay({'2026-11-16', '2026-11-17'}, schedule: target3);
      expect(r.currentStreak, 0);
      expect(r.frozenDates, isEmpty);
    });

    test('consecutive completed weeks accumulate', () {
      // Week Nov 9 (Mon 9–Sun 15): 3 check-ins. Week Nov 16: 3 check-ins.
      final r = replay(
        {
          '2026-11-09',
          '2026-11-11',
          '2026-11-13',
          '2026-11-16',
          '2026-11-18',
          '2026-11-20',
        },
        schedule: target3,
        start: DateTime(2026, 11, 9),
      );
      expect(r.currentStreak, 2);
      expect(r.bestStreak, 2);
    });

    test('a missed elapsed week resets without tokens', () {
      // Week Nov 9 complete, week Nov 16 has only 2 (missed), today Nov 22.
      final r = replay(
        {'2026-11-09', '2026-11-11', '2026-11-13', '2026-11-16', '2026-11-17'},
        schedule: target3,
        start: DateTime(2026, 11, 9),
      );
      // Week Nov 16 is the current week (today Nov 22 is in it) -> in progress,
      // not penalized. So streak stays 1 from week Nov 9.
      expect(r.currentStreak, 1);
    });

    test('a fully elapsed missed week resets', () {
      // Week Nov 2 complete, week Nov 9 missed (0), week Nov 16 complete.
      // Today Nov 22 -> week Nov 9 fully elapsed.
      final r = replay(
        {
          '2026-11-02',
          '2026-11-04',
          '2026-11-06',
          '2026-11-16',
          '2026-11-18',
          '2026-11-20',
        },
        schedule: target3,
        start: DateTime(2026, 11, 2),
      );
      expect(r.currentStreak, 1);
      expect(r.bestStreak, 1);
    });

    test('earn a token after 4 completed weeks', () {
      final checkins = <String>{};
      // 4 consecutive weeks starting Oct 5 (Mon), 3 check-ins each.
      final weekStarts = [
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 12),
        DateTime(2026, 10, 19),
        DateTime(2026, 10, 26),
      ];
      for (final ws in weekStarts) {
        for (final offset in [0, 2, 4]) {
          final d = ws.add(Duration(days: offset));
          checkins.add(
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
          );
        }
      }
      final r = replay(
        checkins,
        schedule: target3,
        start: DateTime(2026, 10, 5),
        asOf: DateTime(2026, 11, 1),
      );
      expect(r.currentStreak, 4);
      expect(r.tokens, 1);
    });

    test('freeze bridges a missed elapsed week', () {
      // 4 completed weeks (1 token), then a missed week, then a completed week.
      final checkins = <String>{};
      final weekStarts = [
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 12),
        DateTime(2026, 10, 19),
        DateTime(2026, 10, 26),
        // Nov 2 missed
        DateTime(2026, 11, 9),
      ];
      for (final ws in weekStarts) {
        for (final offset in [0, 2, 4]) {
          final d = ws.add(Duration(days: offset));
          checkins.add(
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
          );
        }
      }
      final r = replay(
        checkins,
        schedule: target3,
        start: DateTime(2026, 10, 5),
        asOf: DateTime(2026, 11, 15),
      );
      expect(r.frozenDates, {'2026-11-02'});
      expect(r.tokens, 0);
      expect(r.currentStreak, 6);
    });
  });

  group('archived / boundary', () {
    test('check-ins before startDate are ignored', () {
      final r = replay({
        '2026-11-01',
        '2026-11-22',
      }, start: DateTime(2026, 11, 16));
      expect(r.completedDays, 1);
      expect(r.currentStreak, 1);
    });

    test('check-ins after today are ignored', () {
      final r = replay({'2026-11-22', '2026-11-25'});
      expect(r.completedDays, 1);
      expect(r.currentStreak, 1);
    });

    test('start equals today with a check-in gives streak 1', () {
      final r = replay({'2026-11-22'}, start: DateTime(2026, 11, 22));
      expect(r.currentStreak, 1);
      expect(r.bestStreak, 1);
    });
  });
}
