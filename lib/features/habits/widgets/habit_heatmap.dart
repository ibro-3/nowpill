import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:motor/motor.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_scheme_provider.dart';
import '../../../domain/date_utils.dart';
import '../../../domain/enums.dart';
import '../../../domain/habit_schedule.dart';
import '../../../domain/heatmap.dart';
import '../../../domain/streak_engine.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'heatmap_semantics.dart';

export '../../../domain/heatmap.dart' show HeatmapDayState;

/// A monthly check-in heatmap. Columns are weeks (Monday-start), rows are
/// weekdays. Cells pop in with a stagger and morph on backfill taps.
class HabitHeatmap extends StatefulWidget {
  const HabitHeatmap({
    required this.month,
    required this.checkins,
    required this.streak,
    required this.schedule,
    required this.startDate,
    required this.color,
    required this.onToggleDay,
    this.targetAmount,
    this.amounts = const {},
    this.kind = HabitKind.build,
    this.relapses = const {},
    this.pausedDates = const {},
    super.key,
  });

  /// Any day within the month to display.
  final DateTime month;

  /// Checked-in dates (`yyyy-MM-dd`).
  final Set<String> checkins;

  final StreakResult streak;
  final HabitSchedule schedule;

  /// The habit's creation day (local).
  final DateTime startDate;

  /// The habit's brand color.
  final Color color;

  /// Called when a backfillable day is tapped.
  final ValueChanged<DateTime> onToggleDay;

  /// Numeric daily goal for measurable habits (null = classic).
  final double? targetAmount;

  /// Logged amounts per day for measurable habits.
  final Map<String, double> amounts;

  /// Quit habits render clean/relapsed days instead of check-ins.
  final HabitKind kind;

  /// Days with a logged relapse (`yyyy-MM-dd`).
  final Set<String> relapses;

  /// Days inside a planned vacation (`yyyy-MM-dd`).
  final Set<String> pausedDates;

  @override
  State<HabitHeatmap> createState() => _HabitHeatmapState();
}

class _HabitHeatmapState extends State<HabitHeatmap>
    with SingleTickerProviderStateMixin {
  late final SingleMotionController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = SingleMotionController(
      motion: MotionTokens.expressive.spatialSlow,
      vsync: this,
      initialValue: 0,
    )..animateTo(1);
  }

  @override
  void didUpdateWidget(HabitHeatmap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month.year != widget.month.year ||
        oldWidget.month.month != widget.month.month) {
      _entrance
        ..value = 0
        ..animateTo(1);
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  bool _canBackfill(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = daysBetween(day, today);
    return diff >= 0 &&
        diff <= 30 &&
        !day.isBefore(_dateOnly(widget.startDate));
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  HeatmapDayState _stateFor(DateTime day) {
    return heatmapDayState(
      day: day,
      today: DateTime.now(),
      startDate: widget.startDate,
      schedule: widget.schedule,
      checkins: widget.checkins,
      frozenDates: widget.streak.frozenDates,
      targetAmount: widget.targetAmount,
      amounts: widget.amounts,
      kind: widget.kind,
      relapses: widget.relapses,
      pausedDates: widget.pausedDates,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final tokens = MotionScope.of(context);
    _entrance.motion = tokens.spatialSlow;

    final first = DateTime(widget.month.year, widget.month.month, 1);
    final daysInMonth = DateTime(
      widget.month.year,
      widget.month.month + 1,
      0,
    ).day;
    // Grid starts on the Monday of the week containing the 1st.
    final gridStart = startOfWeek(first);
    final totalCells = ((daysInMonth + first.weekday - 1) / 7).ceil() * 7;

    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, _) {
        final entrance = _entrance.value.clamp(0.0, 1.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final label in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: theme.typography.baseline.labelSmall.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: totalCells,
              itemBuilder: (context, i) {
                final day = gridStart.add(Duration(days: i));
                final inMonth = day.month == widget.month.month;
                // Stagger by cell index.
                final delay = (i / totalCells) * 0.5;
                final local = ((entrance - delay) / (1 - delay)).clamp(
                  0.0,
                  1.0,
                );
                return _HeatmapCell(
                  day: day,
                  inMonth: inMonth,
                  state: _stateFor(day),
                  color: widget.color,
                  entrance: local,
                  backfillable: inMonth && _canBackfill(day),
                  onTap: () => widget.onToggleDay(day),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _HeatmapCell extends StatefulWidget {
  const _HeatmapCell({
    required this.day,
    required this.inMonth,
    required this.state,
    required this.color,
    required this.entrance,
    required this.backfillable,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final HeatmapDayState state;
  final Color color;
  final double entrance;
  final bool backfillable;
  final VoidCallback onTap;

  @override
  State<_HeatmapCell> createState() => _HeatmapCellState();
}

class _HeatmapCellState extends State<_HeatmapCell>
    with SingleTickerProviderStateMixin {
  late final SingleMotionController _pop;
  late HeatmapDayState _from;

  @override
  void initState() {
    super.initState();
    _from = widget.state;
    _pop = SingleMotionController(
      motion: MotionTokens.expressive.effectsFast,
      vsync: this,
      initialValue: 1,
    );
  }

  @override
  void didUpdateWidget(_HeatmapCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _from = oldWidget.state;
      _pop
        ..value = 0
        ..animateTo(1);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  ({Color fill, Color border, Widget? child}) _palette(
    HeatmapDayState state,
  ) {
    final theme = M3ETheme.of(context);
    switch (state) {
      case HeatmapDayState.done:
        return (
          fill: widget.color,
          border: widget.color,
          child: Icon(
            M3EIcons.check,
            size: 14,
            color: theme.colorScheme.onPrimary,
          ),
        );
      case HeatmapDayState.partial:
        return (
          fill: widget.color.withValues(alpha: 0.35),
          border: widget.color.withValues(alpha: 0.7),
          child: null,
        );
      case HeatmapDayState.frozen:
        return (
          fill: theme.colorScheme.tertiaryContainer,
          border: theme.colorScheme.tertiary,
          child: Icon(
            M3EIcons.ac_unit,
            size: 14,
            color: theme.colorScheme.onTertiaryContainer,
          ),
        );
      case HeatmapDayState.missed:
        return (
          fill: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
          border: theme.colorScheme.error.withValues(alpha: 0.5),
          child: Icon(
            M3EIcons.close,
            size: 12,
            color: theme.colorScheme.error,
          ),
        );
      case HeatmapDayState.todayPending:
        return (
          fill: theme.colorScheme.surfaceContainerHigh,
          border: widget.color,
          child: null,
        );
      case HeatmapDayState.unscheduled:
        return (
          fill: theme.colorScheme.surfaceContainerLow,
          border: theme.colorScheme.outlineVariant,
          child: null,
        );
      case HeatmapDayState.inactive:
        return (
          fill: theme.colorScheme.surfaceContainerLowest,
          border: const Color(0x00000000),
          child: null,
        );
      case HeatmapDayState.relapsed:
        return (
          fill: theme.colorScheme.errorContainer,
          border: theme.colorScheme.error,
          child: Icon(
            M3EIcons.close,
            size: 14,
            color: theme.colorScheme.onErrorContainer,
          ),
        );
      case HeatmapDayState.paused:
        return (
          fill: theme.colorScheme.surfaceContainerHigh,
          border: theme.colorScheme.outline.withValues(alpha: 0.7),
          child: null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = MotionScope.of(context);
    _pop.motion = tokens.effectsFast;

    final t = _pop.value.clamp(0.0, 1.0);
    final from = _palette(_from);
    final to = _palette(widget.state);
    final fill = Color.lerp(from.fill, to.fill, t)!;
    final border = Color.lerp(from.border, to.border, t)!;
    // One springy pop on state change, multiplied by the entrance stagger.
    final pop = 1 + 0.10 * (4 * t * (1 - t));
    final scale = (0.6 + 0.4 * widget.entrance) * pop;
    final opacity = widget.entrance.clamp(0.0, 1.0);

    final cell = Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: widget.inMonth ? opacity : opacity * 0.25,
        child: Container(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border, width: 1.2),
          ),
          child: Center(child: to.child),
        ),
      ),
    );

    final l10n = AppLocalizations.of(context);
    final label =
        '${formatDate(widget.day)}, ${heatmapStateLabel(l10n, widget.state)}';
    if (!widget.backfillable) {
      return Semantics(container: true, label: label, child: cell);
    }
    return Semantics(
      button: true,
      label: label,
      onTap: widget.onTap,
      child: GestureDetector(
        key: ValueKey('heatmap-${formatDate(widget.day)}'),
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: MouseRegion(cursor: SystemMouseCursors.click, child: cell),
      ),
    );
  }
}
