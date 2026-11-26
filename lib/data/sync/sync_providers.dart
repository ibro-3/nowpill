import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/settings/app_settings.dart';
import '../../core/settings/app_settings_provider.dart';
import '../repositories/providers.dart';
import 'device_identity.dart';
import 'sync_coordinator.dart';
import 'sync_folder.dart';

part 'sync_providers.g.dart';

/// Live sync status for the Settings UI. Updated by the coordinator.
@Riverpod(keepAlive: true)
class SyncStateNotifier extends _$SyncStateNotifier {
  @override
  SyncState build() => const SyncState();

  void set(SyncState state) => this.state = state;
}

/// The reactive file-sync coordinator. Watching this provider (from the app
/// shell) activates it; it stays idle until the user enables sync and picks a
/// folder. Data changes and a periodic poll drive sync cycles.
@Riverpod(keepAlive: true)
SyncCoordinator syncCoordinator(Ref ref) {
  final coordinator = SyncCoordinator(
    export: ref.watch(exportServiceProvider),
    deviceId: bootDeviceId,
    onStateChanged: (s) {
      // Guard against updates after the scope closes (tests tear down fast).
      try {
        ref.read(syncStateProvider.notifier).set(s);
      } catch (_) {}
    },
  );

  // Apply the persisted sync configuration now and on every change.
  ref.listen<AsyncValue<AppSettings>>(appSettingsProvider, (prev, next) {
    final settings = next.value;
    if (settings == null) return;
    final folder = settings.syncEnabled && settings.syncFolderHandle != null
        ? syncFolderFromHandle(settings.syncFolderHandle!)
        : null;
    coordinator.setFolder(folder);
  }, fireImmediately: true);

  // Any data change schedules a (debounced) sync cycle.
  final habits = ref.watch(habitRepositoryProvider);
  final tasks = ref.watch(taskRepositoryProvider);
  final lists = ref.watch(taskListRepositoryProvider);
  final chat = ref.watch(chatRepositoryProvider);
  final subs = [
    habits.watchAll().listen((_) => coordinator.scheduleSync()),
    habits.watchAllCheckins().listen((_) => coordinator.scheduleSync()),
    habits.watchVacationPeriods().listen((_) => coordinator.scheduleSync()),
    habits.watchAllRelapses().listen((_) => coordinator.scheduleSync()),
    tasks.watchAll().listen((_) => coordinator.scheduleSync()),
    tasks.watchAllTaskTags().listen((_) => coordinator.scheduleSync()),
    lists.watchAll().listen((_) => coordinator.scheduleSync()),
    chat.watchAll().listen((_) => coordinator.scheduleSync()),
  ];

  ref.onDispose(() async {
    for (final sub in subs) {
      await sub.cancel();
    }
    await coordinator.dispose();
  });

  coordinator.start();
  return coordinator;
}
