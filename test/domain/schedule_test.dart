import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/schedule.dart';

void main() {
  group('HabitSchedule.isDueOn', () {
    test('daily is due every day', () {
      const s = HabitSchedule.daily();
      for (var d = 16; d <= 22; d++) {
        expect(s.isDueOn(DateTime(2026, 11, d)), isTrue);
      }
    });

    test('weekdays due only on listed days', () {
      // Mon/Wed/Fri = 1/3/5. 2026-11-16 is Monday.
      const s = HabitSchedule.weekdays([1, 3, 5]);
      expect(s.isDueOn(DateTime(2026, 11, 16)), isTrue); // Mon
      expect(s.isDueOn(DateTime(2026, 11, 17)), isFalse); // Tue
      expect(s.isDueOn(DateTime(2026, 11, 18)), isTrue); // Wed
      expect(s.isDueOn(DateTime(2026, 11, 19)), isFalse); // Thu
      expect(s.isDueOn(DateTime(2026, 11, 20)), isTrue); // Fri
      expect(s.isDueOn(DateTime(2026, 11, 21)), isFalse); // Sat
      expect(s.isDueOn(DateTime(2026, 11, 22)), isFalse); // Sun
    });

    test('weeklyTarget is due any day', () {
      const s = HabitSchedule.weeklyTarget(3);
      expect(s.isDueOn(DateTime(2026, 11, 21)), isTrue);
      expect(s.isDueOn(DateTime(2026, 11, 22)), isTrue);
    });

    test('isDayBased distinguishes weeklyTarget', () {
      expect(const HabitSchedule.daily().isDayBased, isTrue);
      expect(const HabitSchedule.weekdays([1]).isDayBased, isTrue);
      expect(const HabitSchedule.weeklyTarget(3).isDayBased, isFalse);
    });
  });

  group('task overdue / today logic', () {
    final now = DateTime(2026, 11, 22, 15);

    test('due yesterday is overdue', () {
      expect(
        isTaskOverdue(
          dueAt: DateTime(2026, 11, 21, 9),
          now: now,
          completed: false,
        ),
        isTrue,
      );
    });

    test('due today is not overdue', () {
      expect(
        isTaskOverdue(
          dueAt: DateTime(2026, 11, 22, 23),
          now: now,
          completed: false,
        ),
        isFalse,
      );
    });

    test('due tomorrow is not overdue', () {
      expect(
        isTaskOverdue(
          dueAt: DateTime(2026, 11, 23),
          now: now,
          completed: false,
        ),
        isFalse,
      );
    });

    test('no due date is never overdue', () {
      expect(isTaskOverdue(dueAt: null, now: now, completed: false), isFalse);
    });

    test('completed task is never overdue', () {
      expect(
        isTaskOverdue(dueAt: DateTime(2026, 11, 1), now: now, completed: true),
        isFalse,
      );
    });

    test('isTaskDueToday matches only today', () {
      expect(
        isTaskDueToday(dueAt: DateTime(2026, 11, 22, 8), now: now),
        isTrue,
      );
      expect(isTaskDueToday(dueAt: DateTime(2026, 11, 21), now: now), isFalse);
      expect(isTaskDueToday(dueAt: null, now: now), isFalse);
    });

    test('isTaskInToday includes overdue and due-today, excludes future', () {
      expect(
        isTaskInToday(
          dueAt: DateTime(2026, 11, 20),
          now: now,
          completed: false,
        ),
        isTrue,
      );
      expect(
        isTaskInToday(
          dueAt: DateTime(2026, 11, 22),
          now: now,
          completed: false,
        ),
        isTrue,
      );
      expect(
        isTaskInToday(
          dueAt: DateTime(2026, 11, 23),
          now: now,
          completed: false,
        ),
        isFalse,
      );
      expect(
        isTaskInToday(dueAt: DateTime(2026, 11, 20), now: now, completed: true),
        isFalse,
      );
    });
  });
}
