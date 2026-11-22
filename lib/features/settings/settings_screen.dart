import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/app_settings_provider.dart';

/// App preferences: theme, motion, and dynamic color.
///
/// Export/import and reminder defaults are added in later phases.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          const SizedBox(height: 32),
        ],
      ),
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
