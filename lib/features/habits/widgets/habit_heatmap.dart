import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:motor/motor.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_scheme_provider.dart';
import '../../../domain/date_utils.dart';
import '../../../domain/habit_schedule.dart';
import '../../../domain/streak_engine.dart';

/// The visual state of a single heatmap day.
enum HeatmapDayState {
  /// Checked in.
  done,

  /// A freeze token bridged this missed day.
  frozen,

  /// A scheduled day that was missed (no token).
  missed,

  /// Not a scheduled day.
  unscheduled,

  /// Today, not yet checked (in progress).
  todayPending,

  /// Outside the habit's lifetime or in the future.
  inactive,
}

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
    final today = _dateOnly(DateTime.now());
    final key = formatDate(day);
    if (day.isAfter(today)) return HeatmapDayState.inactive;
    if (day.isBefore(_dateOnly(widget.startDate))) {
      return HeatmapDayState.inactive;
    }
    if (widget.checkins.contains(key)) return HeatmapDayState.done;
    // Weekly-target freezes are stored under the week's Monday; render ❄ on
    // every unchecked day of a frozen week.
    final frozenKey = widget.schedule.isDayBased
        ? key
        : formatDate(startOfWeek(day));
    if (widget.streak.frozenDates.contains(frozenKey)) {
      return HeatmapDayState.frozen;
    }
    if (daysBetween(day, today) == 0) return HeatmapDayState.todayPending;
    // Weekly-target habits never miss individual days — only whole weeks
    // count, so unchecked days stay neutral.
    if (!widget.schedule.isDayBased) return HeatmapDayState.unscheduled;
    if (widget.schedule.isDueOn(day)) return HeatmapDayState.missed;
    return HeatmapDayState.unscheduled;
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

class _HeatmapCell extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final scale = 0.6 + 0.4 * entrance;
    final opacity = entrance.clamp(0.0, 1.0);

    Color fill;
    Color border;
    Widget? child;
    switch (state) {
      case HeatmapDayState.done:
        fill = color;
        border = color;
        child = Icon(
          M3EIcons.check,
          size: 14,
          color: theme.colorScheme.onPrimary,
        );
      case HeatmapDayState.frozen:
        fill = theme.colorScheme.tertiaryContainer;
        border = theme.colorScheme.tertiary;
        child = Icon(
          M3EIcons.ac_unit,
          size: 14,
          color: theme.colorScheme.onTertiaryContainer,
        );
      case HeatmapDayState.missed:
        fill = theme.colorScheme.errorContainer.withValues(alpha: 0.4);
        border = theme.colorScheme.error.withValues(alpha: 0.5);
        child = Icon(M3EIcons.close, size: 12, color: theme.colorScheme.error);
      case HeatmapDayState.todayPending:
        fill = theme.colorScheme.surfaceContainerHigh;
        border = color;
        child = null;
      case HeatmapDayState.unscheduled:
        fill = theme.colorScheme.surfaceContainerLow;
        border = theme.colorScheme.outlineVariant;
        child = null;
      case HeatmapDayState.inactive:
        fill = theme.colorScheme.surfaceContainerLowest;
        border = const Color(0x00000000);
        child = null;
    }

    final cell = Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: inMonth ? opacity : opacity * 0.25,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border, width: 1.2),
          ),
          child: Center(child: child),
        ),
      ),
    );

    if (!backfillable) return cell;
    return GestureDetector(
      key: ValueKey('heatmap-${formatDate(day)}'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(cursor: SystemMouseCursors.click, child: cell),
    );
  }
}
