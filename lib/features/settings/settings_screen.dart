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

  @override
  void initState() {
    super.initState();
    _loadPermission();
  }

  Future<void> _loadPermission() async {
    final status = await ref
        .read(notificationPermissionServiceProvider)
        .status();
    if (mounted) setState(() => _permission = status);
  }

  Future<void> _requestPermission() async {
    final status = await ref
        .read(notificationPermissionServiceProvider)
        .request();
    if (mounted) setState(() => _permission = status);
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
    final message = switch (outcome) {
      ExportOutcome.shared => 'Backup exported.',
      ExportOutcome.cancelled => 'Export cancelled.',
      ExportOutcome.failed => 'Export failed. Please try again.',
    };
    M3ESnackbar.show(context, message: message);
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
          M3ESnackbar.show(context, message: 'Invalid backup: ${e.message}');
        }
        return;
      }
      if (!mounted) return;
      final confirmed = await M3EDialog.show<bool>(
        context,
        dialog: M3EDialog(
          title: 'Replace all data?',
          content: Text(
            'This backup contains ${envelope.habits.length} habits, '
            '${envelope.checkins.length} check-ins, and '
            '${envelope.tasks.length} tasks. Importing replaces ALL current '
            'data and cannot be undone.',
          ),
          actions: [
            M3EButton(
              key: const ValueKey('import-cancel'),
              style: M3EButtonStyle.text,
              onPressed: () => Navigator.of(context).pop(false),
              label: const Text('Cancel'),
            ),
            M3EButton(
              key: const ValueKey('import-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              label: const Text('Replace'),
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
      M3ESnackbar.show(context, message: 'Backup restored.');
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        M3ESnackbar.show(context, message: 'Import failed. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final theme = M3ETheme.of(context);

    return Scaffold(
      appBar: M3EAppBar.top(
        titleText: 'Settings',
        leading: M3EIconButton(
          variant: M3EIconButtonVariant.standard,
          icon: const Icon(M3EIcons.arrow_back),
          tooltip: 'Back',
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
          _SectionHeader(title: 'Appearance', theme: theme),
          const SizedBox(height: 8),
          _SettingsCard(
            theme: theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Theme', style: theme.typography.baseline.titleMedium),
                const SizedBox(height: 12),
                M3ESegmentedButton<AppThemeMode>(
                  selected: {settings.themeMode},
                  onSelectionChanged: (selection) {
                    if (selection.isNotEmpty) {
                      notifier.setThemeMode(selection.first);
                    }
                  },
                  segments: const [
                    M3ESegment(
                      value: AppThemeMode.system,
                      label: 'System',
                      icon: Icon(M3EIcons.brightness_auto),
                    ),
                    M3ESegment(
                      value: AppThemeMode.light,
                      label: 'Light',
                      icon: Icon(M3EIcons.light_mode),
                    ),
                    M3ESegment(
                      value: AppThemeMode.dark,
                      label: 'Dark',
                      icon: Icon(M3EIcons.dark_mode),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SwitchRow(
                  theme: theme,
                  title: 'Dynamic color',
                  subtitle: 'Match your device wallpaper (Material You)',
                  value: settings.dynamicColor,
                  onChanged: notifier.setDynamicColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Motion', theme: theme),
          const SizedBox(height: 8),
          _SettingsCard(
            theme: theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Animation style',
                  style: theme.typography.baseline.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Expressive adds playful bounce. Standard reduces motion. '
                  'Your system accessibility setting always takes priority.',
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
                  segments: const [
                    M3ESegment(
                      value: AppMotionMode.expressive,
                      label: 'Expressive',
                      icon: Icon(M3EIcons.animation),
                    ),
                    M3ESegment(
                      value: AppMotionMode.standard,
                      label: 'Standard',
                      icon: Icon(M3EIcons.motion_photos_auto),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Reminders & week', theme: theme),
          const SizedBox(height: 8),
          _SettingsCard(
            theme: theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Default reminder time',
                  style: theme.typography.baseline.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Pre-filled when you add a reminder to a habit or task.',
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
                              ? 'Set default'
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
                        tooltip: 'Clear default reminder',
                        onPressed: () =>
                            notifier.setDefaultReminderMinutes(null),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                _SwitchRow(
                  theme: theme,
                  title: 'Week starts on Monday',
                  subtitle:
                      'Streaks and stats always use Monday-start weeks; this '
                      'sets the calendar display.',
                  value: settings.weekStartsOnMonday,
                  onChanged: notifier.setWeekStartsOnMonday,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Notifications', theme: theme),
          const SizedBox(height: 8),
          _SettingsCard(
            theme: theme,
            child: _NotificationStatusRow(
              theme: theme,
              status: _permission,
              onRequest: _requestPermission,
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Data', theme: theme),
          const SizedBox(height: 8),
          _SettingsCard(
            theme: theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Backup & restore',
                  style: theme.typography.baseline.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Export everything to a JSON file, or restore from a '
                  'backup. Restoring replaces all current data.',
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
                        label: const Text('Export'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: M3EButton.icon(
                        onPressed: _busy ? null : _import,
                        style: M3EButtonStyle.outlined,
                        icon: const Icon(M3EIcons.download),
                        label: const Text('Import'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'About', theme: theme),
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
                        'NowPill',
                        style: theme.typography.emphasized.titleMedium,
                      ),
                      Text(
                        'Version 0.1.0 · Local-first habits & to-dos',
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
    final (label, color, showRequest) = switch (status) {
      NotificationPermissionStatus.granted => (
        'Notifications are enabled.',
        scheme.primary,
        false,
      ),
      NotificationPermissionStatus.denied => (
        'Notifications are disabled. Reminders will not appear.',
        scheme.error,
        true,
      ),
      NotificationPermissionStatus.notRequired => (
        'This platform does not require notification permission.',
        scheme.onSurfaceVariant,
        false,
      ),
      _ => (
        'Checking notification permission…',
        scheme.onSurfaceVariant,
        false,
      ),
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
            label: const Text('Enable'),
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
