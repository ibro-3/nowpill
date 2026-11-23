import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/repositories/providers.dart';
import '../../domain/date_utils.dart';
import '../../l10n/generated/app_localizations.dart';
import '../shell/feature_placeholders.dart';
import 'habit_detail_screen.dart';
import 'habit_editor_sheet.dart';
import 'habit_providers.dart';
import 'widgets/habit_card.dart';

/// The Habits tab: active habits with check-pills, streaks, and tokens.
class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);
    final habits = ref.watch(activeHabitsProvider).value ?? const [];

    return Scaffold(
      appBar: M3EAppBar.top(
        titleText: l10n.navHabits,
        actions: const [SearchAction(), SettingsAction()],
      ),
      floatingActionButton: M3EFab(
        icon: const Icon(M3EIcons.add),
        tooltip: l10n.newHabit,
        onPressed: () => showHabitEditor(context),
      ),
      body: habits.isEmpty
          ? _EmptyState(theme: theme)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: habits.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final habit = habits[i];
                return HabitCard(
                  key: ValueKey('habit-${habit.id}'),
                  habit: habit,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => HabitDetailScreen(habitId: habit.id),
                    ),
                  ),
                  onCheckIn: () => _toggleToday(ref, habit.id),
                );
              },
            ),
    );
  }

  Future<void> _toggleToday(WidgetRef ref, int habitId) async {
    final repo = ref.read(habitRepositoryProvider);
    final today = formatDate(DateTime.now());
    final checked = ref.read(habitCheckedTodayProvider(habitId));
    if (checked) {
      await repo.removeCheckIn(habitId, today);
    } else {
      // Measurable habits: the list pill completes the whole goal (partial
      // progress is logged from the Today stepper).
      final target = ref.read(habitProvider(habitId)).value?.targetAmount;
      await repo.checkIn(habitId, today, amount: target);
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});

  final M3EThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            M3EShapeContainer(
              kind: M3EShapeKind.cookie9Sided,
              width: 80,
              height: 80,
              color: theme.colorScheme.surfaceContainerHigh,
              child: Icon(
                M3EIcons.repeat,
                size: 34,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).habitsEmpty,
              textAlign: TextAlign.center,
              style: theme.typography.baseline.bodyLarge.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
