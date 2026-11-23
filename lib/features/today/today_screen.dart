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

  /// Logs one more unit toward a measurable habit's daily goal. Reaching the
  /// goal counts as the day's check-in (streak); partial progress is UI-only.
  Future<void> _addAmount(TodayHabit item) async {
    final repo = ref.read(habitRepositoryProvider);
    final today = formatDate(DateTime.now());
    final target = item.targetAmount ?? 1;
    final next = (item.amountToday ?? 0) + 1;
    await repo.checkIn(item.habit.id, today, amount: next);
    unawaited(HapticFeedback.lightImpact());
    if (next >= target) unawaited(HapticFeedback.mediumImpact());
  }

  /// Removes one logged unit; dropping to zero clears the day's check-in.
  Future<void> _removeAmount(TodayHabit item) async {
    final repo = ref.read(habitRepositoryProvider);
    final today = formatDate(DateTime.now());
    final next = (item.amountToday ?? 0) - 1;
    if (next <= 0) {
      await repo.removeCheckIn(item.habit.id, today);
    } else {
      await repo.checkIn(item.habit.id, today, amount: next);
    }
  }

  /// Marks a measurable habit's goal fully met (or clears it when done).
  Future<void> _completeGoal(TodayHabit item) async {
    final repo = ref.read(habitRepositoryProvider);
    final today = formatDate(DateTime.now());
    if (item.checkedToday) {
      await repo.removeCheckIn(item.habit.id, today);
    } else {
      await repo.checkIn(item.habit.id, today, amount: item.targetAmount);
      unawaited(HapticFeedback.mediumImpact());
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
                              onAddAmount: () => _addAmount(item),
                              onRemoveAmount: () => _removeAmount(item),
                              onCompleteGoal: () => _completeGoal(item),
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
/// and the signature check-pill. Measurable habits swap the pill for a
/// progress stepper (− amount/target +) plus a goal-complete pill.
class _TodayHabitTile extends StatelessWidget {
  const _TodayHabitTile({
    required this.item,
    required this.onToggle,
    required this.onAddAmount,
    required this.onRemoveAmount,
    required this.onCompleteGoal,
    super.key,
  });

  final TodayHabit item;
  final VoidCallback onToggle;
  final VoidCallback onAddAmount;
  final VoidCallback onRemoveAmount;
  final VoidCallback onCompleteGoal;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);
    final habit = item.habit;
    final color = Color(habit.color);
    final measurable = item.targetAmount != null;

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
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
                if (measurable) ...[
                  const SizedBox(height: 4),
                  _AmountBar(
                    progress: item.amountProgress,
                    color: color,
                    done: item.checkedToday,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _HabitStreakBadge(habitId: habit.id),
          const SizedBox(width: 12),
          if (measurable)
            _AmountStepper(
              item: item,
              color: color,
              l10n: l10n,
              onAdd: onAddAmount,
              onRemove: onRemoveAmount,
              onComplete: onCompleteGoal,
            )
          else
            CheckPill(
              checked: item.checkedToday,
              activeColor: color,
              onChanged: (_) => onToggle(),
              semanticLabel: item.checkedToday
                  ? l10n.undoCheckInHabit(habit.name)
                  : l10n.checkInHabit(habit.name),
            ),
        ],
      ),
    );
  }
}

/// Thin progress bar under a measurable habit's name (0…1 of the daily goal).
class _AmountBar extends StatelessWidget {
  const _AmountBar({
    required this.progress,
    required this.color,
    required this.done,
  });

  final double progress;
  final Color color;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 5,
        child: Stack(
          children: [
            Container(color: theme.colorScheme.surfaceContainerHighest),
            FractionallySizedBox(
              widthFactor: progress,
              child: Container(
                color: done ? color : color.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// − amount/target + stepper with a goal-complete pill for measurable habits.
class _AmountStepper extends StatelessWidget {
  const _AmountStepper({
    required this.item,
    required this.color,
    required this.l10n,
    required this.onAdd,
    required this.onRemove,
    required this.onComplete,
  });

  final TodayHabit item;
  final Color color;
  final AppLocalizations l10n;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onComplete;

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final done = item.amountToday ?? 0;
    final target = item.targetAmount ?? 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: l10n.removeAmount(item.habit.name),
          child: GestureDetector(
            key: ValueKey('amount-minus-${item.habit.id}'),
            onTap: done > 0 ? onRemove : null,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                M3EIcons.remove_circle_outline,
                size: 22,
                color: done > 0
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.outlineVariant,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            l10n.amountProgress(_fmt(done), _fmt(target)),
            style: theme.typography.baseline.labelMedium.copyWith(
              color: item.checkedToday
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
        Semantics(
          button: true,
          label: l10n.addAmount(item.habit.name),
          child: GestureDetector(
            key: ValueKey('amount-plus-${item.habit.id}'),
            onTap: onAdd,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(M3EIcons.add_circle, size: 24, color: color),
            ),
          ),
        ),
        const SizedBox(width: 6),
        CheckPill(
          checked: item.checkedToday,
          activeColor: color,
          onChanged: (_) => onComplete(),
          semanticLabel: item.checkedToday
              ? l10n.clearGoal(item.habit.name)
              : l10n.completeGoal(item.habit.name),
        ),
      ],
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
