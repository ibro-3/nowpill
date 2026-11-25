import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/motion/spring_switcher.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../shell/feature_placeholders.dart';
import '../today/widgets/floating_pills.dart';
import 'task_editor_sheet.dart';
import 'task_filter.dart';
import 'task_providers.dart';
import 'widgets/task_card.dart';

/// The Tasks tab: filterable list of to-dos with a create FAB.
class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(taskFilterProvider);
    final tasks = ref.watch(filteredTasksProvider);
    final tags = ref.watch(allTagsProvider).value ?? const [];
    final tagFilter = ref.watch(taskTagFilterProvider);
    final lists = ref.watch(allTaskListsProvider).value ?? const [];
    final listFilter = ref.watch(taskListFilterProvider);
    // Filter chips grow with large system text; give their horizontal strips
    // room instead of clipping them to the default 44px.
    final chipRowHeight = 44 * MediaQuery.textScalerOf(context).scale(1.0);
    final wide = MediaQuery.sizeOf(context).width >= 840;

    return Scaffold(
      // The shell paints the shared ambient backdrop behind the branch.
      backgroundColor: Colors.transparent,
      appBar: M3EAppBar.top(
        // Keep the ambient backdrop continuous behind the bar.
        backgroundColor: Colors.transparent,
        titleText: l10n.navTasks,
        actions: const [SearchAction(), SettingsAction()],
      ),
      // M3: use an extended FAB when a label clarifies the primary action on
      // larger windows, and a medium FAB on compact/medium ones.
      floatingActionButton: wide
          ? M3EExtendedFab(
              label: l10n.newTask,
              icon: const Icon(M3EIcons.add),
              size: M3EExtendedFabSize.medium,
              onPressed: () => showTaskEditor(context),
            )
          : M3EFab(
              icon: const Icon(M3EIcons.add),
              tooltip: l10n.newTask,
              onPressed: () => showTaskEditor(context),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
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
          SizedBox(
            height: chipRowHeight,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: M3EChip(
                      label: l10n.taskLists,
                      type: M3EChipType.filter,
                      selected: listFilter == null,
                      onPressed: () =>
                          ref.read(taskListFilterProvider.notifier).set(null),
                    ),
                  ),
                ),
                for (final list in lists)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Center(
                      child: M3EChip(
                        label: list.name,
                        type: M3EChipType.filter,
                        selected: listFilter == list.id,
                        onPressed: () => ref
                            .read(taskListFilterProvider.notifier)
                            .set(listFilter == list.id ? null : list.id),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: M3EChip(
                      label: l10n.newList,
                      type: M3EChipType.assist,
                      leading: const Icon(M3EIcons.add, size: 18),
                      onPressed: () => _createList(context, ref),
                    ),
                  ),
                ),
                Center(
                  child: M3EIconButton(
                    variant: M3EIconButtonVariant.standard,
                    icon: const Icon(M3EIcons.edit_outlined),
                    tooltip: l10n.manageLists,
                    onPressed: () => M3EBottomSheet.showAdaptive<void>(
                      context,
                      title: l10n.manageLists,
                      builder: (context) => const _ListManagerSheet(),
                    ),
                  ),
                ),
              ],
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
            child: SpringSwitcher(
              switchKey: ValueKey('$filter|$listFilter|$tagFilter'),
              child: tasks.isEmpty
                  ? _EmptyState(filter: filter)
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

  Future<void> _createList(BuildContext context, WidgetRef ref) async {
    final name = await M3EDialog.show<String>(
      context,
      dialog: const _ListNameDialog(isNew: true),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref
        .read(taskListRepositoryProvider)
        .create(name: name.trim(), color: 0xFF2DD4A8);
    if (context.mounted) {
      M3ESnackbar.show(
        context,
        message: AppLocalizations.of(context).listCreated,
      );
    }
  }
}

/// Inline list manager: rename or delete lists without leaving the Tasks tab.
class _ListManagerSheet extends ConsumerWidget {
  const _ListManagerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);
    final lists = ref.watch(allTaskListsProvider).value ?? const [];
    if (lists.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          l10n.newList,
          style: theme.typography.baseline.bodyMedium.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: lists.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final list = lists[i];
        return ListTile(
          key: ValueKey('list-row-${list.id}'),
          title: Text(list.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              M3EIconButton(
                variant: M3EIconButtonVariant.standard,
                icon: const Icon(M3EIcons.edit_outlined),
                tooltip: l10n.renameList,
                onPressed: () async {
                  final name = await M3EDialog.show<String>(
                    context,
                    dialog: _ListNameDialog(isNew: false, initial: list.name),
                  );
                  if (name == null || name.trim().isEmpty) return;
                  await ref
                      .read(taskListRepositoryProvider)
                      .update(list.copyWith(name: name.trim()));
                },
              ),
              M3EIconButton(
                variant: M3EIconButtonVariant.standard,
                icon: const Icon(M3EIcons.delete_outline),
                tooltip: l10n.delete,
                onPressed: () async {
                  final confirmed = await M3EDialog.show<bool>(
                    context,
                    dialog: M3EDialog(
                      title: l10n.deleteListTitle,
                      content: Text(l10n.deleteListBody),
                      actions: [
                        M3EButton(
                          style: M3EButtonStyle.text,
                          onPressed: () => Navigator.of(context).pop(false),
                          label: Text(l10n.cancel),
                        ),
                        M3EButton(
                          key: const ValueKey('list-delete-confirm'),
                          onPressed: () => Navigator.of(context).pop(true),
                          label: Text(l10n.delete),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  await ref.read(taskListRepositoryProvider).delete(list.id);
                  if (ref.read(taskListFilterProvider) == list.id) {
                    ref.read(taskListFilterProvider.notifier).set(null);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Small text dialog used for both creating and renaming a list.
class _ListNameDialog extends StatefulWidget {
  const _ListNameDialog({required this.isNew, this.initial});

  final bool isNew;
  final String? initial;

  @override
  State<_ListNameDialog> createState() => _ListNameDialogState();
}

class _ListNameDialogState extends State<_ListNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return M3EDialog(
      title: widget.isNew ? l10n.newList : l10n.renameList,
      content: M3ETextField(
        autofocus: true,
        controller: _controller,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        M3EButton(
          style: M3EButtonStyle.text,
          onPressed: () => Navigator.of(context).pop(),
          label: Text(l10n.cancel),
        ),
        M3EButton(
          key: const ValueKey('list-name-save'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          label: Text(l10n.save),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});

  final TaskFilter filter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (icon, message) = switch (filter) {
      TaskFilter.today => (M3EIcons.today, l10n.tasksEmptyToday),
      TaskFilter.upcoming => (M3EIcons.calendar_today, l10n.tasksEmptyUpcoming),
      TaskFilter.all => (M3EIcons.checklist, l10n.tasksEmptyAll),
      TaskFilter.done => (M3EIcons.check_circle, l10n.tasksEmptyDone),
    };
    // The FAB is the single primary action on this screen; duplicating its
    // label here would create a second "new task" target for assistive tech.
    return FloatingPills(icon: icon, message: message);
  }
}
