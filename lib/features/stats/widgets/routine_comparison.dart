import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import '../../../domain/insights_engine.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'completion_row.dart';

/// Weighted completion average per routine (and Unrouted), ranked by rate.
class RoutineComparison extends StatelessWidget {
  const RoutineComparison({required this.entries, super.key});

  final List<RoutineInsight> entries;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);
    final color = theme.colorScheme.primary.toARGB32();
    return Column(
      children: [
        for (final entry in entries)
          CompletionRow(
            label: entry.key == null ? l10n.unrouted : entry.name,
            detail: l10n.insightHabitCount(entry.habitCount),
            percent: entry.percent,
            color: color,
          ),
      ],
    );
  }
}
