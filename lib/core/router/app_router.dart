import 'package:go_router/go_router.dart';

import '../../features/chat/chat_screen.dart';
import '../../features/habits/archived_habits_screen.dart';
import '../../features/habits/habits_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/stats/stats_screen.dart';
import '../../features/tasks/tasks_screen.dart';
import '../../features/today/today_screen.dart';

/// Route paths for the five primary destinations.
abstract final class AppRoutes {
  const AppRoutes._();

  static const String today = '/today';
  static const String tasks = '/tasks';
  static const String habits = '/habits';
  static const String stats = '/stats';
  static const String chat = '/chat';
  static const String settings = '/settings';
  static const String search = '/search';
  static const String onboarding = '/onboarding';
  static const String archivedHabits = '/habits/archived';
}

/// Builds the app router: a [StatefulShellRoute] with one branch per tab
/// (state preserved across tab switches) plus a root-level settings route.
GoRouter buildRouter({GoRouterRedirect? redirect}) {
  return GoRouter(
    initialLocation: AppRoutes.today,
    redirect: redirect,
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
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.chat,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: ChatScreen()),
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
      GoRoute(
        path: AppRoutes.archivedHabits,
        builder: (context, state) => const ArchivedHabitsScreen(),
      ),
      // Top-level: the first-run flow must not be trapped inside a shell tab.
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
    ],
  );
}
