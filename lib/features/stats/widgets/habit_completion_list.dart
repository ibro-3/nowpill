import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../habits/habit_detail_screen.dart';
import '../../habits/habit_icons.dart';
import '../../habits/widgets/habit_insights_card.dart';
import '../stats_view_model.dart';
import 'completion_row.dart';

/// Active habits ranked by completion rate; tapping opens the habit's detail.
class HabitCompletionList extends StatelessWidget {
  const HabitCompletionList({required this.entries, super.key});

  final List<HabitCompletionEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    if (entries.isEmpty) {
      return Text(
        AppLocalizations.of(context).statsCompletionEmpty,
        style: theme.typography.baseline.bodyMedium.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        for (final entry in entries)
          CompletionRow(
            label: entry.name,
            detail: insightDetail(l10n, entry.insight),
            percent: entry.insight.percent,
            color: entry.color,
            icon: habitIconForKey(entry.iconKey),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => HabitDetailScreen(habitId: entry.habitId),
              ),
            ),
          ),
      ],
    );
  }
}
