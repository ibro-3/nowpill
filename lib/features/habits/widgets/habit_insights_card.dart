import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/insights_engine.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Shared description of an insight's numerators, e.g. "3 of 10 days".
String insightDetail(AppLocalizations l10n, HabitInsight insight) {
  if (insight.isWeekly) {
    return l10n.insightWeeks(insight.completed, insight.tracked);
  }
  if (insight.isQuit) {
    return l10n.insightCleanDays(insight.completed, insight.tracked);
  }
  return l10n.insightDays(insight.completed, insight.tracked);
}

/// Compact completion insights for one habit: rate over a trailing window,
/// progress bar, and the strongest weekday (or relapse count for quit habits).
class HabitInsightsCard extends StatelessWidget {
  const HabitInsightsCard({
    required this.insight,
    required this.range,
    required this.onRangeChanged,
    super.key,
  });

  final HabitInsight insight;
  final InsightRange range;
  final ValueChanged<InsightRange> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    return M3ECard(
      key: const ValueKey('habit-insights'),
      variant: M3ECardVariant.filled,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.insightTitle,
            style: theme.typography.emphasized.titleSmall,
          ),
          const SizedBox(height: 8),
          M3ESegmentedButton<InsightRange>(
            selected: {range},
            onSelectionChanged: (selection) => onRangeChanged(selection.first),
            segments: [
              M3ESegment(
                value: InsightRange.last30Days,
                label: l10n.statsRange30,
              ),
              M3ESegment(
                value: InsightRange.last90Days,
                label: l10n.statsRange90,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!insight.hasHistory)
            Text(
              l10n.insightNoHistory,
              style: theme.typography.baseline.bodyMedium.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${insight.percent}%',
                  style: theme.typography.emphasized.headlineSmall.copyWith(
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    insightDetail(l10n, insight),
                    style: theme.typography.baseline.labelMedium.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Semantics(
              container: true,
              label: '${insight.percent}%',
              child: LinearProgressIndicator(
                value: insight.rate ?? 0,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
                backgroundColor: scheme.surfaceContainerHighest,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            if (insight.isQuit)
              Text(
                l10n.insightRelapses(insight.relapses),
                style: theme.typography.baseline.labelMedium.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else if (insight.bestWeekday != null)
              Row(
                children: [
                  Icon(
                    M3EIcons.calendar_month,
                    size: 16,
                    color: scheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      insight.isWeekly
                          ? l10n.insightMostActiveDay(
                              weekdayName(l10n, insight.bestWeekday!),
                            )
                          : l10n.insightBestDay(
                              weekdayName(l10n, insight.bestWeekday!),
                            ),
                      style: theme.typography.baseline.labelMedium.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            if (!insight.isQuit) ...[
              const SizedBox(height: 8),
              Text(
                l10n.insightNeutralHint,
                style: theme.typography.baseline.labelSmall.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// ISO weekday (1 = Mon … 7 = Sun) to a localized full name.
  static String weekdayName(AppLocalizations l10n, int weekday) {
    return switch (weekday) {
      1 => l10n.weekdayMonday,
      2 => l10n.weekdayTuesday,
      3 => l10n.weekdayWednesday,
      4 => l10n.weekdayThursday,
      5 => l10n.weekdayFriday,
      6 => l10n.weekdaySaturday,
      7 => l10n.weekdaySunday,
      _ => '',
    };
  }
}
