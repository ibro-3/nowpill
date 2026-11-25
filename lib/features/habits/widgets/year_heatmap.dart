import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:motor/motor.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_scheme_provider.dart';
import '../../../core/theme/app_surfaces.dart';
import '../../../domain/date_utils.dart';
import '../../../domain/enums.dart';
import '../../../domain/habit_schedule.dart';
import '../../../domain/heatmap.dart';
import '../../../domain/streak_engine.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'heatmap_semantics.dart';

/// A trailing-year check-in heatmap (GitHub-style): 53 Monday-start week
/// columns × 7 weekday rows, ending with the current week. Brand-color
/// intensity per day state; the same states (and tap-backfill rules) as the
/// month grid. The whole grid fades in as one — no per-cell springs for 371
/// cells.
class YearHeatmap extends StatefulWidget {
  const YearHeatmap({
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

  final Set<String> checkins;
  final StreakResult streak;
  final HabitSchedule schedule;
  final DateTime startDate;
  final Color color;
  final ValueChanged<DateTime> onToggleDay;
  final double? targetAmount;
  final Map<String, double> amounts;
  final HabitKind kind;
  final Set<String> relapses;
  final Set<String> pausedDates;

  @override
  State<YearHeatmap> createState() => _YearHeatmapState();
}

class _YearHeatmapState extends State<YearHeatmap>
    with SingleTickerProviderStateMixin {
  late final SingleMotionController _entrance;

  @override
  void initState() {
    super.initState();
    // The year overview only fades in; opacity is an effect, not a spatial
    // transform. No per-cell springs for 371 cells.
    _entrance = SingleMotionController(
      motion: MotionTokens.expressive.effectsSlow,
      vsync: this,
      initialValue: 0,
    )..animateTo(1);
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
    final start = DateTime(
      widget.startDate.year,
      widget.startDate.month,
      widget.startDate.day,
    );
    return diff >= 0 && diff <= 30 && !day.isBefore(start);
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final tokens = MotionScope.of(context);
    _entrance.motion = tokens.effectsSlow;

    final now = DateTime.now();
    final weeks = yearHeatmapWeeks(
      today: now,
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

    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, _) {
        final opacity = _entrance.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 53 columns + gaps fit the available width; cells stay square.
              const gap = 2.0;
              final cell = ((constraints.maxWidth - gap * 52) / 53)
                  .floorToDouble();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MonthLabels(
                    weeks: weeks,
                    cell: cell,
                    gap: gap,
                    theme: theme,
                  ),
                  const SizedBox(height: 4),
                  // Individual year cells are only a few dp wide — far below
                  // M3's 48dp target. Make the whole grid the gesture target
                  // and map the tap position to a day instead of giving each
                  // square its own tiny GestureDetector.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) {
                      final pitch = cell + gap;
                      final w = (details.localPosition.dx / pitch)
                          .floor()
                          .clamp(0, weeks.length - 1);
                      final d = (details.localPosition.dy / pitch)
                          .floor()
                          .clamp(0, 6);
                      final day = weeks[w].monday.add(Duration(days: d));
                      if (_canBackfill(day)) widget.onToggleDay(day);
                    },
                    child: SizedBox(
                      height: cell * 7 + gap * 6,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var w = 0; w < weeks.length; w++) ...[
                            if (w > 0) const SizedBox(width: gap),
                            Column(
                              children: [
                                for (var d = 0; d < 7; d++) ...[
                                  if (d > 0) const SizedBox(height: gap),
                                  _YearCell(
                                    day: weeks[w].monday.add(Duration(days: d)),
                                    state: weeks[w].states[d],
                                    color: widget.color,
                                    size: cell,
                                    backfillable: _canBackfill(
                                      weeks[w].monday.add(Duration(days: d)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Month initials above the week column where the month's first day falls.
class _MonthLabels extends StatelessWidget {
  const _MonthLabels({
    required this.weeks,
    required this.cell,
    required this.gap,
    required this.theme,
  });

  final List<YearHeatmapWeek> weeks;
  final double cell;
  final double gap;
  final M3EThemeData theme;

  @override
  Widget build(BuildContext context) {
    const months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
    // Label a column when it contains the 1st of a month (or the first
    // column, so the grid never starts unlabeled).
    final labels = <int, String>{};
    for (var w = 0; w < weeks.length; w++) {
      final monday = weeks[w].monday;
      for (var d = 0; d < 7; d++) {
        final day = monday.add(Duration(days: d));
        if (day.day == 1) {
          labels[w] = months[day.month - 1];
          break;
        }
      }
    }
    labels.putIfAbsent(0, () => months[weeks.first.monday.month - 1]);

    return SizedBox(
      height: 12,
      child: Stack(
        children: [
          for (final entry in labels.entries)
            Positioned(
              left: entry.key * (cell + gap),
              child: Text(
                entry.value,
                style: theme.typography.baseline.labelSmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _YearCell extends StatelessWidget {
  const _YearCell({
    required this.day,
    required this.state,
    required this.color,
    required this.size,
    required this.backfillable,
  });

  final DateTime day;
  final HeatmapDayState state;
  final Color color;
  final double size;
  final bool backfillable;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    Color fill;
    switch (state) {
      case HeatmapDayState.done:
        fill = color;
      case HeatmapDayState.partial:
        fill = color.withValues(alpha: 0.4);
      case HeatmapDayState.frozen:
        fill = theme.colorScheme.tertiary.withValues(alpha: 0.55);
      case HeatmapDayState.missed:
        fill = theme.colorScheme.error.withValues(alpha: 0.25);
      case HeatmapDayState.todayPending:
        fill = color.withValues(alpha: 0.15);
      case HeatmapDayState.unscheduled:
        fill = theme.colorScheme.surfaceContainerHighest;
      case HeatmapDayState.inactive:
        fill = theme.colorScheme.surfaceContainerLow;
      case HeatmapDayState.relapsed:
        fill = theme.colorScheme.error.withValues(alpha: 0.7);
      case HeatmapDayState.paused:
        fill = theme.colorScheme.outline.withValues(alpha: 0.2);
    }

    final cell = Container(
      key: backfillable ? ValueKey('year-heatmap-${formatDate(day)}') : null,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        // Only scale steps: 0 for tiny cells, 4dp (extra small) otherwise.
        borderRadius: BorderRadius.circular(size >= 8 ? AppShape.xsmall : 0),
        border: state == HeatmapDayState.todayPending
            ? Border.all(color: color, width: 1)
            : null,
      ),
    );

    // Cells are visual marks with labels; the enclosing grid owns the single
    // gesture target. Screen readers can use the month grid for per-day edits.
    final l10n = AppLocalizations.of(context);
    final label = '${formatDate(day)}, ${heatmapStateLabel(l10n, state)}';
    return Semantics(container: true, label: label, child: cell);
  }
}
