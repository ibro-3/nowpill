import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/notifications/notification_action_handler.dart';
import 'package:nowpill/data/notifications/reminder_coordinator.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/domain/habit_schedule.dart';
import 'package:nowpill/domain/reminder_planner.dart';

import 'test_database.dart';

/// Notification actions (Phase 22): payload round-trip, planner payloads, and
/// the resume stream-refresh that surfaces background-isolate writes.
void main() {
  group('parseReminderPayload', () {
    test('habit payload round-trips id, day, and label', () {
      final planned = planHabitReminders(
        habitName: 'Read',
        schedule: const HabitSchedule.daily(),
        reminderTime: DateTime(2026, 11, 23, 21),
        now: DateTime(2026, 11, 23, 8),
        checkedDays: const {},
        habitId: 7,
      );
      expect(planned, isNotEmpty);
      final parsed = parseReminderPayload(planned.first.payload);
      expect(parsed, isNotNull);
      expect(parsed!.kind, 'habit');
      expect(parsed.id, 7);
      expect(parsed.dayKey, formatDate(DateTime(2026, 11, 23)));
      expect(parsed.label, 'Read');
    });

    test('task payload round-trips id and label', () {
      final planned = planTaskReminder(
        taskTitle: 'Call dentist',
        reminderAt: DateTime(2026, 11, 23, 15),
        now: DateTime(2026, 11, 23, 8),
        completed: false,
        taskId: 42,
      );
      final parsed = parseReminderPayload(planned.single.payload);
      expect(parsed!.kind, 'task');
      expect(parsed.id, 42);
      expect(parsed.label, 'Call dentist');
    });

    test('label containing colons survives', () {
      final planned = planTaskReminder(
        taskTitle: 'Review: PR 5',
        reminderAt: DateTime(2026, 11, 23, 15),
        now: DateTime(2026, 11, 23, 8),
        completed: false,
        taskId: 1,
      );
      expect(
        parseReminderPayload(planned.single.payload)!.label,
        'Review: PR 5',
      );
    });

    test('invalid payloads return null', () {
      expect(parseReminderPayload(null), isNull);
      expect(parseReminderPayload(''), isNull);
      expect(parseReminderPayload('reminder:5'), isNull);
      expect(parseReminderPayload('habit:notanint'), isNull);
    });
  });

  group('planner payloads carry identity', () {
    test('habit occurrences carry kind/id/dayKey', () {
      final occ = planHabitReminders(
        habitName: 'Run',
        schedule: const HabitSchedule.daily(),
        reminderTime: DateTime(2026, 11, 23, 7),
        now: DateTime(2026, 11, 23, 6),
        checkedDays: const {},
        habitId: 3,
      ).first;
      expect(occ.kind, ReminderKind.habit);
      expect(occ.itemId, 3);
      expect(occ.dayKey, '2026-11-23');
      expect(occ.payload, 'habit:3:2026-11-23:Run');
    });

    test('task occurrences carry kind/id', () {
      final occ = planTaskReminder(
        taskTitle: 'T',
        reminderAt: DateTime(2026, 11, 23, 9),
        now: DateTime(2026, 11, 23, 8),
        completed: false,
        taskId: 9,
      ).single;
      expect(occ.kind, ReminderKind.task);
      expect(occ.itemId, 9);
      expect(occ.payload, 'task:9:T');
    });
  });

  group('refreshDatabaseStreams', () {
    test('re-emits stream data after an out-of-band write', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final habits = HabitRepository(db);
      final id = await habits.create(name: 'Read', color: 1);

      final emitted = <int>[];
      final sub = db
          .select(db.habitCheckins)
          .watch()
          .listen((rows) => emitted.add(rows.length));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emitted.last, 0);

      // Simulate a background-isolate write: a separate connection to the
      // same in-memory DB is not possible, so write via a raw statement that
      // bypasses drift's notification (customStatement does not notify).
      await db.customStatement(
        'INSERT INTO habit_checkins (uuid, updated_at, habit_id, habit_uuid, date) '
        "VALUES ('bg-uuid', 0, $id, 'h-uuid', '2026-11-23')",
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // The stream has NOT re-emitted (drift didn't see the write).
      expect(emitted.last, 0);

      // Resume refresh nudges the streams.
      refreshDatabaseStreams(db);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emitted.last, 1);
      await sub.cancel();
    });
  });

  group('Done action semantics (repository level)', () {
    test('habit Done with target completes the goal', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final habits = HabitRepository(db);
      final id = await habits.create(name: 'Water', color: 1, targetAmount: 8);
      // Mirrors the background handler's Done path.
      final habit = await habits.getById(id);
      await habits.checkIn(id, '2026-11-23', amount: habit?.targetAmount);
      expect((await habits.getCheckins(id)).single.amount, 8);
    });

    test('task Done completes and stamps updatedAt', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final tasks = TaskRepository(db);
      final id = await tasks.create(title: 'T');
      final before = (await tasks.getById(id))!.updatedAt;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await tasks.complete(id);
      final after = (await tasks.getById(id))!;
      expect(after.completedAt, isNotNull);
      expect(after.updatedAt.isAfter(before), isTrue);
    });
  });
}
