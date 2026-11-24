import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/motion/spring_entrance.dart';
import '../../core/motion/spring_switcher.dart';
import '../../domain/insights_engine.dart';
import '../../l10n/generated/app_localizations.dart';
import '../shell/feature_placeholders.dart';
import '../today/widgets/floating_pills.dart';
import 'stats_providers.dart';
import 'widgets/habit_completion_list.dart';
import 'widgets/routine_comparison.dart';
import 'widgets/streak_leaderboard.dart';
import 'widgets/tag_donut.dart';
import 'widgets/trend_chart.dart';
import 'widgets/weekly_bars.dart';
import 'widgets/weekly_review_card.dart';

/// The Stats tab: 30-day trend, weekly summary, streak leaderboard, and tag
/// donut — all derived reactively from the local database.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);
    final vm = ref.watch(statsViewModelProvider);

    return Scaffold(
      appBar: M3EAppBar.top(
        titleText: l10n.navStats,
        actions: const [SearchAction(), SettingsAction()],
      ),
      // Range changes replay a spring fade-through on the whole scroll view,
      // preserving the list's lazy child building.
      body: SpringSwitcher(
        switchKey: vm.range,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            M3ESegmentedButton<InsightRange>(
              key: const ValueKey('stats-range'),
              selected: {vm.range},
              onSelectionChanged: (selection) =>
                  ref.read(statsRangeProvider.notifier).set(selection.first),
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
            if (!vm.hasData)
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: FloatingPills(
                  icon: M3EIcons.insights,
                  message: l10n.statsEmpty,
                ),
              )
            else ...[
              _SummaryRow(
                theme: theme,
                checkins: vm.totalCheckins,
                tasksDone: vm.totalTasksDone,
                bestStreak: vm.bestStreakOverall,
              ),
              const SizedBox(height: 16),
              SpringEntrance(
                key: const ValueKey('stats-entrance-0'),
                index: 0,
                child: _StatsCard(
                  theme: theme,
                  title: l10n.statsLastNDays(vm.range.days),
                  child: TrendChart(trend: vm.trend),
                ),
              ),
              const SizedBox(height: 16),
              SpringEntrance(
                key: const ValueKey('stats-entrance-1'),
                index: 1,
                child: _StatsCard(
                  theme: theme,
                  title: l10n.statsWeeklySummary,
                  child: WeeklyBars(
                    weeks: vm.weeks,
                    thisWeekTotal: vm.thisWeekTotal,
                    lastWeekTotal: vm.lastWeekTotal,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SpringEntrance(
                key: const ValueKey('stats-entrance-2'),
                index: 2,
                child: _StatsCard(
                  theme: theme,
                  title: l10n.statsStreakLeaderboard,
                  child: StreakLeaderboard(entries: vm.leaderboard),
                ),
              ),
              const SizedBox(height: 16),
              SpringEntrance(
                key: const ValueKey('stats-entrance-3'),
                index: 3,
                child: _StatsCard(
                  theme: theme,
                  title: l10n.statsTasksByTag,
                  child: TagDonut(slices: vm.tagSlices),
                ),
              ),
              const SizedBox(height: 16),
              SpringEntrance(
                key: const ValueKey('stats-entrance-4'),
                index: 4,
                child: _StatsCard(
                  theme: theme,
                  title: l10n.statsWeeklyReview,
                  child: WeeklyReviewCard(review: vm.review),
                ),
              ),
              const SizedBox(height: 16),
              SpringEntrance(
                key: const ValueKey('stats-entrance-5'),
                index: 5,
                child: _StatsCard(
                  theme: theme,
                  title: l10n.statsHabitCompletion,
                  child: HabitCompletionList(entries: vm.habitCompletion),
                ),
              ),
              if (vm.routineCompletion.any((entry) => entry.key != null)) ...[
                const SizedBox(height: 16),
                SpringEntrance(
                  key: const ValueKey('stats-entrance-6'),
                  index: 6,
                  child: _StatsCard(
                    theme: theme,
                    title: l10n.statsRoutineComparison,
                    child: RoutineComparison(entries: vm.routineCompletion),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Three headline numbers: total check-ins, tasks done, best streak.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.theme,
    required this.checkins,
    required this.tasksDone,
    required this.bestStreak,
  });

  final M3EThemeData theme;
  final int checkins;
  final int tasksDone;
  final int bestStreak;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = theme.colorScheme;
    // M3 role pairs: a container fill always uses its matching `on *` role.
    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            theme: theme,
            value: '$checkins',
            label: l10n.statsCheckIns,
            icon: M3EIcons.check_circle,
            color: scheme.primaryContainer,
            onColor: scheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryTile(
            theme: theme,
            value: '$tasksDone',
            label: l10n.statsTasksDone,
            icon: M3EIcons.task_alt,
            color: scheme.tertiaryContainer,
            onColor: scheme.onTertiaryContainer,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryTile(
            theme: theme,
            value: '$bestStreak',
            label: l10n.statsBestStreak,
            icon: M3EIcons.local_fire_department,
            color: scheme.secondaryContainer,
            onColor: scheme.onSecondaryContainer,
          ),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.theme,
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    required this.onColor,
  });

  final M3EThemeData theme;
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return M3ECard(
      variant: M3ECardVariant.filled,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: onColor),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.typography.emphasized.headlineSmall.copyWith(
              color: onColor,
            ),
          ),
          Text(
            label,
            style: theme.typography.emphasized.labelSmall.copyWith(
              color: onColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.theme,
    required this.title,
    required this.child,
  });

  final M3EThemeData theme;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return M3ECard(
      variant: M3ECardVariant.filled,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.typography.emphasized.titleMedium.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
