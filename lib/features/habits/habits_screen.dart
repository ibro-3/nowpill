import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/providers.dart';
import '../../domain/date_utils.dart';
import '../../l10n/generated/app_localizations.dart';
import '../shell/feature_placeholders.dart';
import 'habit_detail_screen.dart';
import 'habit_editor_sheet.dart';
import 'habit_providers.dart';
import 'relapse_sheet.dart';
import 'widgets/habit_card.dart';

/// The Habits tab: active habits with check-pills, streaks, and tokens.
class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);
    final habits = ref.watch(activeHabitsProvider).value ?? const [];
    final routines = ref.watch(allRoutinesProvider).value ?? const <Routine>[];
    final filter = ref.watch(routineFilterProvider);
    final visible = habits.where((habit) {
      if (filter == null) return true;
      if (filter == -1) return habit.routineId == null;
      return habit.routineId == filter;
    }).toList();

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
          : Column(
              children: [
                if (routines.isNotEmpty)
                  SizedBox(
                    height: 56,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _chip(
                          l10n.all,
                          filter == null,
                          () => ref
                              .read(routineFilterProvider.notifier)
                              .set(null),
                        ),
                        for (final routine in routines)
                          _chip(
                            routine.name,
                            filter == routine.id,
                            () => ref
                                .read(routineFilterProvider.notifier)
                                .set(filter == routine.id ? null : routine.id),
                          ),
                        _chip(
                          l10n.unrouted,
                          filter == -1,
                          () => ref
                              .read(routineFilterProvider.notifier)
                              .set(filter == -1 ? null : -1),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              l10n.habitsEmptyActive,
                              style: theme.typography.baseline.bodyMedium,
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                          children: [
                            if (routines.isEmpty)
                              ..._cards(context, ref, visible),
                            for (final routine in routines)
                              if (filter == null ||
                                  filter == routine.id &&
                                      visible.any(
                                        (h) => h.routineId == routine.id,
                                      ))
                                _RoutineSection(
                                  key: ValueKey(
                                    'routine-section-${routine.id}',
                                  ),
                                  name: routine.name,
                                  color: Color(routine.color),
                                  theme: theme,
                                  children: _cards(
                                    context,
                                    ref,
                                    visible
                                        .where((h) => h.routineId == routine.id)
                                        .toList(),
                                  ),
                                ),
                            if (routines.isNotEmpty &&
                                (filter == null || filter == -1))
                              if (visible.any((h) => h.routineId == null))
                                _RoutineSection(
                                  key: const ValueKey(
                                    'routine-section-unrouted',
                                  ),
                                  name: l10n.unrouted,
                                  color: theme.colorScheme.outline,
                                  theme: theme,
                                  children: _cards(
                                    context,
                                    ref,
                                    visible
                                        .where((h) => h.routineId == null)
                                        .toList(),
                                  ),
                                ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: M3EChip(
          label: label,
          type: M3EChipType.filter,
          selected: selected,
          onPressed: onPressed,
        ),
      ),
    );
  }

  List<Widget> _cards(BuildContext context, WidgetRef ref, List<Habit> habits) {
    return [
      for (final habit in habits)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: HabitCard(
            key: ValueKey('habit-${habit.id}'),
            habit: habit,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => HabitDetailScreen(habitId: habit.id),
              ),
            ),
            onCheckIn: () => _toggleToday(ref, habit.id),
            onLogRelapse: () => _logRelapse(context, ref, habit.id),
          ),
        ),
    ];
  }

  Future<void> _logRelapse(
    BuildContext context,
    WidgetRef ref,
    int habitId,
  ) async {
    final note = await showRelapseDialog(context);
    if (note == null) return;
    await ref
        .read(habitRepositoryProvider)
        .logRelapse(
          habitId,
          formatDate(DateTime.now()),
          note: note.isEmpty ? null : note,
        );
    if (context.mounted) {
      M3ESnackbar.show(
        context,
        message: AppLocalizations.of(context).relapseLogged,
      );
    }
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

class _RoutineSection extends StatelessWidget {
  const _RoutineSection({
    required this.name,
    required this.color,
    required this.theme,
    required this.children,
    super.key,
  });

  final String name;
  final Color color;
  final M3EThemeData theme;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(M3EIcons.circle, size: 14, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: theme.typography.emphasized.titleSmall.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}
