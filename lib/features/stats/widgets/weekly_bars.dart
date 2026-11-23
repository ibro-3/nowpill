import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import '../../../domain/stats_engine.dart';

/// Weekly completion summary: stacked bars (habits + tasks) for the last 8
/// ISO weeks, with a this-week vs last-week delta hint above.
class WeeklyBars extends StatelessWidget {
  const WeeklyBars({
    required this.weeks,
    required this.thisWeekTotal,
    required this.lastWeekTotal,
    super.key,
  });

  final List<WeekSummary> weeks;
  final int thisWeekTotal;
  final int lastWeekTotal;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final scheme = theme.colorScheme;
    if (weeks.isEmpty) return const SizedBox.shrink();

    final maxY = _niceMax(
      weeks.fold<int>(0, (m, w) => w.total > m ? w.total : m),
    );
    final labelStyle = theme.typography.baseline.labelSmall.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DeltaHint(
          theme: theme,
          thisWeek: thisWeekTotal,
          lastWeek: lastWeekTotal,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              barTouchData: const BarTouchData(enabled: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY / 3,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: maxY / 3,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(value.toInt().toString(), style: labelStyle),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= weeks.length) {
                        return const SizedBox.shrink();
                      }
                      final w = weeks[i].weekStart;
                      return SideTitleWidget(
                        meta: meta,
                        child: Text('${w.month}/${w.day}', style: labelStyle),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < weeks.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: weeks[i].total.toDouble(),
                        width: 16,
                        borderRadius: BorderRadius.circular(5),
                        rodStackItems: [
                          BarChartRodStackItem(
                            0,
                            weeks[i].habitCheckins.toDouble(),
                            scheme.primary,
                          ),
                          BarChartRodStackItem(
                            weeks[i].habitCheckins.toDouble(),
                            weeks[i].total.toDouble(),
                            scheme.tertiary,
                          ),
                        ],
                        color: scheme.primary,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  double _niceMax(int maxValue) {
    if (maxValue <= 3) return 3;
    final step = maxValue <= 6 ? 2 : (maxValue / 3).ceil();
    return (step * 3).toDouble();
  }
}

class _DeltaHint extends StatelessWidget {
  const _DeltaHint({
    required this.theme,
    required this.thisWeek,
    required this.lastWeek,
  });

  final M3EThemeData theme;
  final int thisWeek;
  final int lastWeek;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final delta = thisWeek - lastWeek;
    final (label, color) = switch (delta) {
      > 0 => ('+$delta vs last week', scheme.primary),
      < 0 => ('$delta vs last week', scheme.onSurfaceVariant),
      _ => ('same as last week', scheme.onSurfaceVariant),
    };
    return Row(
      children: [
        Flexible(
          child: Text(
            '$thisWeek this week',
            style: theme.typography.emphasized.titleSmall.copyWith(
              color: scheme.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.baseline.labelSmall.copyWith(
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
