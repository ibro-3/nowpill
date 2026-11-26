import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/providers.dart';
import '../../domain/search.dart';
import '../chat/chat_providers.dart';
import '../habits/habit_providers.dart';
import '../tasks/task_providers.dart';

part 'search_providers.g.dart';

/// The current search query (empty = show hints, not results). Not keepAlive:
/// each visit to the search screen starts fresh.
@Riverpod(keepAlive: false)
class SearchQueryNotifier extends _$SearchQueryNotifier {
  @override
  String build() => '';

  void set(String query) => state = query;
}

/// Grouped search results, recomputed reactively on query or data changes.
class SearchResults {
  const SearchResults({
    this.tasks = const [],
    this.habits = const [],
    this.tags = const [],
    this.notes = const [],
  });

  final List<Task> tasks;
  final List<Habit> habits;
  final List<Tag> tags;
  final List<ChatNote> notes;

  bool get isEmpty =>
      tasks.isEmpty && habits.isEmpty && tags.isEmpty && notes.isEmpty;
  int get total => tasks.length + habits.length + tags.length + notes.length;
}

/// All subtasks, reactive (search matches subtask titles too).
final allSubtasksProvider = StreamProvider<List<Subtask>>((ref) {
  return ref.watch(taskRepositoryProvider).watchAllSubtasks();
});

/// Live search over tasks (title/notes/subtasks), habits (name/notes), and
/// tags (name). Case/diacritic-insensitive substring match.
final searchResultsProvider = Provider<SearchResults>((ref) {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) return const SearchResults();

  final tasks = ref.watch(allTasksProvider).value ?? const <Task>[];
  final habits = ref.watch(activeHabitsProvider).value ?? const <Habit>[];
  final tags = ref.watch(allTagsProvider).value ?? const <Tag>[];
  final subtasks = ref.watch(allSubtasksProvider).value ?? const <Subtask>[];
  final notes = ref.watch(allChatNotesProvider).value ?? const <ChatNote>[];

  final subtasksByTask = <int, List<String>>{};
  for (final s in subtasks) {
    (subtasksByTask[s.taskId] ??= []).add(s.title);
  }

  return SearchResults(
    tasks: tasks
        .where(
          (t) => searchMatchesAny(query, [
            t.title,
            t.notes,
            ...?subtasksByTask[t.id],
          ]),
        )
        .toList(),
    habits: habits
        .where((h) => searchMatchesAny(query, [h.name, h.notes]))
        .toList(),
    tags: tags.where((t) => searchMatches(query, t.name)).toList(),
    notes: notes.where((n) => searchMatches(query, n.body)).toList(),
  );
});
