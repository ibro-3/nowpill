import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/date_utils.dart';
import '../db/app_database.dart';
import '../db/connection_native.dart';
import '../repositories/habit_repository.dart';
import '../repositories/task_repository.dart';
import '../sync/device_identity.dart';
import 'notification_service.dart'
    show kReminderChannelId, kReminderChannelName, kReminderChannelDescription;

/// Android notification action ids.
const String kActionDone = 'done';
const String kActionSnooze10 = 'snooze10';
const String kActionSnooze60 = 'snooze60';

/// Parses a reminder payload (`habit:<id>:<dayKey>:<label>` / `task:<id>:<label>`).
({String kind, int id, String? dayKey, String label})? parseReminderPayload(
  String? payload,
) {
  if (payload == null || payload.isEmpty) return null;
  final parts = payload.split(':');
  if (parts.length < 2) return null;
  final id = int.tryParse(parts[1]);
  if (id == null) return null;
  if (parts[0] == 'habit') {
    return (
      kind: 'habit',
      id: id,
      dayKey: parts.length > 2 ? parts[2] : null,
      label: parts.length > 3 ? parts.sublist(3).join(':') : '',
    );
  }
  if (parts[0] == 'task') {
    return (
      kind: 'task',
      id: id,
      dayKey: null,
      label: parts.length > 2 ? parts.sublist(2).join(':') : '',
    );
  }
  return null;
}

/// Applies the Done action through the repositories (so `updatedAt` is stamped
/// and sync picks it up). Shared by the background isolate (own connection)
/// and the foreground handler (the app's shared connection). Guarded: a
/// failed action must never crash the caller.
Future<void> applyDoneAction(
  AppDatabase db,
  ({String kind, int id, String? dayKey, String label}) parsed,
) async {
  try {
    if (parsed.kind == 'habit') {
      final dayKey = parsed.dayKey?.isNotEmpty == true
          ? parsed.dayKey!
          : formatDate(DateTime.now());
      final habits = HabitRepository(db);
      final habit = await habits.getById(parsed.id);
      // Measurable habits: Done completes the whole goal.
      await habits.checkIn(parsed.id, dayKey, amount: habit?.targetAmount);
    } else {
      await TaskRepository(db).complete(parsed.id);
    }
  } catch (_) {
    // Guarded.
  }
}

/// Handles Done / Snooze actions tapped on a reminder while the app is closed
/// (Android background isolate). Opens the same database file the app uses,
/// applies the action, then closes it.
///
/// Must be a top-level function annotated `vm:entry-point` so the AOT compiler
/// keeps it. Registered via `onDidReceiveBackgroundNotificationResponse`.
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) {
  // The background isolate has no Riverpod scope; run async work detached.
  _handle(response);
}

Future<void> _handle(NotificationResponse response) async {
  final parsed = parseReminderPayload(response.payload);
  if (parsed == null) return;
  final action = response.actionId;
  if (action == null || action.isEmpty) return; // plain tap → app opens

  final minutes = action == kActionSnooze10
      ? 10
      : action == kActionSnooze60
      ? 60
      : null;
  if (minutes != null) {
    await _snooze(response, parsed.label, minutes);
    return;
  }
  if (action != kActionDone) return;

  AppDatabase? db;
  try {
    final path = await resolveDatabasePath();
    db = AppDatabase.withExecutor(
      NativeDatabase(File(path)),
      deviceId: await loadOrCreateDeviceId(),
    );
    await applyDoneAction(db, parsed);
  } catch (_) {
    // Guarded: a failed action must never crash the background isolate.
  } finally {
    await db?.close();
  }
}

/// Re-schedules the same reminder [minutes] from now under a snooze id (above
/// the normal reminder ranges). Uses inexact scheduling so no exact-alarm
/// permission is needed for a snooze.
Future<void> _snooze(
  NotificationResponse response,
  String label,
  int minutes,
) async {
  try {
    tzdata.initializeTimeZones();
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final snoozeId = 2000000 + (response.id ?? 0);
    final when = tz.TZDateTime.from(
      DateTime.now().add(Duration(minutes: minutes)),
      tz.UTC,
    );
    await plugin.zonedSchedule(
      id: snoozeId,
      scheduledDate: when,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          kReminderChannelId,
          kReminderChannelName,
          channelDescription: kReminderChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: 'NowPill reminder',
      body: label,
      payload: response.payload,
    );
  } catch (_) {
    // Guarded: snooze failure must not crash the isolate.
  }
}
