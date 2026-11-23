import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Web stub for the notification background handler. Web reminders fire
/// in-tab only (no OS scheduling, no background isolate), so there are no
/// background actions to handle. The real implementation lives in
/// `notification_background_native.dart` (native platforms only) — keeping
/// dart:ffi out of the web compilation.
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) {
  // No-op on web.
}
