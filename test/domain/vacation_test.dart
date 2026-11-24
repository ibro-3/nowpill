import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/domain/habit_schedule.dart';
import 'package:nowpill/domain/streak_engine.dart';
import 'package:nowpill/domain/vacation.dart';

void main() {
  group('expandPausedDates', () {
    test('expands inclusive ranges and ignores inverted ones', () {
      final result = expandPausedDates([
        const VacationPeriod(start: '2026-11-20', end: '2026-11-22'),
        const VacationPeriod(start: '2026-12-02', end: '2026-12-01'),
      ]);
      expect(result, {'2026-11-20', '2026-11-21', '2026-11-22'});
    });

    test('clamps to the requested window', () {
      final result = expandPausedDates(
        [const VacationPeriod(start: '2026-11-01', end: '2026-11-30')],
        from: '2026-11-20',
        to: '2026-11-21',
      );
      expect(result, {'2026-11-20', '2026-11-21'});
    });

    test('isDayPaused checks bounds without expanding', () {
      final periods = [
        const VacationPeriod(start: '2026-11-20', end: '2026-11-22'),
      ];
      expect(isDayPaused(DateTime(2026, 11, 22), periods), isTrue);
      expect(isDayPaused(DateTime(2026, 11, 23), periods), isFalse);
    });
  });

  group('isWeekFullyPaused', () {
    test('a whole week counts, a partial week does not', () {
      final full = expandPausedDates([
        const VacationPeriod(start: '2026-11-09', end: '2026-11-15'),
      ]);
      final partial = expandPausedDates([
        const VacationPeriod(start: '2026-11-09', end: '2026-11-11'),
      ]);
      expect(
        isWeekFullyPaused(
          weekStart: DateTime(2026, 11, 9),
          habitStart: DateTime(2026, 11, 2),
          today: DateTime(2026, 11, 24),
          pausedDates: full,
        ),
        isTrue,
      );
      expect(
        isWeekFullyPaused(
          weekStart: DateTime(2026, 11, 9),
          habitStart: DateTime(2026, 11, 2),
          today: DateTime(2026, 11, 24),
          pausedDates: partial,
        ),
        isFalse,
      );
    });

    test('only active, elapsed days need coverage', () {
      // Habit created on Thursday and a week that is still in progress.
      expect(
        isWeekFullyPaused(
          weekStart: DateTime(2026, 11, 9),
          habitStart: DateTime(2026, 11, 12),
          today: DateTime(2026, 11, 13),
          pausedDates: {
            formatDate(DateTime(2026, 11, 12)),
            formatDate(DateTime(2026, 11, 13)),
          },
        ),
        isTrue,
      );
      expect(
        isWeekFullyPaused(
          weekStart: DateTime(2026, 11, 9),
          habitStart: DateTime(2026, 11, 2),
          today: DateTime(2026, 11, 24),
          pausedDates: const {},
        ),
        isFalse,
      );
    });
  });

  group('paused days in streak replay', () {
    final today = DateTime(2026, 11, 24, 12);
    const daily = HabitSchedule.daily();

    test(
      'a missed day inside a vacation neither breaks nor extends a streak',
      () {
        final paused = {
          formatDate(DateTime(2026, 11, 22)),
          formatDate(DateTime(2026, 11, 23)),
        };
        final result = replayStreak(
          schedule: daily,
          checkins: {
            formatDate(DateTime(2026, 11, 20)),
            formatDate(DateTime(2026, 11, 21)),
            formatDate(today),
          },
          today: today,
          startDate: DateTime(2026, 11, 20),
          pausedDates: paused,
        );
        expect(result.currentStreak, 3);
        expect(result.bestStreak, 3);
        expect(result.frozenDates, isEmpty);
        expect(result.tokens, 0);
      },
    );

    test('a missed day still breaks the streak outside the vacation', () {
      final result = replayStreak(
        schedule: daily,
        checkins: {formatDate(DateTime(2026, 11, 20))},
        today: today,
        startDate: DateTime(2026, 11, 20),
        pausedDates: {formatDate(DateTime(2026, 11, 22))},
      );
      expect(result.currentStreak, 0); // 21 was a miss
    });

    test('a check-in during a vacation still counts', () {
      final result = replayStreak(
        schedule: daily,
        checkins: {
          formatDate(DateTime(2026, 11, 20)),
          formatDate(DateTime(2026, 11, 21)),
          formatDate(DateTime(2026, 11, 22)),
          formatDate(DateTime(2026, 11, 23)),
        },
        today: today,
        startDate: DateTime(2026, 11, 20),
        pausedDates: {formatDate(DateTime(2026, 11, 22))},
      );
      expect(result.currentStreak, 4);
    });

    test('a fully paused weekly-target week is skipped', () {
      const schedule = HabitSchedule.weeklyTarget(3);
      final result = replayStreak(
        schedule: schedule,
        checkins: {
          formatDate(DateTime(2026, 11, 3)),
          formatDate(DateTime(2026, 11, 4)),
          formatDate(DateTime(2026, 11, 5)),
          formatDate(DateTime(2026, 11, 17)),
          formatDate(DateTime(2026, 11, 18)),
          formatDate(DateTime(2026, 11, 19)),
        },
        today: today,
        startDate: DateTime(2026, 11, 2),
        pausedDates: expandPausedDates([
          const VacationPeriod(start: '2026-11-09', end: '2026-11-15'),
        ]),
      );
      // Weeks of Nov 2 and Nov 16 met the target; Nov 9 was paused (not missed).
      expect(result.currentStreak, 2);
    });

    test('a partially paused weekly-target week can still be missed', () {
      final result = replayStreak(
        schedule: const HabitSchedule.weeklyTarget(3),
        checkins: {
          formatDate(DateTime(2026, 11, 3)),
          formatDate(DateTime(2026, 11, 4)),
          formatDate(DateTime(2026, 11, 5)),
          formatDate(DateTime(2026, 11, 17)),
          formatDate(DateTime(2026, 11, 18)),
          formatDate(DateTime(2026, 11, 19)),
        },
        today: today,
        startDate: DateTime(2026, 11, 2),
        pausedDates: expandPausedDates([
          const VacationPeriod(start: '2026-11-09', end: '2026-11-11'),
        ]),
      );
      // Mon–Wed off does not excuse Thu–Sun: the Nov 9 week still breaks it.
      expect(result.currentStreak, 1);
    });

    test('paused days never spend freeze tokens', () {
      final result = replayStreak(
        schedule: daily,
        checkins: const {},
        today: today,
        startDate: DateTime(2026, 11, 20),
        pausedDates: expandPausedDates([
          const VacationPeriod(start: '2026-11-20', end: '2026-11-23'),
        ]),
      );
      expect(result.tokens, 0);
      expect(result.frozenDates, isEmpty);
    });
  });

  test('HabitKind enum indexes are stable', () {
    expect(HabitKind.build.index, 0);
    expect(HabitKind.quit.index, 1);
  });
}
