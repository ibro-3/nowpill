import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_surfaces.dart';
import '../../data/db/app_database.dart';
import '../../l10n/generated/app_localizations.dart';
import '../habits/habit_detail_screen.dart';
import '../habits/habit_icons.dart';
import '../tasks/task_editor_sheet.dart';
import 'search_providers.dart';

/// Global search across tasks (title/notes/subtasks), habits, tags, and
/// personal chat notes.
/// Live-as-you-type; results grouped by entity with tap-through to the
/// existing editors/detail screens.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Start each visit with a clean query.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(searchQueryProvider.notifier).set('');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(searchQueryProvider);
    final results = ref.watch(searchResultsProvider);
    final hasQuery = query.trim().isNotEmpty;

    return Scaffold(
      appBar: M3EAppBar.top(
        title: Text(l10n.search),
        leading: M3EIconButton(
          variant: M3EIconButtonVariant.standard,
          icon: const Icon(M3EIcons.arrow_back),
          tooltip: l10n.back,
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            // M3E search bar: the recommended contained search style with
            // focus-expand behavior, instead of a plain text field.
            child: M3ESearchBar(
              controller: _controller,
              hintText: l10n.searchHint,
              autoFocus: true,
              leading: const Icon(M3EIcons.search),
              onChanged: (v) => ref.read(searchQueryProvider.notifier).set(v),
            ),
          ),
          Expanded(
            child: !hasQuery
                ? _Hint(theme: theme, l10n: l10n)
                : results.isEmpty
                ? _NoResults(theme: theme, l10n: l10n, query: query)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      if (results.tasks.isNotEmpty) ...[
                        _GroupHeader(title: l10n.searchTasks, theme: theme),
                        for (final task in results.tasks)
                          _TaskResult(task: task, theme: theme),
                      ],
                      if (results.habits.isNotEmpty) ...[
                        _GroupHeader(title: l10n.searchHabits, theme: theme),
                        for (final habit in results.habits)
                          _HabitResult(habit: habit, theme: theme),
                      ],
                      if (results.tags.isNotEmpty) ...[
                        _GroupHeader(title: l10n.searchTags, theme: theme),
                        for (final tag in results.tags)
                          _TagResult(tag: tag, theme: theme),
                      ],
                      if (results.notes.isNotEmpty) ...[
                        _GroupHeader(title: l10n.searchNotes, theme: theme),
                        for (final note in results.notes)
                          _NoteResult(note: note, theme: theme),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.theme, required this.l10n});

  final M3EThemeData theme;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              M3EIcons.search,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.searchEmptyHint,
              textAlign: TextAlign.center,
              style: theme.typography.baseline.bodyMedium.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({
    required this.theme,
    required this.l10n,
    required this.query,
  });

  final M3EThemeData theme;
  final AppLocalizations l10n;
  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          l10n.searchNoResults(query),
          key: const ValueKey('search-no-results'),
          textAlign: TextAlign.center,
          style: theme.typography.baseline.bodyMedium.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.theme});

  final String title;
  final M3EThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6, left: 4),
      child: Text(
        title,
        style: theme.typography.emphasized.titleSmall.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _TaskResult extends StatelessWidget {
  const _TaskResult({required this.task, required this.theme});

  final Task task;
  final M3EThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: M3ECard(
        variant: M3ECardVariant.filled,
        onPressed: () => showTaskEditor(context, task: task),
        // 12dp vertical padding + 24dp text line = a 48dp card target.
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              task.completedAt != null
                  ? M3EIcons.check_circle
                  : M3EIcons.radio_button_unchecked,
              size: 18,
              color: task.completedAt != null
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.baseline.bodyLarge.copyWith(
                  decoration: task.completedAt != null
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitResult extends StatelessWidget {
  const _HabitResult({required this.habit, required this.theme});

  final Habit habit;
  final M3EThemeData theme;

  @override
  Widget build(BuildContext context) {
    final color = Color(habit.color);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: M3ECard(
        variant: M3ECardVariant.filled,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => HabitDetailScreen(habitId: habit.id),
          ),
        ),
        // 12dp vertical padding + 24dp text line = a 48dp card target.
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              habitIconForKey(habit.iconKey),
              size: 18,
              color: AppSurfaces.graphic(theme.colorScheme, color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                habit.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.baseline.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteResult extends StatelessWidget {
  const _NoteResult({required this.note, required this.theme});

  final ChatNote note;
  final M3EThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: M3ECard(
        variant: M3ECardVariant.filled,
        // Opens the stream; there is no per-note deep link in v1.
        onPressed: () => context.go(AppRoutes.chat),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              M3EIcons.chat_bubble_outline,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                note.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.baseline.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagResult extends StatelessWidget {
  const _TagResult({required this.tag, required this.theme});

  final Tag tag;
  final M3EThemeData theme;

  @override
  Widget build(BuildContext context) {
    final color = Color(tag.color);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: M3ECard(
        variant: M3ECardVariant.filled,
        // 12dp vertical padding + 24dp text line = a 48dp card target.
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              M3EIcons.tag,
              size: 18,
              color: AppSurfaces.graphic(theme.colorScheme, color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '#${tag.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.baseline.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
