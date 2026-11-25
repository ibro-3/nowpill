import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:motor/motor.dart';

import '../../core/motion/ambient_backdrop.dart';
import '../../core/motion/app_motion.dart';
import '../../core/motion/motion_scheme_provider.dart';
import '../../core/motion/spring_switcher.dart';
import '../../core/router/app_router.dart';
import '../../data/notifications/reminder_coordinator.dart';
import '../../data/repositories/providers.dart';
import '../../data/sync/sync_providers.dart';
import '../../features/today/today_providers.dart';
import '../../l10n/generated/app_localizations.dart';

/// Width at or above which the shell switches from a bottom navigation bar to
/// a navigation rail (M3 medium window class).
const double _kRailBreakpoint = 600;

/// Width at or above which the rail may expand (M3 expanded window class).
/// Medium windows keep the 96dp collapsed rail; the 220–360dp expanded rail
/// belongs to expanded windows where there is room to spare.
const double _kExpandedBreakpoint = 840;

/// The four primary destinations, shared by the bar and the rail. Labels are
/// resolved from the active locale at build time.
List<_Destination> _destinations(AppLocalizations l10n) => [
  _Destination(
    label: l10n.navToday,
    icon: M3EIcons.today_outlined,
    selectedIcon: M3EIcons.today,
  ),
  _Destination(
    label: l10n.navTasks,
    icon: M3EIcons.checklist_outlined,
    selectedIcon: M3EIcons.checklist,
  ),
  _Destination(
    label: l10n.navHabits,
    icon: M3EIcons.repeat_outlined,
    selectedIcon: M3EIcons.repeat,
  ),
  _Destination(
    label: l10n.navStats,
    icon: M3EIcons.insights_outlined,
    selectedIcon: M3EIcons.insights,
  ),
];

class _Destination {
  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Adaptive navigation shell around the go_router [StatefulNavigationShell].
///
/// Compact windows get an [M3ENavigationBar]; medium-and-larger windows get an
/// [M3ENavigationRail]. Both drive the same branch selection, so tab state is
/// preserved across switches and across the adaptive layout change.
///
/// Also owns the reminder lifecycle: it activates the `ReminderCoordinator`
/// for the shell's lifetime and reschedules on app resume, so occurrences
/// that elapsed while backgrounded are rolled forward and a newly granted
/// exact-alarm access takes effect.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _runDailyBackup();
  }

  /// Fire-and-forget daily snapshot (Phase 20). Guarded inside the service;
  /// a failing backup never affects the app.
  Future<void> _runDailyBackup() async {
    try {
      final service = await ref.read(autoBackupServiceProvider.future);
      await service.runDailyBackup();
    } catch (_) {
      // Documents dir unavailable (tests/web): skip silently.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Fire-and-forget: rescheduling is guarded and must never block the UI.
      unawaited(ref.read(reminderCoordinatorProvider).rescheduleAll());
      // Pick up remote changes that landed while backgrounded.
      ref.read(syncCoordinatorProvider).scheduleSync();
      // Pick up notification-action writes made in the background isolate.
      refreshDatabaseStreams(ref.read(appDatabaseProvider));
    }
  }

  void _onDestinationSelected(int index) {
    widget.navigationShell.goBranch(
      index,
      // Tapping the active tab again pops to its root.
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Activate the reactive reminder scheduler for the lifetime of the shell.
    ref.watch(reminderCoordinatorProvider);
    // Keep the home-screen widget in sync with the data.
    ref.watch(widgetSnapshotControllerProvider);
    // Activate file sync (idle until enabled in Settings).
    ref.watch(syncCoordinatorProvider);

    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= _kRailBreakpoint;
    final index = widget.navigationShell.currentIndex;
    final l10n = AppLocalizations.of(context);
    final destinations = _destinations(l10n);

    // M3 navigation badges report dynamic information and clear once the user
    // has seen the destination. Counts come from the same Today view model the
    // dashboard renders, so they never drift from the list itself.
    final today = ref.watch(todayViewModelProvider);
    final badgeCounts = <int, int>{
      1: today.overdueTasks.length,
      2: today.habits.length,
    };
    int? badgeFor(int destination) {
      final count = badgeCounts[destination] ?? 0;
      return count > 0 ? count : null;
    }

    // The branch itself keeps its state (IndexedStack); only the incoming
    // content's opacity/position springs. Reduced motion renders it directly.
    final branch = SpringSwitcher(
      switchKey: index,
      child: widget.navigationShell,
    );

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            M3ENavigationRail(
              type: width >= _kExpandedBreakpoint
                  ? M3ENavigationRailType.expanded
                  : M3ENavigationRailType.collapsed,
              selectedIndex: index,
              onDestinationSelected: _onDestinationSelected,
              leading: const _RailBrand(),
              sections: [
                M3ENavigationRailSection(
                  destinations: [
                    for (var i = 0; i < destinations.length; i++)
                      M3ENavigationRailDestination(
                        icon: _NavIconWiggle(
                          selected: i == index,
                          icon: destinations[i].icon,
                          selectedIcon: destinations[i].selectedIcon,
                        ),
                        selectedIcon: _NavIconWiggle(
                          selected: i == index,
                          icon: destinations[i].icon,
                          selectedIcon: destinations[i].selectedIcon,
                        ),
                        label: destinations[i].label,
                        badgeCount: badgeFor(i),
                      ),
                  ],
                ),
              ],
              trailing: const _SettingsButton(),
            ),
            Expanded(
              child: Stack(
                children: [
                  const Positioned.fill(child: AmbientBackdrop()),
                  branch,
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackdrop()),
          branch,
        ],
      ),
      // The bar sizes itself from its content (which scales with the system
      // text size) and adds the bottom safe-area inset internally. Wrapping it
      // in a fixed height clipped the labels and hid them behind the gesture
      // pill on devices with a bottom inset.
      bottomNavigationBar: M3ENavigationBar(
        selectedIndex: index,
        onDestinationSelected: _onDestinationSelected,
        destinations: [
          for (var i = 0; i < destinations.length; i++)
            M3ENavigationBarDestination(
              icon: Icon(destinations[i].icon),
              selectedIcon: Icon(destinations[i].selectedIcon),
              label: destinations[i].label,
              badgeCount: badgeFor(i),
            ),
        ],
      ),
    );
  }
}

/// Compact brand mark for the expanded rail. A single shape container is used
/// as an icon crop — never behind text-heavy content (M3 shape guidance).
class _RailBrand extends StatelessWidget {
  const _RailBrand();

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          M3EShapeContainer(
            kind: M3EShapeKind.cookie6Sided,
            width: 36,
            height: 36,
            color: theme.colorScheme.primaryContainer,
            child: Icon(
              M3EIcons.today,
              size: 20,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// Nav icons already get M3E's small scale pop. This adds a one-shot tilt on
/// top — enough to feel alive, not enough to distract from the label. Reduced
/// motion skips it entirely.
class _NavIconWiggle extends StatefulWidget {
  const _NavIconWiggle({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;

  @override
  State<_NavIconWiggle> createState() => _NavIconWiggleState();
}

class _NavIconWiggleState extends State<_NavIconWiggle>
    with SingleTickerProviderStateMixin {
  late final SequenceMotionController<int, double> _tilt =
      SequenceMotionController<int, double>(
        motion: MotionTokens.expressive.spatialFast,
        vsync: this,
        converter: const SingleMotionConverter(),
        initialValue: 0,
      );

  @override
  void didUpdateWidget(covariant _NavIconWiggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tokens = MotionScope.of(context);
    if (!oldWidget.selected && widget.selected && !tokens.reduced) {
      _tilt
        ..motion = tokens.spatialFast
        ..playSequence(
          MotionSequence.steps(const [
            0.0,
            -1.0,
            0.55,
            0.0,
          ], motion: tokens.spatialFast),
        );
    }
  }

  @override
  void dispose() {
    _tilt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tilt,
      builder: (context, _) => Transform.rotate(
        // −1 → +0.55 → 0 maps to ≈ −8° → +4.4° → 0°.
        angle: _tilt.value * 0.14,
        child: Icon(widget.selected ? widget.selectedIcon : widget.icon),
      ),
    );
  }
}

/// Opens the settings route. Rendered as a rail trailing item on wide layouts.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton();

  @override
  Widget build(BuildContext context) {
    return M3EIconButton(
      variant: M3EIconButtonVariant.standard,
      icon: const Icon(M3EIcons.settings_outlined),
      tooltip: AppLocalizations.of(context).settings,
      onPressed: () => context.push(AppRoutes.settings),
    );
  }
}
