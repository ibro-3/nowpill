import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../shell/feature_placeholders.dart';
import 'task_editor_sheet.dart';
import 'task_filter.dart';
import 'task_providers.dart';
import 'widgets/task_card.dart';

/// The Tasks tab: filterable list of to-dos with a create FAB.
class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(taskFilterProvider);
    final tasks = ref.watch(filteredTasksProvider);
    final tags = ref.watch(allTagsProvider).value ?? const [];
    final tagFilter = ref.watch(taskTagFilterProvider);

    return Scaffold(
      appBar: M3EAppBar.top(
        titleText: l10n.navTasks,
        actions: const [SearchAction(), SettingsAction()],
      ),
      floatingActionButton: M3EFab(
        icon: const Icon(M3EIcons.add),
        tooltip: l10n.newTask,
        onPressed: () => showTaskEditor(context),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: M3EButtonGroup(
                selectedIndex: filter.index,
                onSelectedIndexChanged: (i) {
                  if (i != null) {
                    ref
                        .read(taskFilterProvider.notifier)
                        .set(TaskFilter.values[i]);
                  }
                },
                style: M3EButtonStyle.tonal,
                actions: [
                  M3EButtonGroupAction(label: Text(l10n.navToday)),
                  M3EButtonGroupAction(label: Text(l10n.upcoming)),
                  M3EButtonGroupAction(label: Text(l10n.all)),
                  M3EButtonGroupAction(label: Text(l10n.done)),
                ],
              ),
            ),
          ),
          if (tags.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final tag in tags)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Center(
                        child: M3EChip(
                          label: tag.name,
                          type: M3EChipType.filter,
                          selected: tagFilter == tag.id,
                          onPressed: () => ref
                              .read(taskTagFilterProvider.notifier)
                              .set(tagFilter == tag.id ? null : tag.id),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: tasks.isEmpty
                ? _EmptyState(filter: filter, theme: theme)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: tasks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final task = tasks[i];
                      return TaskCard(
                        key: ValueKey('task-${task.id}'),
                        task: task,
                        onTap: () => showTaskEditor(context, task: task),
                        onToggleComplete: () => _toggle(ref, task),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(WidgetRef ref, Task task) async {
    final repo = ref.read(taskRepositoryProvider);
    if (task.completedAt != null) {
      await repo.reopen(task.id);
    } else {
      await repo.complete(task.id);
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter, required this.theme});

  final TaskFilter filter;
  final M3EThemeData theme;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (icon, message) = switch (filter) {
      TaskFilter.today => (M3EIcons.today, l10n.tasksEmptyToday),
      TaskFilter.upcoming => (M3EIcons.calendar_today, l10n.tasksEmptyUpcoming),
      TaskFilter.all => (M3EIcons.checklist, l10n.tasksEmptyAll),
      TaskFilter.done => (M3EIcons.check_circle, l10n.tasksEmptyDone),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            M3EShapeContainer(
              kind: M3EShapeKind.cookie9Sided,
              width: 80,
              height: 80,
              color: theme.colorScheme.surfaceContainerHigh,
              child: Icon(
                icon,
                size: 34,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.typography.baseline.bodyLarge.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
