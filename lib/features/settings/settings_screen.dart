import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/app_settings_provider.dart';
import '../../data/export/backup_service.dart';
import '../../data/export/export_service.dart';
import '../../data/notifications/notification_permission_service.dart';
import '../../data/repositories/providers.dart';
import '../../data/sync/device_identity.dart';
import '../../data/sync/sync_coordinator.dart';
import '../../data/sync/sync_folder.dart';
import '../../data/sync/sync_providers.dart';
import '../../l10n/generated/app_localizations.dart';

/// App preferences: appearance, motion, reminders, notifications, data
/// backup/restore, and about.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;
  NotificationPermissionStatus? _permission;
  bool? _canExact;

  @override
  void initState() {
    super.initState();
    _loadPermission();
    _loadExactAlarmStatus();
  }

  Future<void> _loadPermission() async {
    final status = await ref
        .read(notificationPermissionServiceProvider)
        .status();
    if (mounted) setState(() => _permission = status);
  }

  Future<void> _loadExactAlarmStatus() async {
    final can = await ref
        .read(notificationPermissionServiceProvider)
        .canScheduleExactAlarms();
    if (mounted) setState(() => _canExact = can);
  }

  /// iOS priming: explain why reminders need notification access before
  /// triggering the one-shot system prompt (denials are hard to recover from
  /// on iOS). Returns true when the user opted in.
  Future<bool> _showIosPriming() async {
    final l10n = AppLocalizations.of(context);
    final agreed = await M3EDialog.show<bool>(
      context,
      dialog: M3EDialog(
        title: l10n.iosPrimingTitle,
        content: Text(l10n.iosPrimingBody),
        actions: [
          M3EButton(
            key: const ValueKey('ios-priming-cancel'),
            style: M3EButtonStyle.text,
            onPressed: () => Navigator.of(context).pop(false),
            label: Text(l10n.notNow),
          ),
          M3EButton(
            key: const ValueKey('ios-priming-continue'),
            onPressed: () => Navigator.of(context).pop(true),
            label: Text(l10n.continueLabel),
          ),
        ],
      ),
    );
    return agreed == true;
  }

  Future<void> _requestPermission() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      if (!await _showIosPriming()) return;
      if (!mounted) return;
    }
    final status = await ref
        .read(notificationPermissionServiceProvider)
        .request();
    if (mounted) setState(() => _permission = status);
  }

  /// Android 12+ exact-alarm special access: opens the system settings
  /// screen, then refreshes status when the user returns.
  Future<void> _requestExactAlarms() async {
    final granted = await ref
        .read(notificationPermissionServiceProvider)
        .requestExactAlarmsPermission();
    if (mounted) setState(() => _canExact = granted);
    await ref.read(reminderCoordinatorProvider).rescheduleAll();
  }

  Future<void> _sendTestNotification() async {
    final service = ref.read(notificationServiceProvider);
    final l10n = AppLocalizations.of(context);
    if (!service.webSupported) {
      M3ESnackbar.show(context, message: l10n.browserUnsupported);
      return;
    }
    // On web the notification only shows once permission is granted; request
    // it here (this runs from a tap, satisfying the user-gesture requirement).
    if (kIsWeb && _permission != NotificationPermissionStatus.granted) {
      await _requestPermission();
      if (!mounted) return;
      if (_permission != NotificationPermissionStatus.granted) {
        M3ESnackbar.show(context, message: l10n.notificationsBlocked);
        return;
      }
    }
    final ok = await service.showNow(
      id: 0,
      title: l10n.appName,
      body: l10n.testReminderBody,
    );
    if (!mounted) return;
    M3ESnackbar.show(
      context,
      message: ok ? l10n.testNotificationSent : l10n.testNotificationFailed,
    );
  }

  Future<void> _pickDefaultReminder() async {
    final settings = ref.read(currentSettingsProvider);
    final minutes = settings.defaultReminderMinutes;
    final picked = await M3ETimePicker.show(
      context,
      initialTime: M3ETime(
        hour: minutes == null ? 9 : minutes ~/ 60,
        minute: minutes == null ? 0 : minutes % 60,
      ),
    );
    if (picked == null) return;
    ref
        .read(appSettingsProvider.notifier)
        .setDefaultReminderMinutes(picked.hour * 60 + picked.minute);
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    final outcome = await ref.read(backupServiceProvider).exportToFile();
    if (!mounted) return;
    setState(() => _busy = false);
    final l10n = AppLocalizations.of(context);
    final message = switch (outcome) {
      ExportOutcome.shared => l10n.backupExported,
      ExportOutcome.cancelled => l10n.exportCancelled,
      ExportOutcome.failed => l10n.exportFailed,
    };
    M3ESnackbar.show(context, message: message);
  }

  /// Opens the platform folder picker and persists the chosen sync folder.
  Future<void> _chooseSyncFolder() async {
    final l10n = AppLocalizations.of(context);
    try {
      final folder = await pickSyncFolder();
      if (folder == null || !mounted) return;
      if (!await folder.isAccessible()) {
        if (mounted) {
          M3ESnackbar.show(context, message: l10n.syncFolderFailed);
        }
        return;
      }
      ref.read(appSettingsProvider.notifier).setSyncFolderHandle(folder.handle);
      if (mounted) {
        M3ESnackbar.show(context, message: l10n.syncFolderSet);
      }
    } catch (_) {
      if (mounted) {
        M3ESnackbar.show(context, message: l10n.syncFolderFailed);
      }
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    final backup = ref.read(backupServiceProvider);
    try {
      final json = await backup.pickBackupFile();
      if (json == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final ExportEnvelope envelope;
      try {
        envelope = backup.validate(json);
      } on ImportFormatException catch (e) {
        if (mounted) {
          setState(() => _busy = false);
          M3ESnackbar.show(
            context,
            message: AppLocalizations.of(context).invalidBackup(e.message),
          );
        }
        return;
      }
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final confirmed = await M3EDialog.show<bool>(
        context,
        dialog: M3EDialog(
          title: l10n.replaceDataTitle,
          content: Text(
            l10n.replaceDataBody(
              envelope.habits.length,
              envelope.checkins.length,
              envelope.tasks.length,
            ),
          ),
          actions: [
            M3EButton(
              key: const ValueKey('import-cancel'),
              style: M3EButtonStyle.text,
              onPressed: () => Navigator.of(context).pop(false),
              label: Text(l10n.cancel),
            ),
            M3EButton(
              key: const ValueKey('import-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              label: Text(l10n.replace),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await backup.restore(json);
      if (!mounted) return;
      setState(() => _busy = false);
      M3ESnackbar.show(
        context,
        message: AppLocalizations.of(context).backupRestored,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        M3ESnackbar.show(
          context,
          message: AppLocalizations.of(context).importFailed,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: M3EAppBar.top(
        titleText: l10n.settings,
        leading: M3EIconButton(
          variant: M3EIconButtonVariant.standard,
          icon: const Icon(M3EIcons.arrow_back),
          tooltip: l10n.back,
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.today);
            }
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          _SectionHeader(title: l10n.settingsAppearance, theme: theme),
          const SizedBox(height: 8),
          _SettingsCard(
            theme: theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsTheme,
                  style: theme.typography.baseline.titleMedium,
                ),
                const SizedBox(height: 12),
                M3ESegmentedButton<AppThemeMode>(
                  selected: {settings.themeMode},
                  onSelectionChanged: (selection) {
                    if (selection.isNotEmpty) {
                      notifier.setThemeMode(selection.first);
                    }
                  },
                  segments: [
                    M3ESegment(
                      value: AppThemeMode.system,
                      label: l10n.themeSystem,
                      icon: const Icon(M3EIcons.brightness_auto),
                    ),
                    M3ESegment(
                      value: AppThemeMode.light,
                      label: l10n.themeLight,
                      icon: const Icon(M3EIcons.light_mode),
                    ),
                    M3ESegment(
                      value: AppThemeMode.dark,
                      label: l10n.themeDark,
                      icon: const Icon(M3EIcons.dark_mode),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SwitchRow(
                  theme: theme,
                  title: l10n.dynamicColor,
                  subtitle: l10n.dynamicColorDesc,
                  value: settings.dynamicColor,
                  onChanged: notifier.setDynamicColor,
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.settingsLanguage,
                  style: theme.typography.baseline.titleMedium,
                ),
                const SizedBox(height: 12),
                M3ESegmentedButton<String>(
                  selected: {settings.localeCode ?? 'system'},
                  onSelectionChanged: (selection) {
                    if (selection.isNotEmpty) {
                      final code = selection.first;
                      notifier.setLocaleCode(code == 'system' ? null : code);
                    }
                  },
                  segments: [
                    M3ESegment(value: 'system', label: l10n.languageSystem),
                    M3ESegment(value: 'en', label: l10n.languageEnglish),
                    M3ESegment(value: 'es', label: l10n.languageSpanish),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: l10n.settingsMotion, theme: theme),
          const SizedBox(height: 8),
          _SettingsCard(
            theme: theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.animationStyle,
                  style: theme.typography.baseline.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.motionDesc,
                  style: theme.typography.baseline.bodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                M3ESegmentedButton<AppMotionMode>(
                  selected: {settings.motionMode},
                  onSelectionChanged: (selection) {
                    if (selection.isNotEmpty) {
                      notifier.setMotionMode(selection.first);
                    }
                  },
                  segments: [
                    M3ESegment(
                      value: AppMotionMode.expressive,
                      label: l10n.motionExpressive,
                      icon: const Icon(M3EIcons.animation),
                    ),
                    M3ESegment(
                      value: AppMotionMode.standard,
                      label: l10n.motionStandard,
                      icon: const Icon(M3EIcons.motion_photos_auto),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: l10n.settingsRemindersWeek, theme: theme),
          const SizedBox(height: 8),
          _SettingsCard(
            theme: theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.defaultReminderTime,
                  style: theme.typography.baseline.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.defaultReminderDesc,
                  style: theme.typography.baseline.bodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: M3EButton.icon(
                        onPressed: _pickDefaultReminder,
                        style: M3EButtonStyle.tonal,
                        icon: const Icon(M3EIcons.notifications),
                        label: Text(
                          settings.defaultReminderMinutes == null
                              ? l10n.setDefaultValue
                              : _formatMinutes(
                                  settings.defaultReminderMinutes!,
                                ),
                        ),
                      ),
                    ),
                    if (settings.defaultReminderMinutes != null) ...[
                      const SizedBox(width: 8),
                      M3EIconButton(
                        variant: M3EIconButtonVariant.standard,
                        icon: const Icon(M3EIcons.close),
                        tooltip: l10n.clearDefaultReminder,
                        onPressed: () =>
                            notifier.setDefaultReminderMinutes(null),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                _SwitchRow(
                  theme: theme,
                  title: l10n.weekStartsMonday,
                  subtitle: l10n.weekStartDesc,
                  value: settings.weekStartsOnMonday,
                  onChanged: notifier.setWeekStartsOnMonday,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: l10n.settingsNotifications, theme: theme),
          const SizedBox(height: 8),
          _SettingsCard(
            theme: theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NotificationStatusRow(
                  theme: theme,
                  status: _permission,
                  onRequest: _requestPermission,
                ),
                if (!kIsWeb &&
                    defaultTargetPlatform == TargetPlatform.android &&
                    _canExact != null) ...[
                  const SizedBox(height: 12),
                  _ExactAlarmRow(
                    theme: theme,
                    canExact: _canExact!,
                    onRequest: _requestExactAlarms,
                  ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: M3EButton.icon(
                    onPressed: _sendTestNotification,
                    style: M3EButtonStyle.tonal,
                    icon: const Icon(M3EIcons.notifications_active),
                    label: Text(l10n.sendTestNotification),
                  ),
                ),
                if (kIsWeb) ...[
                  const SizedBox(height: 12),
                  Text(
                    l10n.webReminderNote,
                    style: theme.typography.baseline.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: l10n.settingsData, theme: theme),
          const SizedBox(height: 8),
          _SettingsCard(
            theme: theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.backupRestore,
                  style: theme.typography.baseline.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.backupDesc,
                  style: theme.typography.baseline.bodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: M3EButton.icon(
                        onPressed: _busy ? null : _export,
                        style: M3EButtonStyle.tonal,
                        icon: const Icon(M3EIcons.upload),
                        label: Text(l10n.export),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: M3EButton.icon(
                        onPressed: _busy ? null : _import,
                        style: M3EButtonStyle.outlined,
                        icon: const Icon(M3EIcons.download),
                        label: Text(l10n.import),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: l10n.settingsSync, theme: theme),
          const SizedBox(height: 8),
          _SyncCard(
            theme: theme,
            settings: settings,
            onChooseFolder: _chooseSyncFolder,
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: l10n.settingsAbout, theme: theme),
          const SizedBox(height: 8),
          _SettingsCard(
            theme: theme,
            child: Row(
              children: [
                M3EShapeContainer(
                  kind: M3EShapeKind.cookie9Sided,
                  width: 48,
                  height: 48,
                  color: theme.colorScheme.primaryContainer,
                  child: Icon(
                    M3EIcons.medication,
                    size: 24,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.appName,
                        style: theme.typography.emphasized.titleMedium,
                      ),
                      Text(
                        l10n.aboutVersion('0.2.0'),
                        style: theme.typography.baseline.bodySmall.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _formatMinutes(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _NotificationStatusRow extends StatelessWidget {
  const _NotificationStatusRow({
    required this.theme,
    required this.status,
    required this.onRequest,
  });

  final M3EThemeData theme;
  final NotificationPermissionStatus? status;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final (label, color, showRequest) = switch (status) {
      NotificationPermissionStatus.granted => (
        l10n.notifEnabled,
        scheme.primary,
        false,
      ),
      NotificationPermissionStatus.denied => (
        l10n.notifDisabled,
        scheme.error,
        true,
      ),
      NotificationPermissionStatus.notRequired => (
        l10n.notifNotRequired,
        scheme.onSurfaceVariant,
        false,
      ),
      _ => (l10n.notifChecking, scheme.onSurfaceVariant, false),
    };

    return Row(
      children: [
        Icon(M3EIcons.notifications_active, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: theme.typography.baseline.bodyMedium.copyWith(
              color: scheme.onSurface,
            ),
          ),
        ),
        if (showRequest) ...[
          const SizedBox(width: 12),
          M3EButton(
            style: M3EButtonStyle.tonal,
            onPressed: onRequest,
            label: Text(l10n.enable),
          ),
        ],
      ],
    );
  }
}

/// Android 12+ exact-alarm special access status. When not granted, reminders
/// still fire but the OS may batch/delay them; the action opens the system
/// "Alarms & reminders" settings screen.
class _ExactAlarmRow extends StatelessWidget {
  const _ExactAlarmRow({
    required this.theme,
    required this.canExact,
    required this.onRequest,
  });

  final M3EThemeData theme;
  final bool canExact;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Icon(
          M3EIcons.access_alarm,
          size: 20,
          color: canExact ? scheme.primary : scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            canExact ? l10n.exactAlarmsOn : l10n.exactAlarmsOff,
            style: theme.typography.baseline.bodyMedium.copyWith(
              color: scheme.onSurface,
            ),
          ),
        ),
        if (!canExact) ...[
          const SizedBox(width: 12),
          M3EButton(
            style: M3EButtonStyle.tonal,
            onPressed: onRequest,
            label: Text(l10n.allow),
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.theme});

  final String title;
  final M3EThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: theme.typography.emphasized.titleMedium.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Folder-sync controls: enable toggle, folder picker, live status, manual
/// sync, and this device's identity. Web shows a hint (folder sync deferred).
class _SyncCard extends ConsumerWidget {
  const _SyncCard({
    required this.theme,
    required this.settings,
    required this.onChooseFolder,
  });

  final M3EThemeData theme;
  final AppSettings settings;
  final Future<void> Function() onChooseFolder;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  String _statusText(AppLocalizations l10n, SyncState state) {
    if (!settings.syncEnabled || settings.syncFolderHandle == null) {
      return l10n.syncStatusIdle;
    }
    return switch (state.status) {
      SyncStatus.idle => l10n.syncStatusIdle,
      SyncStatus.syncing => l10n.syncStatusSyncing,
      SyncStatus.ok => l10n.syncStatusOk(_formatTime(state.lastSyncAt)),
      SyncStatus.folderUnavailable => l10n.syncStatusUnavailable,
      SyncStatus.failed => l10n.syncStatusFailed(state.lastError ?? '?'),
    };
  }

  String _formatTime(DateTime? at) {
    if (at == null) return '—';
    final local = at.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(syncStateProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final folderLabel = settings.syncFolderHandle == null
        ? l10n.syncNoFolder
        : (syncFolderFromHandle(settings.syncFolderHandle!)?.displayName ??
              settings.syncFolderHandle!);

    return _SettingsCard(
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.syncTitle, style: theme.typography.baseline.titleMedium),
          const SizedBox(height: 4),
          Text(
            l10n.syncDesc,
            style: theme.typography.baseline.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (!_supported)
            Text(
              l10n.syncUnsupported,
              style: theme.typography.baseline.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else ...[
            _SwitchRow(
              theme: theme,
              title: l10n.syncEnable,
              subtitle: folderLabel,
              value: settings.syncEnabled && settings.syncFolderHandle != null,
              onChanged: (on) {
                if (on && settings.syncFolderHandle == null) {
                  // Enabling without a folder goes straight to the picker.
                  onChooseFolder().then((_) {
                    final handle = ref
                        .read(appSettingsProvider)
                        .value
                        ?.syncFolderHandle;
                    if (handle != null) notifier.setSyncEnabled(true);
                  });
                } else {
                  notifier.setSyncEnabled(on);
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: M3EButton.icon(
                    onPressed: onChooseFolder,
                    style: M3EButtonStyle.outlined,
                    icon: const Icon(M3EIcons.folder),
                    label: Text(
                      settings.syncFolderHandle == null
                          ? l10n.syncChooseFolder
                          : l10n.syncChangeFolder,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: M3EButton.icon(
                    onPressed:
                        settings.syncEnabled &&
                            settings.syncFolderHandle != null
                        ? () => ref.read(syncCoordinatorProvider).syncNow()
                        : null,
                    style: M3EButtonStyle.tonal,
                    icon: const Icon(M3EIcons.sync),
                    label: Text(l10n.syncNow),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _statusText(l10n, state),
              key: const ValueKey('sync-status'),
              style: theme.typography.baseline.bodySmall.copyWith(
                color:
                    state.status == SyncStatus.failed ||
                        state.status == SyncStatus.folderUnavailable
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.syncDeviceId(bootDeviceId),
              style: theme.typography.baseline.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.theme, required this.child});

  final M3EThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return M3ECard(
      variant: M3ECardVariant.filled,
      padding: const EdgeInsets.all(20),
      child: child,
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.theme,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final M3EThemeData theme;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.typography.baseline.titleMedium),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.typography.baseline.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        M3ESwitch(value: value, onChanged: onChanged),
      ],
    );
  }
}
