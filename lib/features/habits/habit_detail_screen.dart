import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/repositories/providers.dart';
import '../../domain/date_utils.dart';
import '../../domain/enums.dart';
import '../../domain/streak_engine.dart';
import '../../l10n/generated/app_localizations.dart';
import 'habit_editor_sheet.dart';
import 'habit_icons.dart';
import 'habit_providers.dart';
import 'relapse_sheet.dart';
import 'widgets/habit_heatmap.dart';
import 'widgets/token_wallet.dart';
import 'widgets/year_heatmap.dart';

/// The user's choice when tapping a missed day in manual freeze mode.
enum _DayChoice { cancel, freeze, backfill }

/// Which heatmap range the detail screen shows.
enum _HeatmapRange { month, year }

/// Habit detail: monthly heatmap with backfill, streak stats, token wallet,
/// and archive / delete actions.
class HabitDetailScreen extends ConsumerStatefulWidget {
  const HabitDetailScreen({required this.habitId, super.key});

  final int habitId;

  @override
  ConsumerState<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends ConsumerState<HabitDetailScreen> {
  late DateTime _month;
  _HeatmapRange _range = _HeatmapRange.month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  Future<void> _toggleDay(DateTime day) async {
    final repo = ref.read(habitRepositoryProvider);
    final habit = ref.read(habitProvider(widget.habitId)).value;
    if (habit == null) return;
    final key = formatDate(day);

    if (habit.kind == HabitKind.quit) {
      // Tapping a clean day logs a relapse; tapping it again removes the
      // entry. Paused days are neutral and cannot be toggled.
      if (ref
          .read(pausedDaysProvider(habit.createdAt.toLocal()))
          .contains(key)) {
        return;
      }
      final relapses =
          ref.read(habitRelapsesProvider(widget.habitId)).value ?? const [];
      final existing = relapses.where((r) => r.date == key).firstOrNull;
      if (existing != null) {
        await repo.removeRelapse(widget.habitId, key);
      } else {
        final note = await showRelapseDialog(context);
        if (note == null) return;
        await repo.logRelapse(
          widget.habitId,
          key,
          note: note.isEmpty ? null : note,
        );
      }
      return;
    }

    final checkins =
        ref.read(habitCheckinsProvider(widget.habitId)).value ?? const [];
    final freezes =
        ref.read(habitFreezesProvider(widget.habitId)).value ?? const [];
    final schedule = ref.read(habitScheduleProvider(widget.habitId));
    // Weekly-target freezes are stored under the week's Monday.
    final freezeKey = schedule.isDayBased ? key : formatDate(startOfWeek(day));

    // A real check-in always wins: tapping a checked day removes it.
    if (checkins.any((c) => c.date == key)) {
      await repo.removeCheckIn(widget.habitId, key);
      return;
    }

    final isManual = habit.freezeMode == FreezeMode.manual;
    final frozen = freezes.any((f) => f.date == freezeKey);

    if (isManual && frozen) {
      // Tapping a frozen day removes the freeze (refund).
      await repo.removeFreeze(widget.habitId, freezeKey);
      return;
    }

    if (isManual) {
      // Offer a choice: backfill a real check-in, or spend a token to freeze.
      final streak = ref.read(habitStreakProvider(widget.habitId));
      final choice = await _showFreezeChoice(canFreeze: streak.tokens > 0);
      switch (choice) {
        case _DayChoice.backfill:
          // Backfill counts as full completion (measurable: the whole goal).
          await repo.checkIn(widget.habitId, key, amount: habit.targetAmount);
        case _DayChoice.freeze:
          await repo.placeFreeze(widget.habitId, freezeKey);
        case _DayChoice.cancel:
          break;
      }
      return;
    }

    // Auto mode: tap toggles a backfill check-in (full goal for measurable).
    await repo.checkIn(widget.habitId, key, amount: habit.targetAmount);
  }

  Future<_DayChoice> _showFreezeChoice({required bool canFreeze}) async {
    final l10n = AppLocalizations.of(context);
    final result = await M3EDialog.show<_DayChoice>(
      context,
      dialog: M3EDialog(
        title: l10n.dayMissedTitle,
        content: Text(
          canFreeze ? l10n.dayMissedCanFreeze : l10n.dayMissedNoToken,
        ),
        actions: [
          M3EButton(
            key: const ValueKey('day-cancel'),
            style: M3EButtonStyle.text,
            onPressed: () => Navigator.of(context).pop(_DayChoice.cancel),
            label: Text(l10n.cancel),
          ),
          if (canFreeze)
            M3EButton(
              key: const ValueKey('day-freeze'),
              style: M3EButtonStyle.tonal,
              onPressed: () => Navigator.of(context).pop(_DayChoice.freeze),
              label: Text(l10n.freeze),
            ),
          M3EButton(
            key: const ValueKey('day-backfill'),
            onPressed: () => Navigator.of(context).pop(_DayChoice.backfill),
            label: Text(l10n.backfill),
          ),
        ],
      ),
    );
    return result ?? _DayChoice.cancel;
  }

  Future<void> _logRelapse() async {
    final note = await showRelapseDialog(context);
    if (note == null) return;
    await ref
        .read(habitRepositoryProvider)
        .logRelapse(
          widget.habitId,
          formatDate(DateTime.now()),
          note: note.isEmpty ? null : note,
        );
    if (mounted) {
      M3ESnackbar.show(
        context,
        message: AppLocalizations.of(context).relapseLogged,
      );
    }
  }

  Future<void> _archive() async {
    await ref.read(habitRepositoryProvider).archive(widget.habitId);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await M3EDialog.show<bool>(
      context,
      dialog: M3EDialog(
        title: l10n.deleteHabitTitle,
        content: Text(l10n.deleteHabitBody),
        actions: [
          M3EButton(
            style: M3EButtonStyle.text,
            onPressed: () => Navigator.of(context).pop(false),
            label: Text(l10n.cancel),
          ),
          M3EButton(
            onPressed: () => Navigator.of(context).pop(true),
            label: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(habitRepositoryProvider).delete(widget.habitId);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);
    final habit = ref.watch(habitProvider(widget.habitId)).value;
    if (habit == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final streak = ref.watch(habitStreakProvider(widget.habitId));
    final checkins =
        ref.watch(habitCheckinsProvider(widget.habitId)).value ?? const [];
    final relapses =
        ref.watch(habitRelapsesProvider(widget.habitId)).value ?? const [];
    final paused = ref.watch(pausedDaysProvider(habit.createdAt.toLocal()));
    final schedule = ref.watch(habitScheduleProvider(widget.habitId));
    final isQuit = habit.kind == HabitKind.quit;
    final color = Color(habit.color);
    final unit = schedule.isDayBased ? daysPerToken : weeksPerToken;
    final unitLabel = schedule.isDayBased ? l10n.unitDay : l10n.unitWeek;
    final toNext = unit - (streak.currentStreak % unit);

    return Scaffold(
      appBar: M3EAppBar.top(
        titleText: habit.name,
        leading: M3EIconButton(
          variant: M3EIconButtonVariant.standard,
          icon: const Icon(M3EIcons.arrow_back),
          tooltip: l10n.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          M3EIconButton(
            variant: M3EIconButtonVariant.standard,
            icon: const Icon(M3EIcons.edit),
            tooltip: l10n.editHabit,
            onPressed: () => showHabitEditor(context, habit: habit),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              if (isQuit) ...[
                M3ECard(
                  variant: M3ECardVariant.filled,
                  padding: const EdgeInsets.all(16),
                  child: Semantics(
                    container: true,
                    label: l10n.daysClean(streak.currentStreak),
                    child: Text(
                      l10n.daysClean(streak.currentStreak),
                      style: theme.typography.emphasized.headlineSmall.copyWith(
                        color: color,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              Row(
                children: [
                  M3EShapeContainer(
                    kind: M3EShapeKind.cookie6Sided,
                    width: 56,
                    height: 56,
                    color: color.withValues(alpha: 0.18),
                    child: Icon(
                      habitIconForKey(habit.iconKey),
                      size: 28,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _StatRow(
                          icon: M3EIcons.local_fire_department,
                          label: isQuit
                              ? l10n.habitCleanDays
                              : l10n.currentStreak,
                          value: '${streak.currentStreak}',
                          color: theme.colorScheme.tertiary,
                          theme: theme,
                        ),
                        const SizedBox(height: 4),
                        _StatRow(
                          icon: M3EIcons.emoji_events,
                          label: l10n.bestStreak,
                          value: '${streak.bestStreak}',
                          color: theme.colorScheme.primary,
                          theme: theme,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!isQuit) ...[
                const SizedBox(height: 20),
                M3ECard(
                  variant: M3ECardVariant.filled,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            l10n.freezeTokens,
                            style: theme.typography.emphasized.titleSmall,
                          ),
                          const Spacer(),
                          TokenWallet(tokens: streak.tokens),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        habit.freezeMode == FreezeMode.manual
                            ? (streak.tokens >= maxTokens
                                  ? l10n.walletFullManual
                                  : l10n.walletEarnManual(
                                      unit,
                                      unitLabel,
                                      toNext,
                                    ))
                            : (streak.tokens >= maxTokens
                                  ? l10n.walletFullAuto(unitLabel)
                                  : l10n.walletEarnAuto(
                                      unit,
                                      unitLabel,
                                      toNext,
                                    )),
                        style: theme.typography.baseline.bodySmall.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              M3ESegmentedButton<_HeatmapRange>(
                selected: {_range},
                onSelectionChanged: (s) => setState(() => _range = s.first),
                segments: [
                  M3ESegment(
                    value: _HeatmapRange.month,
                    label: l10n.heatmapMonth,
                  ),
                  M3ESegment(
                    value: _HeatmapRange.year,
                    label: l10n.heatmapYear,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_range == _HeatmapRange.month) ...[
                Row(
                  children: [
                    M3EIconButton(
                      variant: M3EIconButtonVariant.standard,
                      icon: const Icon(M3EIcons.chevron_left),
                      tooltip: l10n.previousMonth,
                      onPressed: () => _shiftMonth(-1),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          _monthLabel(l10n, _month),
                          style: theme.typography.emphasized.titleMedium,
                        ),
                      ),
                    ),
                    M3EIconButton(
                      variant: M3EIconButtonVariant.standard,
                      icon: const Icon(M3EIcons.chevron_right),
                      tooltip: l10n.nextMonth,
                      onPressed: () => _shiftMonth(1),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                HabitHeatmap(
                  month: _month,
                  checkins: checkins.map((c) => c.date).toSet(),
                  streak: streak,
                  schedule: schedule,
                  startDate: habit.createdAt.toLocal(),
                  color: color,
                  onToggleDay: _toggleDay,
                  kind: habit.kind,
                  relapses: relapses.map((r) => r.date).toSet(),
                  pausedDates: paused,
                  targetAmount: habit.targetAmount,
                  amounts: {
                    for (final c in checkins)
                      if (c.amount != null) c.date: c.amount!,
                  },
                ),
              ] else ...[
                Center(
                  child: Text(
                    l10n.yearHeatmapTitle,
                    style: theme.typography.emphasized.titleMedium,
                  ),
                ),
                const SizedBox(height: 12),
                YearHeatmap(
                  checkins: checkins.map((c) => c.date).toSet(),
                  streak: streak,
                  schedule: schedule,
                  startDate: habit.createdAt.toLocal(),
                  color: color,
                  onToggleDay: _toggleDay,
                  kind: habit.kind,
                  relapses: relapses.map((r) => r.date).toSet(),
                  pausedDates: paused,
                  targetAmount: habit.targetAmount,
                  amounts: {
                    for (final c in checkins)
                      if (c.amount != null) c.date: c.amount!,
                  },
                ),
              ],
              const SizedBox(height: 8),
              Text(
                isQuit
                    ? l10n.kindQuitDesc
                    : habit.freezeMode == FreezeMode.manual
                    ? l10n.heatmapHintManual
                    : l10n.heatmapHintAuto,
                style: theme.typography.baseline.labelSmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: isQuit
                        ? M3EButton.icon(
                            key: const ValueKey('log-relapse'),
                            onPressed: _logRelapse,
                            style: M3EButtonStyle.tonal,
                            icon: const Icon(M3EIcons.error),
                            label: Text(l10n.logRelapse),
                          )
                        : M3EButton.icon(
                            onPressed: _archive,
                            style: M3EButtonStyle.tonal,
                            icon: const Icon(M3EIcons.archive),
                            label: Text(l10n.archive),
                          ),
                  ),
                  const SizedBox(width: 12),
                  M3EIconButton(
                    variant: M3EIconButtonVariant.standard,
                    icon: Icon(
                      M3EIcons.delete_forever,
                      color: theme.colorScheme.error,
                    ),
                    tooltip: l10n.deleteHabit,
                    onPressed: _confirmDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _monthLabel(AppLocalizations l10n, DateTime m) {
    final names = [
      l10n.monthJanuary,
      l10n.monthFebruary,
      l10n.monthMarch,
      l10n.monthApril,
      l10n.monthMayFull,
      l10n.monthJune,
      l10n.monthJuly,
      l10n.monthAugust,
      l10n.monthSeptember,
      l10n.monthOctober,
      l10n.monthNovember,
      l10n.monthDecember,
    ];
    return '${names[m.month - 1]} ${m.year}';
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final M3EThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          value,
          style: theme.typography.emphasized.titleLarge.copyWith(color: color),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.typography.baseline.labelMedium.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
