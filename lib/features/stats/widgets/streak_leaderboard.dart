import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import '../../../domain/stats_engine.dart';
import '../../habits/habit_icons.dart';
import '../../habits/widgets/streak_odometer.dart';

/// Streak leaderboard: active habits ranked by current streak, each row an
/// icon cookie, name, 🔥 current streak odometer, and best-streak hint.
class StreakLeaderboard extends StatelessWidget {
  const StreakLeaderboard({required this.entries, super.key});

  final List<LeaderboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    if (entries.isEmpty) {
      return Text(
        'No active habits yet.',
        style: theme.typography.baseline.bodyMedium.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == entries.length - 1 ? 0 : 10),
            child: _Row(entry: entries[i], rank: i + 1, theme: theme),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.rank, required this.theme});

  final LeaderboardEntry entry;
  final int rank;
  final M3EThemeData theme;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final color = Color(entry.color);
    final unit = entry.isWeekly ? 'wk' : 'd';

    return Row(
      children: [
        SizedBox(
          width: 22,
          child: Text(
            '$rank',
            style: theme.typography.baseline.labelMedium.copyWith(
              color: rank <= 3 ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
        M3EShapeContainer(
          kind: M3EShapeKind.cookie6Sided,
          width: 36,
          height: 36,
          color: color.withValues(alpha: 0.18),
          child: Icon(habitIconForKey(entry.iconKey), size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.baseline.titleSmall.copyWith(
                  color: scheme.onSurface,
                ),
              ),
              Text(
                'best ${entry.bestStreak}$unit',
                style: theme.typography.baseline.labelSmall.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          M3EIcons.local_fire_department,
          size: 16,
          color: entry.currentStreak > 0 ? scheme.tertiary : scheme.outline,
        ),
        const SizedBox(width: 2),
        StreakOdometer(
          value: entry.currentStreak,
          style: theme.typography.emphasized.titleSmall,
        ),
        const SizedBox(width: 2),
        Text(
          unit,
          style: theme.typography.baseline.labelSmall.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
