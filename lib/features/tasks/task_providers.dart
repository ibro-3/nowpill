import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/providers.dart';
import '../../domain/schedule.dart';
import 'task_filter.dart';

part 'task_providers.g.dart';

// NOTE: The drift-typed stream/list providers below are hand-written rather
// than code-generated. riverpod_generator (via analyzer_buffer) cannot resolve
// Drift's part-file data classes (Task, Tag, …) as provider value types, so we
// declare them manually. The notifiers use codegen. See doc/m3e_spike_decision.md.

/// The active list filter.
@Riverpod(keepAlive: true)
class TaskFilterNotifier extends _$TaskFilterNotifier {
  @override
  TaskFilter build() => TaskFilter.today;

  void set(TaskFilter filter) => state = filter;
}

/// Optional tag filter (null = all tags).
@Riverpod(keepAlive: true)
class TaskTagFilterNotifier extends _$TaskTagFilterNotifier {
  @override
  int? build() => null;

  void set(int? tagId) => state = tagId;
}

/// All tasks, reactive.
final allTasksProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchAll();
});

/// All tags, reactive (for the filter row and editor).
final allTagsProvider = StreamProvider<List<Tag>>((ref) {
  return ref.watch(tagRepositoryProvider).watchAll();
});

/// Subtasks for a task, reactive.
final subtasksProvider = StreamProvider.family<List<Subtask>, int>((
  ref,
  taskId,
) {
  return ref.watch(taskRepositoryProvider).watchSubtasks(taskId);
});

/// Tags attached to a task, reactive (for display on the card).
final taskTagsProvider = StreamProvider.family<List<Tag>, int>((ref, taskId) {
  return ref.watch(taskRepositoryProvider).watchTags(taskId);
});

/// All task→tag links, reactive (for the tag filter).
final allTaskTagsProvider = StreamProvider<List<TaskTag>>((ref) {
  return ref.watch(taskRepositoryProvider).watchAllTaskTags();
});

/// The filtered, sorted task list for the current filter + tag selection.
///
/// Sorting: overdue first, then by due date ascending (nulls last), then by
/// creation. Completed tasks sort by completion time descending.
final filteredTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(allTasksProvider).value ?? const <Task>[];
  final filter = ref.watch(taskFilterProvider);
  final tagFilter = ref.watch(taskTagFilterProvider);
  final now = DateTime.now();

  Iterable<Task> result = tasks;

  if (tagFilter != null) {
    final links = ref.watch(allTaskTagsProvider).value ?? const <TaskTag>[];
    final taggedIds = links
        .where((l) => l.tagId == tagFilter)
        .map((l) => l.taskId)
        .toSet();
    result = result.where((t) => taggedIds.contains(t.id));
  }

  switch (filter) {
    case TaskFilter.today:
      result = result.where(
        (t) => isTaskInToday(
          dueAt: t.dueAt,
          now: now,
          completed: t.completedAt != null,
        ),
      );
    case TaskFilter.upcoming:
      result = result.where(
        (t) =>
            t.completedAt == null &&
            t.dueAt != null &&
            !isTaskInToday(dueAt: t.dueAt, now: now, completed: false),
      );
    case TaskFilter.all:
      break;
    case TaskFilter.done:
      result = result.where((t) => t.completedAt != null);
  }

  final list = result.toList();
  if (filter == TaskFilter.done) {
    list.sort(
      (a, b) => (b.completedAt ?? DateTime(0)).compareTo(
        a.completedAt ?? DateTime(0),
      ),
    );
  } else {
    list.sort((a, b) {
      final aOver = isTaskOverdue(
        dueAt: a.dueAt,
        now: now,
        completed: a.completedAt != null,
      );
      final bOver = isTaskOverdue(
        dueAt: b.dueAt,
        now: now,
        completed: b.completedAt != null,
      );
      if (aOver != bOver) return aOver ? -1 : 1;
      final aDue = a.dueAt;
      final bDue = b.dueAt;
      if (aDue != null && bDue != null) {
        final c = aDue.compareTo(bDue);
        if (c != 0) return c;
      } else if (aDue != null) {
        return -1;
      } else if (bDue != null) {
        return 1;
      }
      return b.createdAt.compareTo(a.createdAt);
    });
  }
  return list;
});
