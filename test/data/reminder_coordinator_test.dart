import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/notifications/notification_service.dart';
import 'package:nowpill/data/notifications/reminder_coordinator.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/domain/reminder_planner.dart';

import 'test_database.dart';

/// Records scheduling calls instead of touching a platform plugin.
class RecordingNotificationService extends NotificationService {
  RecordingNotificationService() : super();

  final List<(int id, DateTime when, String label)> scheduled = [];
  int cancelAllCalls = 0;
  bool noOp = false;

  @override
  bool get isNoOp => noOp;

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    scheduled.clear();
  }

  @override
  Future<void> scheduleAll(
    Iterable<ReminderOccurrence> occurrences, {
    required int Function(ReminderOccurrence, int) idFor,
  }) async {
    var slot = 0;
    for (final occ in occurrences) {
      scheduled.add((idFor(occ, slot), occ.when, occ.label));
      slot++;
    }
  }
}

void main() {
  late AppDatabase db;
  late RecordingNotificationService notifications;
  late ReminderCoordinator coordinator;

  // Fixed "now" so planned occurrences are deterministic: Mon 2026-11-23 08:00.
  final now = DateTime(2026, 11, 23, 8);

  setUp(() {
    db = createTestDatabase();
    notifications = RecordingNotificationService();
    coordinator = ReminderCoordinator(
      habits: HabitRepository(db),
      tasks: TaskRepository(db),
      notifications: notifications,
      clock: () => now,
    );
  });

  tearDown(() async {
    await coordinator.dispose();
    await db.close();
  });

  test('schedules habit reminders at the reminder time', () async {
    final habits = HabitRepository(db);
    await habits.create(
      name: 'Meditate',
      color: 0xFF2DD4A8,
      reminderTime: DateTime(2026, 11, 23, 9),
    );

    await coordinator.rescheduleAll();

    expect(notifications.scheduled, hasLength(kHabitReminderHorizon));
    expect(notifications.scheduled.first.$3, 'Meditate');
    expect(notifications.scheduled.first.$2, DateTime(2026, 11, 23, 9));
    expect(notifications.scheduled.first.$1, habitReminderId(1, 0));
  });

  test('skips habits without a reminder and archived habits', () async {
    final habits = HabitRepository(db);
    await habits.create(name: 'NoReminder', color: 0xFF2DD4A8);
    final archived = await habits.create(
      name: 'Archived',
      color: 0xFF2DD4A8,
      reminderTime: DateTime(2026, 11, 23, 9),
    );
    await habits.archive(archived);

    await coordinator.rescheduleAll();
    expect(notifications.scheduled, isEmpty);
  });

  test('checked-in today is skipped', () async {
    final habits = HabitRepository(db);
    final id = await habits.create(
      name: 'Meditate',
      color: 0xFF2DD4A8,
      reminderTime: DateTime(2026, 11, 23, 9),
    );
    await habits.checkIn(id, formatDate(now));

    await coordinator.rescheduleAll();
    // Today is done, so the first scheduled occurrence is tomorrow.
    expect(notifications.scheduled.first.$2, DateTime(2026, 11, 24, 9));
  });

  test('schedules a future task reminder, skips completed', () async {
    final tasks = TaskRepository(db);
    final open = await tasks.create(
      title: 'Pay rent',
      reminderAt: DateTime(2026, 11, 24, 9),
    );
    final done = await tasks.create(
      title: 'Done task',
      reminderAt: DateTime(2026, 11, 24, 9),
    );
    await tasks.complete(done);

    await coordinator.rescheduleAll();
    expect(notifications.scheduled, hasLength(1));
    expect(notifications.scheduled.single.$3, 'Pay rent');
    expect(notifications.scheduled.single.$1, taskReminderId(open));
  });

  test('reschedule clears prior notifications first', () async {
    final habits = HabitRepository(db);
    await habits.create(
      name: 'Meditate',
      color: 0xFF2DD4A8,
      reminderTime: DateTime(2026, 11, 23, 9),
    );
    await coordinator.rescheduleAll();
    await coordinator.rescheduleAll();
    expect(notifications.cancelAllCalls, 2);
    expect(notifications.scheduled, hasLength(kHabitReminderHorizon));
  });

  test('web no-op schedules nothing', () async {
    notifications.noOp = true;
    final habits = HabitRepository(db);
    await habits.create(
      name: 'Meditate',
      color: 0xFF2DD4A8,
      reminderTime: DateTime(2026, 11, 23, 9),
    );
    await coordinator.rescheduleAll();
    expect(notifications.scheduled, isEmpty);
    expect(notifications.cancelAllCalls, 0);
  });
}
