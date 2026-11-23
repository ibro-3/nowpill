import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The user's notification permission state, for the Settings status row.
enum NotificationPermissionStatus {
  /// The OS granted notification permission.
  granted,

  /// The OS denied (or has not yet granted) notification permission.
  denied,

  /// This platform has no runtime notification permission (Linux, web).
  notRequired,

  /// The state could not be determined (e.g. plugin unavailable in tests).
  unknown,
}

/// Thin abstraction over the platform notification permission APIs.
///
/// Covers POST_NOTIFICATIONS / iOS alert permission plus the Android 12+
/// exact-alarm special access (with a settings-intent request). The scheduling
/// service (channels, zonedSchedule, boot receiver) lives in
/// `NotificationService`.
class NotificationPermissionService {
  NotificationPermissionService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Whether this platform gates notifications behind a runtime permission.
  bool get requiresRuntimePermission {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  /// Reads the current permission status. Never throws — plugin failures
  /// (e.g. no platform handler in widget tests) resolve to
  /// [NotificationPermissionStatus.unknown].
  Future<NotificationPermissionStatus> status() async {
    if (!requiresRuntimePermission) {
      return NotificationPermissionStatus.notRequired;
    }
    try {
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final enabled = await android?.areNotificationsEnabled();
        return enabled == true
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
      }
      if (Platform.isIOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        final result = await ios?.checkPermissions();
        return result?.isEnabled == true
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
      }
      return NotificationPermissionStatus.unknown;
    } catch (_) {
      return NotificationPermissionStatus.unknown;
    }
  }

  /// Requests notification permission (Android 13+ POST_NOTIFICATIONS, iOS
  /// alert/sound/badge). Returns the resulting status.
  Future<NotificationPermissionStatus> request() async {
    if (!requiresRuntimePermission) {
      return NotificationPermissionStatus.notRequired;
    }
    try {
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final granted = await android?.requestNotificationsPermission();
        return granted == true
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
      }
      if (Platform.isIOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        final granted = await ios?.requestPermissions(
          alert: true,
          sound: true,
          badge: true,
        );
        return granted == true
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
      }
      return NotificationPermissionStatus.unknown;
    } catch (_) {
      return NotificationPermissionStatus.unknown;
    }
  }

  /// Whether Android currently allows exact alarms (Android 12+ special
  /// access). Always false on other platforms and when the plugin is
  /// unavailable; callers gate the UI on the platform separately.
  Future<bool> canScheduleExactAlarms() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.canScheduleExactNotifications() == true;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system "Alarms & reminders" settings screen so the user can
  /// grant exact-alarm access (Android 12+). Returns whether access is
  /// granted after the user returns. False on other platforms / on failure.
  Future<bool> requestExactAlarmsPermission() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestExactAlarmsPermission();
      return await canScheduleExactAlarms();
    } catch (_) {
      return false;
    }
  }
}
