import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/reminder_planner.dart';

/// Android notification channel for habit/task reminders.
const String kReminderChannelId = 'nowpill_reminders';
const String kReminderChannelName = 'Reminders';
const String kReminderChannelDescription =
    'Habit and task reminders scheduled by NowPill.';

/// Platform-agnostic notification scheduling.
///
/// * **Android / iOS / macOS** — OS-level `zonedSchedule` so reminders fire
///   even when the app is closed. Android uses exact alarms when permitted and
///   gracefully falls back to inexact otherwise.
/// * **Linux** — the desktop plugin only supports immediate notifications, so
///   reminders are kept as in-app timers (fire while the app runs) and can be
///   fired immediately for verification.
/// * **Web** — no-op; the UI shows a hint that reminders need the mobile app.
///
/// All methods are safe to call in widget tests: plugin failures are swallowed
/// so a missing platform handler never crashes the UI.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  /// Linux in-app fallback timers, keyed by notification id.
  final Map<int, Timer> _linuxTimers = {};

  /// Whether this platform can schedule OS-level notifications.
  bool get supportsOsScheduling {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  /// Whether reminders are a no-op on this platform (web).
  bool get isNoOp => kIsWeb;

  /// Initializes the plugin and the timezone database. Idempotent.
  Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      _initialized = true;
      return;
    }
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {
        // Fall back to UTC if the platform timezone is unavailable.
        tz.setLocalLocation(tz.UTC);
      }

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const linux = LinuxInitializationSettings(
        defaultActionName: 'Open NowPill',
      );
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: android,
          iOS: ios,
          linux: linux,
        ),
      );

      if (defaultTargetPlatform == TargetPlatform.android) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(
              const AndroidNotificationChannel(
                kReminderChannelId,
                kReminderChannelName,
                description: kReminderChannelDescription,
                importance: Importance.high,
              ),
            );
      }
      _initialized = true;
    } catch (_) {
      // No platform handler (e.g. widget tests): stay uninitialized but never
      // throw. Scheduling calls below are individually guarded.
    }
  }

  /// The Android schedule mode: exact when the OS permits it, inexact
  /// otherwise. Non-Android platforms ignore this value.
  Future<AndroidScheduleMode> _androidScheduleMode() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final canExact = await android?.canScheduleExactNotifications();
      return canExact == true
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
    } catch (_) {
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
  }

  NotificationDetails _details() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        kReminderChannelId,
        kReminderChannelName,
        channelDescription: kReminderChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
      linux: LinuxNotificationDetails(),
    );
  }

  /// Schedules a batch of reminders (replacing any prior ones for the same
  /// ids). On Linux these become in-app timers; on web they are dropped.
  Future<void> scheduleAll(
    Iterable<ReminderOccurrence> occurrences, {
    required int Function(ReminderOccurrence, int) idFor,
  }) async {
    if (kIsWeb) return;
    await initialize();
    final mode = await _androidScheduleMode();
    var slot = 0;
    for (final occ in occurrences) {
      final id = idFor(occ, slot);
      await _scheduleOne(id, occ, mode);
      slot++;
    }
  }

  Future<void> _scheduleOne(
    int id,
    ReminderOccurrence occ,
    AndroidScheduleMode mode,
  ) async {
    try {
      if (supportsOsScheduling) {
        final when = tz.TZDateTime.from(occ.when, tz.local);
        await _plugin.zonedSchedule(
          id: id,
          scheduledDate: when,
          notificationDetails: _details(),
          androidScheduleMode: mode,
          title: 'NowPill reminder',
          body: occ.label,
          payload: 'reminder:$id',
        );
      } else {
        // Linux: in-app timer fallback (fires only while the app runs).
        _linuxTimers[id]?.cancel();
        final delay = occ.when.difference(DateTime.now());
        if (delay.isNegative) return;
        _linuxTimers[id] = Timer(delay, () {
          _linuxTimers.remove(id);
          showNow(id: id, title: 'NowPill reminder', body: occ.label);
        });
      }
    } catch (_) {
      // Guarded: a scheduling failure must not break the UI flow.
    }
  }

  /// Cancels a single reminder by id (OS schedule or Linux timer).
  Future<void> cancel(int id) async {
    _linuxTimers.remove(id)?.cancel();
    if (kIsWeb) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  /// Cancels every pending reminder.
  Future<void> cancelAll() async {
    for (final timer in _linuxTimers.values) {
      timer.cancel();
    }
    _linuxTimers.clear();
    if (kIsWeb) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// Shows a notification immediately (used for the Linux manual-fire test and
  /// the in-app timer fallback). Returns true when the platform accepted it.
  Future<bool> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return false;
    await initialize();
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: _details(),
        payload: 'reminder:$id',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Releases Linux fallback timers. Called when the provider scope closes.
  void dispose() {
    for (final timer in _linuxTimers.values) {
      timer.cancel();
    }
    _linuxTimers.clear();
  }
}
