import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/motion/shape_morph.dart';
import '../../core/motion/spring_entrance.dart';
import '../../core/theme/app_surfaces.dart';
import '../../core/widgets/spring_progress.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/providers.dart';
import '../../domain/date_utils.dart';
import '../../domain/enums.dart';
import '../../l10n/generated/app_localizations.dart';
import '../habits/habit_detail_screen.dart';
import '../habits/habit_icons.dart';
import '../habits/habit_providers.dart';
import '../habits/relapse_sheet.dart';
import '../habits/widgets/habit_card.dart';
import '../habits/widgets/streak_odometer.dart';
import '../shell/feature_placeholders.dart';
import '../tasks/task_editor_sheet.dart';
import '../tasks/widgets/check_pill.dart';
import '../tasks/widgets/task_card.dart';
import 'today_providers.dart';
import 'today_view_model.dart';
import 'widgets/confetti_overlay.dart';
import 'widgets/floating_pills.dart';
import 'widgets/today_progress_ring.dart';

/// The Today dashboard: greeting + progress ring, then overdue → habits due →
/// tasks due → done-today, with a FAB menu for creation and an all-done
/// celebration.
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  int _confettiToken = 0;
  bool _wasAllDone = false;
  bool _showPaused = false;

  /// Banner copy reflects the period's scope (v0.7).
  String _vacationBannerMessage(
    VacationPeriod? period,
    List<VacationScope> scopes,
  ) {
    final l10n = AppLocalizations.of(context);
    if (period == null || period.allHabits) return l10n.vacationBanner;
    final routines = ref.read(allRoutinesProvider).value ?? const <Routine>[];
    final habits = ref.read(activeHabitsProvider).value ?? const <Habit>[];
    final names = <String>[];
    for (final scope in scopes) {
      if (scope.periodUuid != period.uuid) continue;
      if (scope.targetKind == VacationTargetKind.routine) {
        final routine = routines.cast<Routine?>().firstWhere(
          (r) => r?.uuid == scope.targetUuid,
          orElse: () => null,
        );
        if (routine != null) names.add(routine.name);
      } else {
        final habit = habits.cast<Habit?>().firstWhere(
          (h) => h?.uuid == scope.targetUuid,
          orElse: () => null,
        );
        if (habit != null) names.add(habit.name);
      }
    }
    return names.isEmpty
        ? l10n.vacationBanner
        : l10n.vacationSummarySome(names.join(', '));
  }

  Future<void> _logRelapse(int habitId) async {
    final note = await showRelapseDialog(context);
    if (note == null) return;
    await ref
        .read(habitRepositoryProvider)
        .logRelapse(
          habitId,
          formatDate(DateTime.now()),
          note: note.isEmpty ? null : note,
        );
    if (!mounted) return;
    M3ESnackbar.show(
      context,
      message: AppLocalizations.of(context).relapseLogged,
    );
  }

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
    final periods =
        ref.watch(vacationPeriodsProvider).value ?? const <VacationPeriod>[];
    final scopes =
        ref.watch(vacationScopesProvider).value ?? const <VacationScope>[];
    final todayKey = formatDate(DateTime.now());
    final activePeriod = periods.cast<VacationPeriod?>().firstWhere(
      (p) =>
          p != null &&
          p.startDate.compareTo(todayKey) <= 0 &&
          todayKey.compareTo(p.endDate) <= 0,
      orElse: () => null,
    );
    final onVacation = activePeriod != null;
    final allHabits = ref.watch(activeHabitsProvider).value ?? const <Habit>[];
    final pausedIds = ref.watch(pausedTodayHabitIdsProvider);
    final pausedHabits = allHabits
        .where((h) => pausedIds.contains(h.id))
        .toList();
    final quitHabits = allHabits
        .where((h) => h.kind == HabitKind.quit && !pausedIds.contains(h.id))
        .toList();

    // Fire the celebration once per transition into the all-done state.
    if (vm.allDone && !_wasAllDone) {
      _confettiToken++;
      HapticFeedback.mediumImpact();
    }
    _wasAllDone = vm.allDone;

    final now = DateTime.now();
    // The flexible app bar's collapsed title block has a fixed height; at
    // large system text the subtitle would overflow it. Keep the date on the
    // dashboard instead when scaling is high.
    final showBarSubtitle = MediaQuery.textScalerOf(context).scale(1.0) <= 1.3;
    return Scaffold(
      // The shell paints the shared ambient backdrop behind the branch.
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    // M3 large flexible app bar: the date is the page subtitle,
                    // and the bar compresses to a small one while scrolling.
                    M3EAppBar.sliver(
                      // Let the shell's ambient backdrop show through the bar;
                      // the package keeps this color at rest and on scroll.
                      backgroundColor: Colors.transparent,
                      titleText: l10n.navToday,
                      subtitleText: showBarSubtitle
                          ? _dateLabel(l10n, now)
                          : null,
                      variant: showBarSubtitle
                          ? M3EAppBarVariant.largeFlexible
                          : M3EAppBarVariant.small,
                      actions: const [SearchAction(), SettingsAction()],
                    ),
                    // M3 layout-grid margins: 16dp compact, 24dp from the
                    // medium breakpoint the shell uses for its nav rail.
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: MediaQuery.sizeOf(context).width >= 600
                            ? 24
                            : 16,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _Header(
                            vm: vm,
                            theme: theme,
                            now: now,
                            showDate: !showBarSubtitle,
                          ),
                          const SizedBox(height: 20),
                          if (onVacation) ...[
                            _VacationBanner(
                              theme: theme,
                              message: _vacationBannerMessage(
                                activePeriod,
                                scopes,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (vm.total == 0 && quitHabits.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 32),
                              // Creation lives in the persistent FAB menu; a
                              // second "new task" target here would duplicate
                              // the same primary action for assistive tech.
                              child: FloatingPills(
                                icon: M3EIcons.wb_twilight,
                                message: l10n.todayEmpty,
                              ),
                            )
                          else ...[
                            if (vm.allDone) ...[
                              SpringEntrance(
                                key: const ValueKey('today-all-done-banner'),
                                index: 0,
                                rise: 12,
                                child: _AllDoneBanner(theme: theme),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (vm.overdueTasks.isNotEmpty) ...[
                              _entrancedSection(0, 'overdue', [
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
                                      onTap: () =>
                                          showTaskEditor(context, task: task),
                                      onToggleComplete: () => _toggleTask(task),
                                    ),
                                  ),
                                const SizedBox(height: 12),
                              ]),
                            ],
                            if (vm.habits.isNotEmpty) ...[
                              _entrancedSection(1, 'habits', [
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
                                      key: ValueKey(
                                        'today-habit-${item.habit.id}',
                                      ),
                                      item: item,
                                      onToggle: () => _toggleHabit(item),
                                      onAddAmount: () => _addAmount(item),
                                      onRemoveAmount: () => _removeAmount(item),
                                      onCompleteGoal: () => _completeGoal(item),
                                    ),
                                  ),
                                const SizedBox(height: 12),
                              ]),
                            ],
                            if (quitHabits.isNotEmpty) ...[
                              _entrancedSection(2, 'quit', [
                                _SectionHeader(
                                  title: l10n.kindQuit,
                                  count: quitHabits.length,
                                  color: theme.colorScheme.tertiary,
                                  theme: theme,
                                ),
                                for (final habit in quitHabits)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: HabitCard(
                                      key: ValueKey('today-quit-${habit.id}'),
                                      habit: habit,
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => HabitDetailScreen(
                                            habitId: habit.id,
                                          ),
                                        ),
                                      ),
                                      onCheckIn: () {},
                                      onLogRelapse: () => _logRelapse(habit.id),
                                    ),
                                  ),
                                const SizedBox(height: 12),
                              ]),
                            ],
                            if (pausedHabits.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Semantics(
                                button: true,
                                label: l10n.a11yExpandPaused,
                                child: ListTile(
                                  key: const ValueKey(
                                    'today-paused-disclosure',
                                  ),
                                  leading: Icon(
                                    M3EIcons.beach_access,
                                    color: theme.colorScheme.primary,
                                  ),
                                  title: Text(
                                    l10n.todayPausedCount(pausedHabits.length),
                                  ),
                                  trailing: Icon(
                                    _showPaused
                                        ? M3EIcons.expand_less
                                        : M3EIcons.expand_more,
                                  ),
                                  onTap: () => setState(
                                    () => _showPaused = !_showPaused,
                                  ),
                                ),
                              ),
                              if (_showPaused)
                                for (final habit in pausedHabits)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      key: ValueKey('today-paused-${habit.id}'),
                                      leading: Icon(
                                        habitIconForKey(habit.iconKey),
                                        // Raw brand colors are ~1.7-2.4:1 on
                                        // surface; a role color meets 3:1.
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                      title: Text(habit.name),
                                      subtitle: Text(l10n.todayPaused),
                                    ),
                                  ),
                            ],
                            if (vm.dueTodayTasks.isNotEmpty) ...[
                              _entrancedSection(3, 'due', [
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
                                      onTap: () =>
                                          showTaskEditor(context, task: task),
                                      onToggleComplete: () => _toggleTask(task),
                                    ),
                                  ),
                                const SizedBox(height: 12),
                              ]),
                            ],
                            if (vm.completedTodayTasks.isNotEmpty) ...[
                              _entrancedSection(4, 'done', [
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
                                      onTap: () =>
                                          showTaskEditor(context, task: task),
                                      onToggleComplete: () => _toggleTask(task),
                                    ),
                                  ),
                              ]),
                            ],
                          ],
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
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
      // One FAB for Today's primary action: create a task due today. M3 uses a
      // FAB menu only when several kinds of action belong to the button; "New
      // habit" stays on the Habits destination, so a plain FAB fits every width.
      floatingActionButton: M3EFab(
        icon: const Icon(M3EIcons.add),
        tooltip: l10n.newTask,
        onPressed: () => showTaskEditor(
          context,
          // Prefill the date only; 09:00 is the editor's own default time.
          initialDueAt: DateTime(now.year, now.month, now.day, 9),
        ),
      ),
    );
  }
}

/// Wraps one dashboard section in a bounded spring entrance. Index is fixed
/// per section (not by position) so state persists when other sections appear
/// or disappear as data changes.
Widget _entrancedSection(int index, String name, List<Widget> children) {
  return SpringEntrance(
    key: ValueKey('today-section-$name'),
    index: index,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

/// Date label used as the large flexible app bar's subtitle.
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

/// The dashboard hero: greeting, progress copy, and the spring ring. The date
/// moved into the app bar subtitle, so this block stays compact while the bar
/// collapses on scroll.
class _Header extends StatelessWidget {
  const _Header({
    required this.vm,
    required this.theme,
    required this.now,
    this.showDate = false,
  });

  final TodayViewModel vm;
  final M3EThemeData theme;
  final DateTime now;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final h = now.hour;
    final greeting = h < 5
        ? l10n.greetingUpLate
        : h < 12
        ? l10n.greetingMorning
        : h < 17
        ? l10n.greetingAfternoon
        : h < 22
        ? l10n.greetingEvening
        : l10n.greetingWindingDown;
    // Keep the ring on the trailing edge at every width; the greeting wraps in
    // the Expanded column instead. Cap the diameter to a share of the card's
    // content width. M3 circular indicators top out at 240dp.
    // From M3: cards use a 12dp corner radius and 16dp left/right padding
    // (containment.md). My design decision: match that with 16dp top/bottom.
    return M3ECard(
      variant: M3ECardVariant.filled,
      padding: const EdgeInsets.all(16),
      // Let the card grow with text that scales up to 2x on a small phone.
      expanded: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1.0);
          final stacked = textScale > 1.3 || constraints.maxWidth < 360;
          final maxRing = math.min(
            240.0,
            constraints.maxWidth * (stacked ? 0.5 : 0.45),
          );
          final ringSize = math.max(96.0, math.min(132 * textScale, maxRing));
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: theme.typography.emphasized.titleMedium.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (showDate) ...[
                const SizedBox(height: 4),
                Text(
                  _dateLabel(l10n, now),
                  style: theme.typography.emphasized.titleMedium,
                ),
              ],
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
          );
          final ring = TodayProgressRing(
            progress: vm.progress,
            done: vm.done,
            total: vm.total,
            celebrate: vm.allDone,
            size: ringSize,
          );
          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 12),
              ring,
            ],
          );
        },
      ),
    );
  }
}

class _VacationBanner extends StatelessWidget {
  const _VacationBanner({required this.theme, required this.message});

  final M3EThemeData theme;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: message,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppShape.hero),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            M3EShapeContainer(
              kind: M3EShapeKind.cookie6Sided,
              width: 40,
              height: 40,
              color: theme.colorScheme.primary,
              child: Icon(
                M3EIcons.beach_access,
                size: 20,
                color: theme.colorScheme.onPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                message,
                style: theme.typography.emphasized.titleMedium.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
        borderRadius: BorderRadius.circular(AppShape.hero),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          // M3 shape tension: a short rectangular accent against rounded rows
          // marks the section without putting a decorative shape behind text.
          ExcludeSemantics(
            child: Container(
              width: 6,
              height: 18,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppShape.xsmall),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.typography.emphasized.titleSmall.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppShape.pill),
            ),
            child: Text(
              '$count',
              style: theme.typography.emphasized.labelSmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
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
      // M3 filled cards keep surfaceContainerHighest; a low-alpha accent wash
      // adds identity without changing the foreground role.
      color: item.checkedToday
          ? null
          : AppSurfaces.tint(theme.colorScheme, color),
      border: item.checkedToday
          ? null
          : BorderSide(color: AppSurfaces.accentBorder(color)),
      // M3 card left/right padding is 16dp.
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          MorphingShape(
            from: M3EShapeKind.cookie6Sided,
            to: M3EShapeKind.cookie9Sided,
            active: item.checkedToday,
            size: 38,
            color: color.withValues(alpha: 0.18),
            activeColor: color.withValues(alpha: 0.28),
            childBuilder: (t) => Icon(
              habitIconForKey(habit.iconKey),
              size: 19 * (0.96 + 0.04 * t),
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
                    semanticLabel: l10n.amountProgress(
                      _formatAmount(item.amountToday ?? 0),
                      _formatAmount(item.targetAmount ?? 1),
                    ),
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

/// Formats a measurable amount without a trailing ".0".
String _formatAmount(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Spring-animated circular progress ring for a measurable habit (0…1 of goal).
class _AmountBar extends StatelessWidget {
  const _AmountBar({required this.progress, required this.semanticLabel});

  final double progress;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    // M3 circular determinate indicator: 40dp ring, 4dp active/track thickness
    // and a 4dp arc-to-track gap. A flat ring is thinner than the wavy linear
    // bar's 10dp wave height and has no broken wave ends. Per-entity identity
    // stays in the habit icon/card wash; the active fill uses the primary role
    // so it meets 3:1 on the track. The wrapper springs the fill to each amount.
    return SpringWavyProgressBar(
      circular: true,
      value: progress.clamp(0.0, 1.0).toDouble(),
      color: theme.colorScheme.primary,
      semanticsLabel: semanticLabel,
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

  String _fmt(double v) => _formatAmount(v);

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
            // 48dp target: the 22dp icon is centered inside a full touch area.
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
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
            // 48dp target for the constructive action as well.
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: Icon(
                  M3EIcons.add_circle,
                  size: 24,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
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
