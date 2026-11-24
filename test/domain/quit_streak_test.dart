import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/domain/habit_schedule.dart';
import 'package:nowpill/domain/streak_engine.dart';

/// Quit habits count clean days from the quit date; only relapses reset.
void main() {
  final today = DateTime(2026, 11, 24, 15);
  const schedule = HabitSchedule.daily();

  StreakResult replay({
    required DateTime start,
    Set<String> relapses = const {},
    Set<String> paused = const {},
  }) {
    return replayStreak(
      schedule: schedule,
      checkins: const {},
      today: today,
      startDate: start,
      kind: HabitKind.quit,
      relapses: relapses,
      pausedDates: paused,
    );
  }

  test('every day since the quit date is clean without any input', () {
    final result = replay(start: DateTime(2026, 11, 21));
    expect(result.currentStreak, 4); // 21, 22, 23, 24
    expect(result.bestStreak, 4);
    expect(result.completedDays, 4);
    expect(result.tokens, 0);
    expect(result.frozenDates, isEmpty);
  });

  test('a relapse resets the current streak but keeps the best', () {
    final result = replay(
      start: DateTime(2026, 11, 18),
      relapses: {formatDate(DateTime(2026, 11, 22))},
    );
    expect(result.currentStreak, 2); // 23, 24
    expect(result.bestStreak, 4); // 18…21
    expect(result.completedDays, 6);
  });

  test('a relapse today means zero days clean', () {
    final result = replay(
      start: DateTime(2026, 11, 20),
      relapses: {formatDate(today)},
    );
    expect(result.currentStreak, 0);
    expect(result.bestStreak, 4);
  });

  test('a relapse before the quit date is ignored', () {
    final result = replay(
      start: DateTime(2026, 11, 20),
      relapses: {formatDate(DateTime(2026, 11, 1))},
    );
    expect(result.currentStreak, 5);
  });

  test('vacation days are neutral: no gain, no reset', () {
    final result = replay(
      start: DateTime(2026, 11, 20),
      paused: {
        formatDate(DateTime(2026, 11, 22)),
        formatDate(DateTime(2026, 11, 23)),
      },
    );
    expect(result.currentStreak, 3); // 20, 21, 24
    expect(result.completedDays, 3);
  });

  test('kind defaults to build and paused days default to no-op', () {
    final result = replayStreak(
      schedule: schedule,
      checkins: const {},
      today: today,
      startDate: DateTime(2026, 11, 23),
    );
    expect(result.currentStreak, 0);
    expect(result.bestStreak, 0);
  });
}
