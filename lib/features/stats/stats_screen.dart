import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:motor/motor.dart';

import '../../core/motion/app_motion.dart';
import '../../core/motion/motion_scheme_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../shell/feature_placeholders.dart';
import '../today/widgets/floating_pills.dart';
import 'stats_providers.dart';
import 'widgets/streak_leaderboard.dart';
import 'widgets/tag_donut.dart';
import 'widgets/trend_chart.dart';
import 'widgets/weekly_bars.dart';

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
        actions: const [SettingsAction()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
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
            _Entrance(
              key: const ValueKey('stats-entrance-0'),
              index: 0,
              child: _StatsCard(
                theme: theme,
                title: l10n.statsLast30Days,
                child: TrendChart(trend: vm.trend),
              ),
            ),
            const SizedBox(height: 16),
            _Entrance(
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
            _Entrance(
              key: const ValueKey('stats-entrance-2'),
              index: 2,
              child: _StatsCard(
                theme: theme,
                title: l10n.statsStreakLeaderboard,
                child: StreakLeaderboard(entries: vm.leaderboard),
              ),
            ),
            const SizedBox(height: 16),
            _Entrance(
              key: const ValueKey('stats-entrance-3'),
              index: 3,
              child: _StatsCard(
                theme: theme,
                title: l10n.statsTasksByTag,
                child: TagDonut(slices: vm.tagSlices),
              ),
            ),
          ],
        ],
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
    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            theme: theme,
            value: '$checkins',
            label: l10n.statsCheckIns,
            icon: M3EIcons.check_circle,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryTile(
            theme: theme,
            value: '$tasksDone',
            label: l10n.statsTasksDone,
            icon: M3EIcons.task_alt,
            color: theme.colorScheme.tertiary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryTile(
            theme: theme,
            value: '$bestStreak',
            label: l10n.statsBestStreak,
            icon: M3EIcons.local_fire_department,
            color: theme.colorScheme.secondary,
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
  });

  final M3EThemeData theme;
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return M3ECard(
      variant: M3ECardVariant.filled,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.typography.emphasized.headlineSmall.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          Text(
            label,
            style: theme.typography.baseline.labelSmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
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

/// A cheap spring entrance: each card fades + rises into place, staggered by
/// [index]. Static (no animation) under reduced motion.
class _Entrance extends StatefulWidget {
  const _Entrance({required this.index, required this.child, super.key});

  final int index;
  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final SingleMotionController _rise;

  @override
  void initState() {
    super.initState();
    _rise = SingleMotionController(
      motion: MotionTokens.expressive.spatialDefault,
      vsync: this,
      initialValue: 0,
    );
    // Bounded stagger (max 180ms): always fires, including inside widget
    // tests' fake-async pumps, so no timer outlives the test.
    Future<void>.delayed(Duration(milliseconds: 60 * widget.index), () {
      if (mounted) _rise.animateTo(1);
    });
  }

  @override
  void dispose() {
    _rise.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = MotionScope.of(context);
    _rise.motion = tokens.spatialDefault;
    if (tokens.reduced) return widget.child;
    return AnimatedBuilder(
      animation: _rise,
      builder: (context, child) {
        final t = _rise.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
