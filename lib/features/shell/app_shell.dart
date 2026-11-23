import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';
import '../../data/repositories/providers.dart';

/// Width at or above which the shell switches from a bottom navigation bar to
/// a navigation rail (M3 medium window class).
const double _kRailBreakpoint = 600;

/// The four primary destinations, shared by the bar and the rail.
const List<_Destination> _destinations = [
  _Destination(
    label: 'Today',
    icon: M3EIcons.today_outlined,
    selectedIcon: M3EIcons.today,
  ),
  _Destination(
    label: 'Tasks',
    icon: M3EIcons.checklist_outlined,
    selectedIcon: M3EIcons.checklist,
  ),
  _Destination(
    label: 'Habits',
    icon: M3EIcons.repeat_outlined,
    selectedIcon: M3EIcons.repeat,
  ),
  _Destination(
    label: 'Stats',
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
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      // Tapping the active tab again pops to its root.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Activate the reactive reminder scheduler for the lifetime of the shell.
    ref.watch(reminderCoordinatorProvider);

    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= _kRailBreakpoint;
    final index = navigationShell.currentIndex;

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
                    for (final d in _destinations)
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
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: M3ENavigationBar(
        selectedIndex: index,
        onDestinationSelected: _onDestinationSelected,
        destinations: [
          for (final d in _destinations)
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
      tooltip: 'Settings',
      onPressed: () => context.push(AppRoutes.settings),
    );
  }
}
