import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../backup/auto_backup_service.dart';
import '../db/app_database.dart';
import '../export/backup_service.dart';
import '../export/export_service.dart';
import '../notifications/notification_action_handler.dart';
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

/// Rotating daily local backups (Phase 20). The directory resolves lazily so
/// tests can override the provider with a temp-dir instance.
@Riverpod(keepAlive: true)
Future<AutoBackupService> autoBackupService(Ref ref) async {
  final docs = await getApplicationDocumentsDirectory();
  return AutoBackupService(
    export: ref.watch(exportServiceProvider),
    directoryPath: p.join(docs.path, 'nowpill-backups'),
  );
}

@Riverpod(keepAlive: true)
NotificationService notificationService(Ref ref) {
  final service = NotificationService();
  final db = ref.watch(appDatabaseProvider);
  // Foreground action taps (app open) apply through the shared database —
  // the background handler only runs while the app is closed.
  service.onActionResponse = (response) async {
    final parsed = parseReminderPayload(response.payload);
    if (parsed == null) return;
    final action = response.actionId;
    if (action == kActionDone) {
      await applyDoneAction(db, parsed);
      // Surface the write to the reactive UI immediately.
      refreshDatabaseStreams(db);
      return;
    }
    final minutes = action == kActionSnooze10
        ? 10
        : action == kActionSnooze60
        ? 60
        : null;
    if (minutes == null) return;
    try {
      await service.snooze(
        id: 2000000 + (response.id ?? 0),
        when: DateTime.now().add(Duration(minutes: minutes)),
        label: parsed.label,
        payload: response.payload ?? '',
      );
    } catch (_) {
      // Guarded: snooze failure must not break the app.
    }
  };
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
