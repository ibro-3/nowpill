import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/notifications/notification_action_handler.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/domain/date_utils.dart';

/// Foreground notification actions: tapping Done while the app is open applies
/// through the shared database via the provider-wired callback.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory(), deviceId: 'devA');
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  NotificationResponse response(String action, String payload) =>
      NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        id: 5,
        actionId: action,
        payload: payload,
      );

  test('foreground Done checks in a habit through the shared db', () async {
    final habits = HabitRepository(db);
    final id = await habits.create(name: 'Read', color: 1);
    final service = container.read(notificationServiceProvider);
    expect(service.onActionResponse, isNotNull);

    final day = formatDate(DateTime.now());
    service.onActionResponse!(response(kActionDone, 'habit:$id:$day:Read'));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final rows = await habits.getCheckins(id);
    expect(rows, hasLength(1));
    expect(rows.single.date, day);
  });

  test('foreground Done completes a measurable goal', () async {
    final habits = HabitRepository(db);
    final id = await habits.create(name: 'Water', color: 1, targetAmount: 8);
    final service = container.read(notificationServiceProvider);

    final day = formatDate(DateTime.now());
    service.onActionResponse!(response(kActionDone, 'habit:$id:$day:Water'));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect((await habits.getCheckins(id)).single.amount, 8);
  });

  test('foreground Done completes a task', () async {
    final tasks = TaskRepository(db);
    final id = await tasks.create(title: 'Call dentist');
    final service = container.read(notificationServiceProvider);

    service.onActionResponse!(response(kActionDone, 'task:$id:Call dentist'));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect((await tasks.getById(id))!.completedAt, isNotNull);
  });

  test('plain tap (no action) is a no-op', () async {
    final habits = HabitRepository(db);
    final id = await habits.create(name: 'Read', color: 1);
    final service = container.read(notificationServiceProvider);

    service.onActionResponse!(
      NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        id: 5,
        payload: 'habit:$id::Read',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(await habits.getCheckins(id), isEmpty);
  });
}
