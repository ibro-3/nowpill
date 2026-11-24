import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/motion/shape_morph.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../tasks/widgets/check_pill.dart';
import '../habit_icons.dart';
import '../habit_providers.dart';
import 'streak_odometer.dart';

/// A habit row: icon, name, schedule hint, streak odometer, token count, and
/// the signature check-pill for today's check-in.
class HabitCard extends ConsumerWidget {
  const HabitCard({
    required this.habit,
    required this.onTap,
    required this.onCheckIn,
    this.onLogRelapse,
    super.key,
  });

  final Habit habit;
  final VoidCallback onTap;
  final VoidCallback onCheckIn;
  final VoidCallback? onLogRelapse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = M3ETheme.of(context);
    final streak = ref.watch(habitStreakProvider(habit.id));
    final checkedToday = ref.watch(habitCheckedTodayProvider(habit.id));
    final color = Color(habit.color);
    final isQuit = habit.kind == HabitKind.quit;

    return M3ECard(
      variant: M3ECardVariant.filled,
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          MorphingShape(
            from: M3EShapeKind.cookie6Sided,
            to: M3EShapeKind.cookie9Sided,
            active: checkedToday,
            size: 44,
            color: color.withValues(alpha: 0.18),
            activeColor: color.withValues(alpha: 0.28),
            childBuilder: (t) => Icon(
              habitIconForKey(habit.iconKey),
              size: 22 * (0.96 + 0.04 * t),
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  habit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.baseline.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  isQuit
                      ? AppLocalizations.of(context).habitCleanDays
                      : _scheduleLabel(AppLocalizations.of(context), habit),
                  style: theme.typography.baseline.labelSmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    M3EIcons.local_fire_department,
                    size: 16,
                    color: streak.currentStreak > 0
                        ? theme.colorScheme.tertiary
                        : theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 2),
                  StreakOdometer(
                    value: streak.currentStreak,
                    style: theme.typography.emphasized.titleMedium,
                  ),
                ],
              ),
              if (streak.tokens > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      M3EIcons.ac_unit,
                      size: 12,
                      color: theme.colorScheme.tertiary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${streak.tokens}',
                      style: theme.typography.baseline.labelSmall.copyWith(
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(width: 12),
          if (isQuit)
            Semantics(
              button: true,
              label: AppLocalizations.of(context).logRelapseFor(habit.name),
              child: M3EIconButton(
                variant: M3EIconButtonVariant.standard,
                icon: Icon(M3EIcons.error, color: color),
                tooltip: AppLocalizations.of(context).logRelapse,
                onPressed: onLogRelapse ?? onCheckIn,
              ),
            )
          else
            CheckPill(
              checked: checkedToday,
              activeColor: color,
              onChanged: (_) => onCheckIn(),
              semanticLabel: checkedToday
                  ? AppLocalizations.of(context).undoCheckInHabit(habit.name)
                  : AppLocalizations.of(context).checkInHabit(habit.name),
            ),
        ],
      ),
    );
  }

  String _scheduleLabel(AppLocalizations l10n, Habit h) {
    final base = switch (h.scheduleType) {
      HabitScheduleType.daily => l10n.everyDay,
      HabitScheduleType.weekdays => _weekdayLabel(l10n, h),
      HabitScheduleType.weeklyTarget => l10n.perWeek(h.targetPerWeek ?? 1),
    };
    final target = h.targetAmount;
    if (target == null) return base;
    final fmt = target == target.roundToDouble()
        ? target.toInt().toString()
        : target.toString();
    return '$base · ${l10n.goalPerDay(fmt)}';
  }

  String _weekdayLabel(AppLocalizations l10n, Habit h) {
    final names = [
      l10n.weekdayMon,
      l10n.weekdayTue,
      l10n.weekdayWed,
      l10n.weekdayThu,
      l10n.weekdayFri,
      l10n.weekdaySat,
      l10n.weekdaySun,
    ];
    final days = (h.weekdays ?? [])
        .where((d) => d >= 1 && d <= 7)
        .map((d) => names[d - 1])
        .join(', ');
    return days.isEmpty ? l10n.scheduleWeekdays : days;
  }
}
