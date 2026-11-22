import 'package:go_router/go_router.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';

/// App-bar action that opens the settings route. Used on compact layouts where
/// there is no navigation rail trailing slot.
class SettingsAction extends StatelessWidget {
  const SettingsAction({super.key});

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

/// Placeholder for the Today dashboard (built in Phase 6).
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _FeaturePlaceholder(
      icon: M3EIcons.today,
      title: 'Today',
      message: 'Your daily habits and tasks will appear here.',
    );
  }
}

/// Placeholder for the Tasks feature (built in Phase 4).
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _FeaturePlaceholder(
      icon: M3EIcons.checklist,
      title: 'Tasks',
      message: 'To-dos with due dates, subtasks, tags, and recurrence.',
    );
  }
}

/// Placeholder for the Habits feature (built in Phase 5).
class HabitsScreen extends StatelessWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _FeaturePlaceholder(
      icon: M3EIcons.repeat,
      title: 'Habits',
      message: 'Streaks, freeze tokens, and check-in heatmaps.',
    );
  }
}

/// Placeholder for the Stats feature (built in Phase 7).
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _FeaturePlaceholder(
      icon: M3EIcons.insights,
      title: 'Stats',
      message: 'Completion trends and streak leaderboards.',
    );
  }
}

class _FeaturePlaceholder extends StatelessWidget {
  const _FeaturePlaceholder({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    return Scaffold(
      appBar: M3EAppBar.top(
        titleText: title,
        actions: const [SettingsAction()],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              M3EShapeContainer(
                kind: M3EShapeKind.cookie9Sided,
                width: 96,
                height: 96,
                color: theme.colorScheme.primaryContainer,
                child: Icon(
                  icon,
                  size: 40,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(title, style: theme.typography.emphasized.headlineMedium),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.typography.baseline.bodyLarge.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
