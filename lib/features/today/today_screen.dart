import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/providers.dart';
import '../../domain/date_utils.dart';
import '../../l10n/generated/app_localizations.dart';
import '../habits/habit_icons.dart';
import '../habits/habit_providers.dart';
import '../habits/widgets/streak_odometer.dart';
import '../shell/feature_placeholders.dart';
import '../tasks/task_editor_sheet.dart';
import '../tasks/widgets/check_pill.dart';
import '../tasks/widgets/task_card.dart';
import 'today_providers.dart';
import 'today_view_model.dart';
import 'widgets/confetti_overlay.dart';
import 'widgets/floating_pills.dart';
import 'widgets/quick_add_bar.dart';
import 'widgets/today_progress_ring.dart';

/// The Today dashboard: greeting + progress ring, then overdue → habits due →
/// tasks due → done-today, with quick-add and an all-done celebration.
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  int _confettiToken = 0;
  bool _wasAllDone = false;

  Future<void> _toggleTask(Task task) async {
    final repo = ref.read(taskRepositoryProvider);
    if (task.completedAt != null) {
      await repo.reopen(task.id);
    } else {
      await repo.complete(task.id);
      unawaited(HapticFeedback.lightImpact());
    }
  }

  Future<void> _toggleHabit(TodayHabit item) async {
    final repo = ref.read(habitRepositoryProvider);
    final today = formatDate(DateTime.now());
    if (item.checkedToday) {
      await repo.removeCheckIn(item.habit.id, today);
    } else {
      await repo.checkIn(item.habit.id, today);
      unawaited(HapticFeedback.lightImpact());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);
    final vm = ref.watch(todayViewModelProvider);

    // Fire the celebration once per transition into the all-done state.
    if (vm.allDone && !_wasAllDone) {
      _confettiToken++;
      HapticFeedback.mediumImpact();
    }
    _wasAllDone = vm.allDone;

    final now = DateTime.now();
    return Scaffold(
      appBar: M3EAppBar.top(
        titleText: l10n.navToday,
        actions: const [SettingsAction()],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    _Header(vm: vm, theme: theme, now: now),
                    const SizedBox(height: 20),
                    if (vm.total == 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 32),
                        child: FloatingPills(
                          icon: M3EIcons.wb_twilight,
                          message: l10n.todayEmpty,
                        ),
                      )
                    else ...[
                      if (vm.allDone) ...[
                        _AllDoneBanner(theme: theme),
                        const SizedBox(height: 16),
                      ],
                      if (vm.overdueTasks.isNotEmpty) ...[
                        _SectionHeader(
                          title: l10n.sectionOverdue,
                          count: vm.overdueTasks.length,
                          color: theme.colorScheme.error,
                          theme: theme,
                        ),
                        for (final task in vm.overdueTasks)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TaskCard(
                              key: ValueKey('today-task-${task.id}'),
                              task: task,
                              onTap: () => showTaskEditor(context, task: task),
                              onToggleComplete: () => _toggleTask(task),
                            ),
                          ),
                        const SizedBox(height: 12),
                      ],
                      if (vm.habits.isNotEmpty) ...[
                        _SectionHeader(
                          title: l10n.sectionHabits,
                          count: vm.habits.length,
                          color: theme.colorScheme.primary,
                          theme: theme,
                        ),
                        for (final item in vm.habits)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _TodayHabitTile(
                              key: ValueKey('today-habit-${item.habit.id}'),
                              item: item,
                              onToggle: () => _toggleHabit(item),
                            ),
                          ),
                        const SizedBox(height: 12),
                      ],
                      if (vm.dueTodayTasks.isNotEmpty) ...[
                        _SectionHeader(
                          title: l10n.sectionDueToday,
                          count: vm.dueTodayTasks.length,
                          color: theme.colorScheme.primary,
                          theme: theme,
                        ),
                        for (final task in vm.dueTodayTasks)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TaskCard(
                              key: ValueKey('today-task-${task.id}'),
                              task: task,
                              onTap: () => showTaskEditor(context, task: task),
                              onToggleComplete: () => _toggleTask(task),
                            ),
                          ),
                        const SizedBox(height: 12),
                      ],
                      if (vm.completedTodayTasks.isNotEmpty) ...[
                        _SectionHeader(
                          title: l10n.sectionDoneToday,
                          count: vm.completedTodayTasks.length,
                          color: theme.colorScheme.onSurfaceVariant,
                          theme: theme,
                        ),
                        for (final task in vm.completedTodayTasks)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TaskCard(
                              key: ValueKey('today-task-${task.id}'),
                              task: task,
                              onTap: () => showTaskEditor(context, task: task),
                              onToggleComplete: () => _toggleTask(task),
                            ),
                          ),
                      ],
                    ],
                  ],
                ),
              ),
              const QuickAddBar(),
            ],
          ),
          Positioned.fill(
            child: ConfettiOverlay(
              playToken: _confettiToken,
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.tertiary,
                const Color(0xFFFFB454),
                const Color(0xFF5B8DEF),
                const Color(0xFFEF5DA8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.vm, required this.theme, required this.now});

  final TodayViewModel vm;
  final M3EThemeData theme;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(l10n, now),
                style: theme.typography.baseline.titleMedium.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _dateLabel(l10n, now),
                style: theme.typography.emphasized.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                vm.total == 0
                    ? l10n.todayClearDay
                    : vm.allDone
                    ? l10n.todayAllDoneSubtitle
                    : l10n.todayProgress(vm.remaining, vm.done),
                style: theme.typography.baseline.bodyMedium.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        TodayProgressRing(
          progress: vm.progress,
          done: vm.done,
          total: vm.total,
          celebrate: vm.allDone,
        ),
      ],
    );
  }

  String _greeting(AppLocalizations l10n, DateTime now) {
    final h = now.hour;
    if (h < 5) return l10n.greetingUpLate;
    if (h < 12) return l10n.greetingMorning;
    if (h < 17) return l10n.greetingAfternoon;
    if (h < 22) return l10n.greetingEvening;
    return l10n.greetingWindingDown;
  }

  String _dateLabel(AppLocalizations l10n, DateTime now) {
    final weekdays = [
      l10n.weekdayMonday,
      l10n.weekdayTuesday,
      l10n.weekdayWednesday,
      l10n.weekdayThursday,
      l10n.weekdayFriday,
      l10n.weekdaySaturday,
      l10n.weekdaySunday,
    ];
    final months = [
      l10n.monthJan,
      l10n.monthFeb,
      l10n.monthMar,
      l10n.monthApr,
      l10n.monthMay,
      l10n.monthJun,
      l10n.monthJul,
      l10n.monthAug,
      l10n.monthSep,
      l10n.monthOct,
      l10n.monthNov,
      l10n.monthDec,
    ];
    return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }
}

class _AllDoneBanner extends StatelessWidget {
  const _AllDoneBanner({required this.theme});

  final M3EThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          M3EShapeContainer(
            kind: M3EShapeKind.softBurst,
            width: 40,
            height: 40,
            color: theme.colorScheme.tertiary,
            child: Icon(
              M3EIcons.celebration,
              size: 20,
              color: theme.colorScheme.onTertiary,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              AppLocalizations.of(context).allDoneBanner,
              style: theme.typography.emphasized.titleMedium.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
    required this.theme,
  });

  final String title;
  final int count;
  final Color color;
  final M3EThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            title,
            style: theme.typography.emphasized.titleSmall.copyWith(
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: theme.typography.baseline.labelSmall.copyWith(
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact habit row for the dashboard: icon cookie, name, streak odometer,
/// and the signature check-pill.
class _TodayHabitTile extends StatelessWidget {
  const _TodayHabitTile({
    required this.item,
    required this.onToggle,
    super.key,
  });

  final TodayHabit item;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final habit = item.habit;
    final color = Color(habit.color);

    return M3ECard(
      variant: M3ECardVariant.filled,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          M3EShapeContainer(
            kind: M3EShapeKind.cookie6Sided,
            width: 38,
            height: 38,
            color: color.withValues(alpha: 0.18),
            child: Icon(habitIconForKey(habit.iconKey), size: 19, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              habit.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.baseline.titleMedium.copyWith(
                decoration: item.checkedToday
                    ? TextDecoration.lineThrough
                    : null,
                color: item.checkedToday
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _HabitStreakBadge(habitId: habit.id),
          const SizedBox(width: 12),
          CheckPill(
            checked: item.checkedToday,
            activeColor: color,
            onChanged: (_) => onToggle(),
            semanticLabel: item.checkedToday
                ? AppLocalizations.of(context).undoCheckInHabit(habit.name)
                : AppLocalizations.of(context).checkInHabit(habit.name),
          ),
        ],
      ),
    );
  }
}

class _HabitStreakBadge extends ConsumerWidget {
  const _HabitStreakBadge({required this.habitId});

  final int habitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = M3ETheme.of(context);
    final streak = ref.watch(habitStreakProvider(habitId));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          M3EIcons.local_fire_department,
          size: 15,
          color: streak.currentStreak > 0
              ? theme.colorScheme.tertiary
              : theme.colorScheme.outline,
        ),
        const SizedBox(width: 2),
        StreakOdometer(
          value: streak.currentStreak,
          style: theme.typography.emphasized.titleSmall,
        ),
      ],
    );
  }
}
