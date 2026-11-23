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
/// Phase 8 only surfaces status + a request action in Settings; the full
/// scheduling service (channels, exact alarms, boot receiver) lands in Phase 9.
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
}
