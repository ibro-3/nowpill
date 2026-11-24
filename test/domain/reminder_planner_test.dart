import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/habit_schedule.dart';
import 'package:nowpill/domain/reminder_planner.dart';

void main() {
  // 2026-11-23 is a Monday.
  final now = DateTime(2026, 11, 23, 8);
  final at9 = DateTime(2026, 11, 23, 9);

  group('planHabitReminders', () {
    test('null reminder time yields nothing', () {
      final r = planHabitReminders(
        habitName: 'Meditate',
        schedule: const HabitSchedule.daily(),
        reminderTime: null,
        now: now,
        checkedDays: const {},
      );
      expect(r, isEmpty);
    });

    test('daily plans the next 7 days at the reminder time', () {
      final r = planHabitReminders(
        habitName: 'Meditate',
        schedule: const HabitSchedule.daily(),
        reminderTime: at9,
        now: now,
        checkedDays: const {},
      );
      expect(r, hasLength(7));
      expect(r.first.when, DateTime(2026, 11, 23, 9));
      expect(r.last.when, DateTime(2026, 11, 29, 9));
      expect(r.every((o) => o.label == 'Meditate'), isTrue);
    });

    test('skips today when the reminder time already passed', () {
      final r = planHabitReminders(
        habitName: 'Meditate',
        schedule: const HabitSchedule.daily(),
        reminderTime: DateTime(2026, 11, 23, 7),
        now: now, // 08:00, reminder was 07:00
        checkedDays: const {},
        count: 3,
      );
      expect(r.first.when, DateTime(2026, 11, 24, 7));
      expect(r, hasLength(3));
    });

    test('skips days already checked in', () {
      final r = planHabitReminders(
        habitName: 'Meditate',
        schedule: const HabitSchedule.daily(),
        reminderTime: at9,
        now: now,
        checkedDays: const {'2026-11-23', '2026-11-25'},
        count: 3,
      );
      expect(r.map((o) => o.when.day).toList(), [24, 26, 27]);
    });

    test('skips planned vacation days', () {
      final r = planHabitReminders(
        habitName: 'Meditate',
        schedule: const HabitSchedule.daily(),
        reminderTime: at9,
        now: now,
        checkedDays: const {},
        pausedDays: const {'2026-11-24', '2026-11-26'},
        count: 3,
      );
      expect(r.map((o) => o.when.day).toList(), [23, 25, 27]);
    });

    test('weekdays schedule only fires on listed days', () {
      // Mon/Wed/Fri = 1/3/5.
      final r = planHabitReminders(
        habitName: 'Gym',
        schedule: const HabitSchedule.weekdays([1, 3, 5]),
        reminderTime: at9,
        now: now,
        checkedDays: const {},
        count: 4,
      );
      // Mon 23, Wed 25, Fri 27, Mon 30.
      expect(r.map((o) => o.when.day).toList(), [23, 25, 27, 30]);
      expect(r.every((o) => [1, 3, 5].contains(o.when.weekday)), isTrue);
    });

    test('weeklyTarget fires every day', () {
      final r = planHabitReminders(
        habitName: 'Journal',
        schedule: const HabitSchedule.weeklyTarget(3),
        reminderTime: at9,
        now: now,
        checkedDays: const {},
        count: 2,
      );
      expect(r.map((o) => o.when.day).toList(), [23, 24]);
    });

    test('count zero yields nothing', () {
      final r = planHabitReminders(
        habitName: 'Meditate',
        schedule: const HabitSchedule.daily(),
        reminderTime: at9,
        now: now,
        checkedDays: const {},
        count: 0,
      );
      expect(r, isEmpty);
    });
  });

  group('planTaskReminder', () {
    test('future reminder is planned', () {
      final r = planTaskReminder(
        taskTitle: 'Pay rent',
        reminderAt: DateTime(2026, 11, 24, 9),
        now: now,
        completed: false,
      );
      expect(r, hasLength(1));
      expect(r.single.when, DateTime(2026, 11, 24, 9));
      expect(r.single.label, 'Pay rent');
    });

    test('null, past, and completed yield nothing', () {
      expect(
        planTaskReminder(
          taskTitle: 'X',
          reminderAt: null,
          now: now,
          completed: false,
        ),
        isEmpty,
      );
      expect(
        planTaskReminder(
          taskTitle: 'X',
          reminderAt: DateTime(2026, 11, 22, 9),
          now: now,
          completed: false,
        ),
        isEmpty,
      );
      expect(
        planTaskReminder(
          taskTitle: 'X',
          reminderAt: DateTime(2026, 11, 24, 9),
          now: now,
          completed: true,
        ),
        isEmpty,
      );
    });
  });

  group('notification ids', () {
    test('habit slots are stable and distinct', () {
      expect(habitReminderId(1, 0), 100100);
      expect(habitReminderId(1, 1), 100101);
      expect(habitReminderId(2, 0), 100200);
      expect(habitReminderId(1, 0), isNot(habitReminderId(2, 0)));
    });

    test('task ids do not collide with habit ids', () {
      expect(taskReminderId(1), 900001);
      expect(taskReminderId(1), isNot(habitReminderId(1, 0)));
    });
  });
}
