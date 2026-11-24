import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import '../../../domain/stats_engine.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Tag donut: share of tasks per tag, with a legend. Center shows the total
/// tagged-task count.
class TagDonut extends StatelessWidget {
  const TagDonut({required this.slices, super.key});

  final List<TagSlice> slices;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final scheme = theme.colorScheme;
    if (slices.isEmpty) {
      return Text(
        AppLocalizations.of(context).statsTagEmpty,
        style: theme.typography.baseline.bodyMedium.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    final total = slices.fold<int>(0, (sum, s) => sum + s.taskCount);

    return Semantics(
      container: true,
      label: AppLocalizations.of(context).a11yDonut,
      child: Row(
        children: [
          SizedBox(
            width: 132,
            height: 132,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 38,
                    startDegreeOffset: -90,
                    pieTouchData: PieTouchData(enabled: false),
                    sections: [
                      for (final s in slices)
                        PieChartSectionData(
                          value: s.taskCount.toDouble(),
                          color: Color(s.color),
                          radius: 24,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$total',
                      style: theme.typography.emphasized.titleLarge.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      AppLocalizations.of(context).statsTagged,
                      style: theme.typography.baseline.labelSmall.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in slices.take(6))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Color(s.color),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.typography.baseline.bodyMedium
                                .copyWith(color: scheme.onSurface),
                          ),
                        ),
                        Text(
                          '${s.taskCount}',
                          style: theme.typography.baseline.labelMedium.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
