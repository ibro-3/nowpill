import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';
import '../../data/repositories/providers.dart';
import '../../l10n/generated/app_localizations.dart';

/// Width at or above which the shell switches from a bottom navigation bar to
/// a navigation rail (M3 medium window class).
const double _kRailBreakpoint = 600;

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

    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= _kRailBreakpoint;
    final index = widget.navigationShell.currentIndex;
    final destinations = _destinations(AppLocalizations.of(context));

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            M3ENavigationRail(
              type: M3ENavigationRailType.expanded,
              selectedIndex: index,
              onDestinationSelected: _onDestinationSelected,
              sections: [
                M3ENavigationRailSection(
                  destinations: [
                    for (final d in destinations)
                      M3ENavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: d.label,
                      ),
                  ],
                ),
              ],
              trailing: const _SettingsButton(),
            ),
            Expanded(child: widget.navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: M3ENavigationBar(
        selectedIndex: index,
        onDestinationSelected: _onDestinationSelected,
        destinations: [
          for (final d in destinations)
            M3ENavigationBarDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
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
