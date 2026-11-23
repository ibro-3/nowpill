import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import '../../../domain/stats_engine.dart';

/// 30-day completion trend: habit check-ins (primary) and tasks done
/// (tertiary) as two smooth lines with a soft area fill under the habits.
class TrendChart extends StatelessWidget {
  const TrendChart({required this.trend, super.key});

  final List<DayCount> trend;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final scheme = theme.colorScheme;
    if (trend.isEmpty) return const SizedBox(height: 180);

    final maxY = _niceMax(
      trend.fold<int>(0, (m, d) => d.total > m ? d.total : m),
    );
    final labelStyle = theme.typography.baseline.labelSmall.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          minX: 0,
          maxX: (trend.length - 1).toDouble(),
          lineTouchData: const LineTouchData(enabled: false),
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
                interval: 7,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= trend.length) {
                    return const SizedBox.shrink();
                  }
                  final day = trend[i].day;
                  return SideTitleWidget(
                    meta: meta,
                    child: Text('${day.month}/${day.day}', style: labelStyle),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < trend.length; i++)
                  FlSpot(i.toDouble(), trend[i].habitCheckins.toDouble()),
              ],
              isCurved: true,
              curveSmoothness: 0.25,
              preventCurveOverShooting: true,
              color: scheme.primary,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: scheme.primary.withValues(alpha: 0.12),
              ),
            ),
            LineChartBarData(
              spots: [
                for (var i = 0; i < trend.length; i++)
                  FlSpot(i.toDouble(), trend[i].tasksDone.toDouble()),
              ],
              isCurved: true,
              curveSmoothness: 0.25,
              preventCurveOverShooting: true,
              color: scheme.tertiary,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }

  /// Rounds the axis maximum up to a friendly number so gridlines land on
  /// integers (at least 3 so the chart never looks flat-lined at zero).
  double _niceMax(int maxValue) {
    if (maxValue <= 3) return 3;
    final step = maxValue <= 6 ? 2 : (maxValue / 3).ceil();
    return (step * 3).toDouble();
  }
}
