import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/weekly_review.dart';
import '../../../l10n/generated/app_localizations.dart';

/// A compact, glanceable recap of last week plus what needs attention today.
class WeeklyReviewCard extends StatelessWidget {
  const WeeklyReviewCard({required this.review, super.key});

  final WeeklyReview review;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);
    final caption = theme.typography.baseline.labelSmall.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.typography.emphasized.titleLarge;
    final delta = review.delta;
    final deltaText = delta == 0
        ? l10n.statsSameAsLastWeek
        : l10n.reviewDelta(delta > 0 ? '+$delta' : '$delta');

    return Semantics(
      container: true,
      label: l10n.statsWeeklyReview,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _Figure(
                  value: '${review.lastWeekTotal}',
                  caption: l10n.reviewDone,
                  valueStyle: valueStyle,
                  captionStyle: caption,
                ),
              ),
              Expanded(
                child: _Figure(
                  value: '${review.tasksDoneLastWeek}',
                  caption: l10n.reviewTasks,
                  valueStyle: valueStyle,
                  captionStyle: caption,
                ),
              ),
              Expanded(
                child: _Figure(
                  value: '${review.bestStreak}',
                  caption: l10n.reviewBest,
                  valueStyle: valueStyle,
                  captionStyle: caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            deltaText,
            style: theme.typography.baseline.bodyMedium.copyWith(
              color: delta < 0
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            review.atRisk.isEmpty
                ? l10n.reviewAllSafe
                : '${l10n.reviewAtRisk}: ${review.atRisk.join(', ')}',
            style: theme.typography.baseline.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text('${review.dueAhead} ${l10n.reviewAhead}', style: caption),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.caption,
    required this.valueStyle,
    required this.captionStyle,
  });

  final String value;
  final String caption;
  final TextStyle valueStyle;
  final TextStyle captionStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: valueStyle),
        const SizedBox(height: 2),
        Text(caption, textAlign: TextAlign.center, style: captionStyle),
      ],
    );
  }
}
