import 'package:go_router/go_router.dart';

import '../../features/habits/habits_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/stats/stats_screen.dart';
import '../../features/tasks/tasks_screen.dart';
import '../../features/today/today_screen.dart';

/// Route paths for the four primary destinations.
abstract final class AppRoutes {
  const AppRoutes._();

  static const String today = '/today';
  static const String tasks = '/tasks';
  static const String habits = '/habits';
  static const String stats = '/stats';
  static const String settings = '/settings';
  static const String search = '/search';
}

/// Builds the app router: a [StatefulShellRoute] with one branch per tab
/// (state preserved across tab switches) plus a root-level settings route.
GoRouter buildRouter() {
  return GoRouter(
    initialLocation: AppRoutes.today,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.today,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: TodayScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.tasks,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: TasksScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.habits,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: HabitsScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.stats,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: StatsScreen()),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.search,
        builder: (context, state) => const SearchScreen(),
      ),
    ],
  );
}
