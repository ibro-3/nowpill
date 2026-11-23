import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../db/app_database.dart';
import '../export/backup_service.dart';
import '../export/export_service.dart';
import '../notifications/notification_permission_service.dart';
import '../notifications/notification_service.dart';
import '../notifications/reminder_coordinator.dart';
import '../sync/device_identity.dart';
import '../widget/widget_bridge_service.dart';
import '../widget/widget_snapshot_controller.dart';
import 'habit_repository.dart';
import 'tag_repository.dart';
import 'task_repository.dart';

part 'providers.g.dart';

/// The single shared [AppDatabase] instance for the app.
///
/// Disposed when the provider scope closes. Tests override this with an
/// in-memory database.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase(deviceId: bootDeviceId);
  ref.onDispose(db.close);
  return db;
}

@Riverpod(keepAlive: true)
TaskRepository taskRepository(Ref ref) {
  return TaskRepository(ref.watch(appDatabaseProvider));
}

@Riverpod(keepAlive: true)
HabitRepository habitRepository(Ref ref) {
  return HabitRepository(ref.watch(appDatabaseProvider));
}

@Riverpod(keepAlive: true)
TagRepository tagRepository(Ref ref) {
  return TagRepository(ref.watch(appDatabaseProvider));
}

@Riverpod(keepAlive: true)
ExportService exportService(Ref ref) {
  return ExportService(ref.watch(appDatabaseProvider));
}

@Riverpod(keepAlive: true)
NotificationPermissionService notificationPermissionService(Ref ref) {
  return NotificationPermissionService();
}

@Riverpod(keepAlive: true)
BackupService backupService(Ref ref) {
  return BackupService(ref.watch(exportServiceProvider));
}

@Riverpod(keepAlive: true)
NotificationService notificationService(Ref ref) {
  final service = NotificationService();
  ref.onDispose(service.dispose);
  return service;
}

/// The reactive reminder scheduler. Watching this provider (e.g. from the app
/// shell) starts it; it reschedules on every habit/check-in/task change.
@Riverpod(keepAlive: true)
ReminderCoordinator reminderCoordinator(Ref ref) {
  final coordinator = ReminderCoordinator(
    habits: ref.watch(habitRepositoryProvider),
    tasks: ref.watch(taskRepositoryProvider),
    notifications: ref.watch(notificationServiceProvider),
  );
  ref.onDispose(coordinator.dispose);
  coordinator.start();
  return coordinator;
}

@Riverpod(keepAlive: true)
WidgetBridgeService widgetBridgeService(Ref ref) {
  return WidgetBridgeService();
}

/// The reactive home-screen widget updater. Watching this provider (e.g. from
/// the app shell) starts it; it pushes a fresh snapshot on every data change.
@Riverpod(keepAlive: true)
WidgetSnapshotController widgetSnapshotController(Ref ref) {
  final controller = WidgetSnapshotController(
    habits: ref.watch(habitRepositoryProvider),
    tasks: ref.watch(taskRepositoryProvider),
    bridge: ref.watch(widgetBridgeServiceProvider),
  );
  ref.onDispose(controller.dispose);
  controller.start();
  return controller;
}
