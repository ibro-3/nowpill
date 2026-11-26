import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/platform/link_launcher.dart';
import '../../core/settings/app_settings_provider.dart';
import '../../core/widgets/connected_choice_group.dart';
import '../../data/updates/update_coordinator.dart';
import '../../domain/update_checker.dart';
import '../../l10n/generated/app_localizations.dart';

const String kReleasesPage = 'https://github.com/ibro-3/nowpill/releases';

/// Settings card for GitHub release checks and downloads.
///
/// From M3: one primary action per screen, connected button group for a short
/// single-choice list, wavy determinate progress for a long download, and a
/// snackbar for low-priority errors. All feedback stays on baseline type;
/// emphasized type marks the available update only.
class UpdateCard extends ConsumerStatefulWidget {
  const UpdateCard({super.key});

  @override
  ConsumerState<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends ConsumerState<UpdateCard> {
  bool _needsInstallPermission = false;

  @override
  void initState() {
    super.initState();
    _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      final can = await ref.read(updateCoordinatorProvider).canInstall();
      if (mounted) setState(() => _needsInstallPermission = !can);
    } catch (_) {
      // Method channel unavailable (tests/web): the option simply stays hidden.
    }
  }

  String _modeLabel(UpdateCheckMode mode, AppLocalizations l10n) {
    return switch (mode) {
      UpdateCheckMode.off => l10n.updateModeOff,
      UpdateCheckMode.manual => l10n.updateModeManual,
      UpdateCheckMode.startup => l10n.updateModeStartup,
      UpdateCheckMode.daily => l10n.updateModeDaily,
      UpdateCheckMode.weekly => l10n.updateModeWeekly,
    };
  }

  UpdatePlatform get _platform {
    if (kIsWeb) {
      return UpdatePlatform.other;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return UpdatePlatform.android;
    }
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return UpdatePlatform.linux;
    }
    return UpdatePlatform.other;
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(updateStateProvider);
    final settings = ref.watch(appSettingsProvider).value;
    final version = ref.watch(packageInfoProvider).value?.version ?? '0.0.0';
    final coordinator = ref.watch(updateCoordinatorProvider);
    final checked = state.lastChecked;
    final locale = Localizations.localeOf(context).toLanguageTag();

    return M3ECard(
      variant: M3ECardVariant.elevated,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.updateCheckMode,
            style: theme.typography.emphasized.titleSmall.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          ConnectedChoiceGroup<UpdateCheckMode>(
            values: UpdateCheckMode.values,
            labels: [
              for (final mode in UpdateCheckMode.values) _modeLabel(mode, l10n),
            ],
            selected: settings?.updateCheckMode ?? UpdateCheckMode.startup,
            onChanged: (mode) =>
                ref.read(appSettingsProvider.notifier).setUpdateCheckMode(mode),
            semanticLabel: l10n.updateCheckMode,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.aboutVersion(version),
            style: theme.typography.baseline.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _status(l10n, theme, state, locale),
          if (state.release != null &&
              (state.status == UpdateStatus.available ||
                  state.status == UpdateStatus.downloaded) &&
              state.release!.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              state.release!.notes.replaceAll(RegExp(r'\s+'), ' ').trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.baseline.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              M3EButton.icon(
                key: const ValueKey('update-check-now'),
                style: M3EButtonStyle.tonal,
                icon: const Icon(M3EIcons.autorenew),
                label: Text(l10n.updateCheckNow),
                onPressed: state.status == UpdateStatus.checking
                    ? null
                    : coordinator.checkNow,
              ),
              if (state.status == UpdateStatus.available &&
                  state.release != null)
                M3EButton.icon(
                  key: const ValueKey('update-download'),
                  icon: const Icon(M3EIcons.download),
                  label: Text(
                    _platform == UpdatePlatform.android
                        ? l10n.updateInstall
                        : l10n.updateDownload,
                  ),
                  onPressed: () async {
                    await coordinator.downloadAndInstall(state.release!);
                    await _refreshPermission();
                  },
                ),
              if (_platform == UpdatePlatform.other)
                M3EButton.icon(
                  style: M3EButtonStyle.text,
                  icon: const Icon(M3EIcons.open_in_new),
                  label: Text(l10n.updateOpenReleases),
                  onPressed: _openReleasesPage,
                ),
              if (_needsInstallPermission)
                M3EButton.icon(
                  style: M3EButtonStyle.text,
                  icon: const Icon(M3EIcons.settings_outlined),
                  label: Text(l10n.updateOpenSettings),
                  onPressed: () async {
                    await coordinator.openInstallSettings();
                    await _refreshPermission();
                  },
                ),
            ],
          ),
          if (checked != null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.updateLastChecked(
                DateFormat.yMMMd(locale).add_jm().format(checked.toLocal()),
              ),
              style: theme.typography.baseline.labelSmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openReleasesPage() async {
    // Reuse the same injectable launcher as chat links, so tests stay offline.
    await ref.read(linkLauncherProvider).open(Uri.parse(kReleasesPage));
  }

  Widget _status(
    AppLocalizations l10n,
    M3EThemeData theme,
    UpdateState state,
    String locale,
  ) {
    switch (state.status) {
      case UpdateStatus.checking:
        if (state.progress > 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.updateDownloading,
                style: theme.typography.baseline.bodySmall,
              ),
              const SizedBox(height: 8),
              M3EProgressIndicator.linearWavy(
                value: state.progress.clamp(0.0, 1.0),
                semanticsLabel: l10n.updateDownloading,
              ),
            ],
          );
        }
        return Row(
          children: [
            const SizedBox(width: 24, height: 24, child: M3ELoadingIndicator()),
            const SizedBox(width: 8),
            Text(
              l10n.updateChecking,
              style: theme.typography.baseline.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      case UpdateStatus.available:
        return Text(
          l10n.updateAvailable(state.release?.version ?? ''),
          style: theme.typography.emphasized.titleSmall.copyWith(
            color: theme.colorScheme.primary,
          ),
        );
      case UpdateStatus.downloaded:
        return Text(
          l10n.updateDownloaded,
          style: theme.typography.baseline.bodyMedium.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        );
      case UpdateStatus.upToDate:
        return Text(
          l10n.updateUpToDate,
          style: theme.typography.baseline.bodyMedium.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );
      case UpdateStatus.error:
        return Text(
          l10n.updateFailed,
          style: theme.typography.baseline.bodyMedium.copyWith(
            color: theme.colorScheme.error,
          ),
        );
      case UpdateStatus.idle:
        return const SizedBox.shrink();
    }
  }
}
