import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_surfaces.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/enums.dart';
import '../../../domain/schedule.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../task_providers.dart';
import 'check_pill.dart';

/// A single task row: check-off pill, title, due/overdue indicator, priority
/// dot, subtask progress, and tag chips. Swipe to complete.
class TaskCard extends ConsumerWidget {
  const TaskCard({
    required this.task,
    required this.onTap,
    required this.onToggleComplete,
    super.key,
  });

  final Task task;
  final VoidCallback onTap;
  final VoidCallback onToggleComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = M3ETheme.of(context);
    final now = DateTime.now();
    final completed = task.completedAt != null;
    final overdue = isTaskOverdue(
      dueAt: task.dueAt,
      now: now,
      completed: completed,
    );
    final subtasks = ref.watch(subtasksProvider(task.id)).value ?? const [];
    final tags = ref.watch(taskTagsProvider(task.id)).value ?? const [];

    final doneCount = subtasks.where((s) => s.done).length;

    // M3 card variants are style-only: outlined reads as lower emphasis for
    // completed rows, filled keeps active work forward. Overdue work gets an
    // error-toned wash; the swipe action stays unchanged.
    return M3ECard(
      variant: completed ? M3ECardVariant.outlined : M3ECardVariant.filled,
      color: !completed && overdue
          ? AppSurfaces.tint(theme.colorScheme, theme.colorScheme.error)
          : null,
      border: !completed && overdue
          ? BorderSide(color: AppSurfaces.accentBorder(theme.colorScheme.error))
          : null,
      onPressed: onTap,
      onSwipe: completed ? null : onToggleComplete,
      swipeMode: M3ECardSwipeMode.dismiss,
      trailingSwipeColor: theme.colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          CheckPill(
            checked: completed,
            onChanged: (_) => onToggleComplete(),
            semanticLabel: completed
                ? AppLocalizations.of(context).markIncomplete
                : AppLocalizations.of(context).markComplete,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (task.priority != TaskPriority.none) ...[
                      _PriorityDot(priority: task.priority),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.baseline.titleMedium.copyWith(
                          decoration: completed
                              ? TextDecoration.lineThrough
                              : null,
                          color: completed
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                if (task.dueAt != null ||
                    subtasks.isNotEmpty ||
                    tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (task.dueAt != null)
                          _DueLabel(
                            dueAt: task.dueAt!,
                            overdue: overdue,
                            completed: completed,
                          ),
                        if (subtasks.isNotEmpty)
                          _SubtaskProgress(
                            done: doneCount,
                            total: subtasks.length,
                          ),
                        for (final tag in tags) _TagChip(tag: tag),
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

class _PriorityDot extends StatelessWidget {
  const _PriorityDot({required this.priority});

  final TaskPriority priority;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final color = switch (priority) {
      TaskPriority.high => theme.colorScheme.error,
      TaskPriority.medium => theme.colorScheme.tertiary,
      TaskPriority.low => theme.colorScheme.primary,
      TaskPriority.none => theme.colorScheme.outline,
    };
    // A short rectangular accent creates shape tension against the rounded
    // card and reads at a glance, unlike a tiny dot.
    return ExcludeSemantics(
      child: Container(
        width: 4,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppShape.card / 2),
        ),
      ),
    );
  }
}

class _DueLabel extends StatelessWidget {
  const _DueLabel({
    required this.dueAt,
    required this.overdue,
    required this.completed,
  });

  final DateTime dueAt;
  final bool overdue;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final color = overdue && !completed
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    final local = dueAt.toLocal();
    final label =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          overdue && !completed ? M3EIcons.warning : M3EIcons.calendar_today,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 3),
        Text(
          overdue && !completed
              ? AppLocalizations.of(context).overdueLabel(label)
              : label,
          style: theme.typography.baseline.labelSmall.copyWith(color: color),
        ),
      ],
    );
  }
}

class _SubtaskProgress extends StatelessWidget {
  const _SubtaskProgress({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          M3EIcons.checklist,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 3),
        Text(
          '$done/$total',
          style: theme.typography.baseline.labelSmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag});

  final Tag tag;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final color = Color(tag.color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        tag.name,
        style: theme.typography.baseline.labelSmall.copyWith(color: color),
      ),
    );
  }
}
