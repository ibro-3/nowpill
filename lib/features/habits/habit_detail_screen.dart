import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/repositories/providers.dart';
import '../../domain/date_utils.dart';
import '../../domain/streak_engine.dart';
import 'habit_editor_sheet.dart';
import 'habit_icons.dart';
import 'habit_providers.dart';
import 'widgets/habit_heatmap.dart';
import 'widgets/token_wallet.dart';

/// Habit detail: monthly heatmap with backfill, streak stats, token wallet,
/// and archive / delete actions.
class HabitDetailScreen extends ConsumerStatefulWidget {
  const HabitDetailScreen({required this.habitId, super.key});

  final int habitId;

  @override
  ConsumerState<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends ConsumerState<HabitDetailScreen> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  Future<void> _toggleDay(DateTime day) async {
    final repo = ref.read(habitRepositoryProvider);
    final key = formatDate(day);
    final checkins =
        ref.read(habitCheckinsProvider(widget.habitId)).value ?? const [];
    final exists = checkins.any((c) => c.date == key);
    if (exists) {
      await repo.removeCheckIn(widget.habitId, key);
    } else {
      await repo.checkIn(widget.habitId, key);
    }
  }

  Future<void> _archive() async {
    await ref.read(habitRepositoryProvider).archive(widget.habitId);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await M3EDialog.show<bool>(
      context,
      dialog: M3EDialog(
        title: 'Delete habit?',
        content: const Text(
          'This permanently removes the habit and all its check-in history. '
          'This cannot be undone.',
        ),
        actions: [
          M3EButton(
            style: M3EButtonStyle.text,
            onPressed: () => Navigator.of(context).pop(false),
            label: const Text('Cancel'),
          ),
          M3EButton(
            onPressed: () => Navigator.of(context).pop(true),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(habitRepositoryProvider).delete(widget.habitId);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final habit = ref.watch(habitProvider(widget.habitId)).value;
    if (habit == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final streak = ref.watch(habitStreakProvider(widget.habitId));
    final checkins =
        ref.watch(habitCheckinsProvider(widget.habitId)).value ?? const [];
    final schedule = ref.watch(habitScheduleProvider(widget.habitId));
    final color = Color(habit.color);
    final unit = schedule.isDayBased ? daysPerToken : weeksPerToken;
    final unitLabel = schedule.isDayBased ? 'day' : 'week';
    final toNext = unit - (streak.currentStreak % unit);

    return Scaffold(
      appBar: M3EAppBar.top(
        titleText: habit.name,
        leading: M3EIconButton(
          variant: M3EIconButtonVariant.standard,
          icon: const Icon(M3EIcons.arrow_back),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          M3EIconButton(
            variant: M3EIconButtonVariant.standard,
            icon: const Icon(M3EIcons.edit),
            tooltip: 'Edit habit',
            onPressed: () => showHabitEditor(context, habit: habit),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Row(
                children: [
                  M3EShapeContainer(
                    kind: M3EShapeKind.cookie6Sided,
                    width: 56,
                    height: 56,
                    color: color.withValues(alpha: 0.18),
                    child: Icon(
                      habitIconForKey(habit.iconKey),
                      size: 28,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _StatRow(
                          icon: M3EIcons.local_fire_department,
                          label: 'Current streak',
                          value: '${streak.currentStreak}',
                          color: theme.colorScheme.tertiary,
                          theme: theme,
                        ),
                        const SizedBox(height: 4),
                        _StatRow(
                          icon: M3EIcons.emoji_events,
                          label: 'Best streak',
                          value: '${streak.bestStreak}',
                          color: theme.colorScheme.primary,
                          theme: theme,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              M3ECard(
                variant: M3ECardVariant.filled,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Freeze tokens',
                          style: theme.typography.emphasized.titleSmall,
                        ),
                        const Spacer(),
                        TokenWallet(tokens: streak.tokens),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      streak.tokens >= maxTokens
                          ? 'Wallet full — tokens automatically protect a missed '
                                '$unitLabel.'
                          : 'Earn a token every $unit-$unitLabel streak '
                                '($toNext to go). Tokens automatically protect a '
                                'missed $unitLabel.',
                      style: theme.typography.baseline.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  M3EIconButton(
                    variant: M3EIconButtonVariant.standard,
                    icon: const Icon(M3EIcons.chevron_left),
                    tooltip: 'Previous month',
                    onPressed: () => _shiftMonth(-1),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        _monthLabel(_month),
                        style: theme.typography.emphasized.titleMedium,
                      ),
                    ),
                  ),
                  M3EIconButton(
                    variant: M3EIconButtonVariant.standard,
                    icon: const Icon(M3EIcons.chevron_right),
                    tooltip: 'Next month',
                    onPressed: () => _shiftMonth(1),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              HabitHeatmap(
                month: _month,
                checkins: checkins.map((c) => c.date).toSet(),
                streak: streak,
                schedule: schedule,
                startDate: habit.createdAt.toLocal(),
                color: color,
                onToggleDay: _toggleDay,
              ),
              const SizedBox(height: 8),
              Text(
                'Tap a day within the last 30 days to backfill a check-in.',
                style: theme.typography.baseline.labelSmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: M3EButton.icon(
                      onPressed: _archive,
                      style: M3EButtonStyle.tonal,
                      icon: const Icon(M3EIcons.archive),
                      label: const Text('Archive'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  M3EIconButton(
                    variant: M3EIconButtonVariant.standard,
                    icon: Icon(
                      M3EIcons.delete_forever,
                      color: theme.colorScheme.error,
                    ),
                    tooltip: 'Delete habit',
                    onPressed: _confirmDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _monthLabel(DateTime m) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${names[m.month - 1]} ${m.year}';
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final M3EThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          value,
          style: theme.typography.emphasized.titleLarge.copyWith(color: color),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.typography.baseline.labelMedium.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
