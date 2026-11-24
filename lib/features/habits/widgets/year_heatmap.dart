import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:motor/motor.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_scheme_provider.dart';
import '../../../domain/date_utils.dart';
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

  @override
  State<YearHeatmap> createState() => _YearHeatmapState();
}

class _YearHeatmapState extends State<YearHeatmap>
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
    _entrance.motion = tokens.spatialSlow;

    final now = DateTime.now();
    final weeks = yearHeatmapWeeks(
      today: now,
      startDate: widget.startDate,
      schedule: widget.schedule,
      checkins: widget.checkins,
      frozenDates: widget.streak.frozenDates,
      targetAmount: widget.targetAmount,
      amounts: widget.amounts,
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
                  SizedBox(
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
                                  onTap: widget.onToggleDay,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
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
                  fontSize: 9,
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
    required this.onTap,
  });

  final DateTime day;
  final HeatmapDayState state;
  final Color color;
  final double size;
  final bool backfillable;
  final ValueChanged<DateTime> onTap;

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
    }

    final cell = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(2),
        border: state == HeatmapDayState.todayPending
            ? Border.all(color: color, width: 1)
            : null,
      ),
    );

    final l10n = AppLocalizations.of(context);
    final label = '${formatDate(day)}, ${heatmapStateLabel(l10n, state)}';
    if (!backfillable) {
      return Semantics(container: true, label: label, child: cell);
    }
    return Semantics(
      button: true,
      label: label,
      onTap: () => onTap(day),
      child: GestureDetector(
        key: ValueKey('year-heatmap-${formatDate(day)}'),
        onTap: () => onTap(day),
        behavior: HitTestBehavior.opaque,
        child: MouseRegion(cursor: SystemMouseCursors.click, child: cell),
      ),
    );
  }
}
