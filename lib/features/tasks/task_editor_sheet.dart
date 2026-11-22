import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/task_repository.dart';
import '../../domain/enums.dart';
import '../../domain/recurrence_rule.dart';
import 'task_providers.dart';

/// Opens the task editor sheet. Pass [task] to edit, or null to create.
Future<void> showTaskEditor(BuildContext context, {Task? task}) {
  return M3EBottomSheet.showAdaptive<void>(
    context,
    title: task == null ? 'New task' : 'Edit task',
    initialValue: M3EBottomSheetValue.expanded,
    expandToFullScreen: true,
    builder: (context) => _TaskEditorForm(task: task),
  );
}

class _TaskEditorForm extends ConsumerStatefulWidget {
  const _TaskEditorForm({this.task});

  final Task? task;

  @override
  ConsumerState<_TaskEditorForm> createState() => _TaskEditorFormState();
}

class _TaskEditorFormState extends ConsumerState<_TaskEditorForm> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  DateTime? _dueAt;
  TaskPriority _priority = TaskPriority.none;
  RecurrenceRule? _recurrence;
  DateTime? _reminderAt;
  late Set<int> _tagIds;
  late List<_SubtaskDraft> _subtasks;
  bool _saving = false;

  bool get _isEdit => widget.task != null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _title = TextEditingController(text: t?.title ?? '');
    _notes = TextEditingController(text: t?.notes ?? '');
    _dueAt = t?.dueAt;
    _priority = t?.priority ?? TaskPriority.none;
    _recurrence = t?.recurrenceRule;
    _reminderAt = t?.reminderAt;
    _tagIds = {};
    _subtasks = [];
    if (t != null) {
      _loadExisting(t.id);
    }
  }

  Future<void> _loadExisting(int taskId) async {
    final repo = ref.read(taskRepositoryProvider);
    final tags = await repo.watchTags(taskId).first;
    final subs = await repo.getSubtasks(taskId);
    if (!mounted) return;
    setState(() {
      _tagIds = tags.map((t) => t.id).toSet();
      _subtasks = subs
          .map((s) => _SubtaskDraft(id: s.id, title: s.title, done: s.done))
          .toList();
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await M3EDatePicker.show(
      context,
      initialDate: _dueAt?.toLocal() ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    final existing = _dueAt?.toLocal();
    setState(() {
      _dueAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        existing?.hour ?? 9,
        existing?.minute ?? 0,
      );
    });
  }

  Future<void> _pickDueTime() async {
    final local = _dueAt?.toLocal() ?? DateTime.now();
    final picked = await M3ETimePicker.show(
      context,
      initialTime: M3ETime(hour: local.hour, minute: local.minute),
    );
    if (picked == null) return;
    final base = _dueAt?.toLocal() ?? DateTime.now();
    setState(() {
      _dueAt = DateTime(
        base.year,
        base.month,
        base.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _pickReminder() async {
    final base = _dueAt?.toLocal() ?? DateTime.now();
    final picked = await M3ETimePicker.show(
      context,
      initialTime: M3ETime(
        hour: _reminderAt?.toLocal().hour ?? 9,
        minute: _reminderAt?.toLocal().minute ?? 0,
      ),
    );
    if (picked == null) return;
    setState(() {
      _reminderAt = DateTime(
        base.year,
        base.month,
        base.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);

    final repo = ref.read(taskRepositoryProvider);
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    final dueUtc = _dueAt?.toUtc();
    final reminderUtc = _reminderAt?.toUtc();

    int taskId;
    if (_isEdit) {
      taskId = widget.task!.id;
      await repo.update(
        widget.task!.copyWith(
          title: title,
          notes: Value(notes),
          dueAt: Value(dueUtc),
          priority: _priority,
          recurrenceRule: Value(_recurrence),
          reminderAt: Value(reminderUtc),
        ),
      );
    } else {
      taskId = await repo.create(
        title: title,
        notes: notes,
        dueAt: dueUtc,
        priority: _priority,
        recurrence: _recurrence,
        reminderAt: reminderUtc,
      );
    }

    await repo.setTags(taskId, _tagIds);
    await _syncSubtasks(repo, taskId);

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _syncSubtasks(TaskRepository repo, int taskId) async {
    final existing = await repo.getSubtasks(taskId);
    final keptIds = _subtasks
        .where((s) => s.id != null)
        .map((s) => s.id!)
        .toSet();

    // Delete removed.
    for (final s in existing) {
      if (!keptIds.contains(s.id)) {
        await repo.deleteSubtask(s.id);
      }
    }
    // Add new / update existing.
    for (var i = 0; i < _subtasks.length; i++) {
      final draft = _subtasks[i];
      if (draft.title.trim().isEmpty) continue;
      if (draft.id == null) {
        await repo.addSubtask(taskId, draft.title.trim(), position: i);
      } else {
        final original = existing.firstWhere((s) => s.id == draft.id);
        if (original.title != draft.title ||
            original.done != draft.done ||
            original.position != i) {
          await repo.updateSubtask(
            original.copyWith(
              title: draft.title,
              done: draft.done,
              position: i,
            ),
          );
        }
      }
    }
  }

  Future<void> _delete() async {
    if (!_isEdit) return;
    await ref.read(taskRepositoryProvider).delete(widget.task!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final tags = ref.watch(allTagsProvider).value ?? const <Tag>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: ListView(
        shrinkWrap: true,
        children: [
          M3ETextField(
            controller: _title,
            label: 'Title',
            autofocus: !_isEdit,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          M3ETextField(
            controller: _notes,
            label: 'Notes',
            maxLines: 3,
            minLines: 1,
          ),
          const SizedBox(height: 20),
          _SectionLabel('Due date', theme),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: M3EButton.icon(
                  onPressed: _pickDueDate,
                  style: M3EButtonStyle.tonal,
                  icon: const Icon(M3EIcons.calendar_today),
                  label: Text(
                    _dueAt == null ? 'Set date' : _formatDate(_dueAt!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: M3EButton.icon(
                  onPressed: _dueAt == null ? null : _pickDueTime,
                  style: M3EButtonStyle.tonal,
                  icon: const Icon(M3EIcons.schedule),
                  label: Text(_dueAt == null ? 'Time' : _formatTime(_dueAt!)),
                ),
              ),
              if (_dueAt != null) ...[
                const SizedBox(width: 8),
                M3EIconButton(
                  variant: M3EIconButtonVariant.standard,
                  icon: const Icon(M3EIcons.close),
                  tooltip: 'Clear due date',
                  onPressed: () => setState(() => _dueAt = null),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          _SectionLabel('Priority', theme),
          const SizedBox(height: 8),
          M3ESegmentedButton<TaskPriority>(
            selected: {_priority},
            onSelectionChanged: (s) => setState(() => _priority = s.first),
            segments: const [
              M3ESegment(value: TaskPriority.none, label: 'None'),
              M3ESegment(value: TaskPriority.low, label: 'Low'),
              M3ESegment(value: TaskPriority.medium, label: 'Med'),
              M3ESegment(value: TaskPriority.high, label: 'High'),
            ],
          ),
          const SizedBox(height: 20),
          _SectionLabel('Repeat', theme),
          const SizedBox(height: 8),
          _RecurrencePicker(
            rule: _recurrence,
            onChanged: (r) => setState(() => _recurrence = r),
          ),
          const SizedBox(height: 20),
          _SectionLabel('Reminder', theme),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: M3EButton.icon(
                  onPressed: _pickReminder,
                  style: M3EButtonStyle.tonal,
                  icon: const Icon(M3EIcons.notifications),
                  label: Text(
                    _reminderAt == null
                        ? 'Set reminder'
                        : _formatTime(_reminderAt!),
                  ),
                ),
              ),
              if (_reminderAt != null) ...[
                const SizedBox(width: 8),
                M3EIconButton(
                  variant: M3EIconButtonVariant.standard,
                  icon: const Icon(M3EIcons.close),
                  tooltip: 'Clear reminder',
                  onPressed: () => setState(() => _reminderAt = null),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          _SectionLabel('Tags', theme),
          const SizedBox(height: 8),
          _TagSelector(
            tags: tags,
            selected: _tagIds,
            onToggle: (id) => setState(() {
              _tagIds.contains(id) ? _tagIds.remove(id) : _tagIds.add(id);
            }),
            onCreate: _createTag,
          ),
          const SizedBox(height: 20),
          _SectionLabel('Subtasks', theme),
          const SizedBox(height: 8),
          _SubtaskEditor(
            subtasks: _subtasks,
            onChanged: (list) => setState(() => _subtasks = list),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              if (_isEdit)
                M3EIconButton(
                  variant: M3EIconButtonVariant.standard,
                  icon: Icon(M3EIcons.delete, color: theme.colorScheme.error),
                  tooltip: 'Delete task',
                  onPressed: _delete,
                ),
              const Spacer(),
              M3EButton(
                onPressed: _saving ? null : _save,
                label: Text(_isEdit ? 'Save' : 'Add task'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _createTag() async {
    final result = await M3EDialog.show<String>(
      context,
      dialog: const _NewTagDialog(),
    );
    if (result == null || result.trim().isEmpty) return;
    final id = await ref
        .read(tagRepositoryProvider)
        .create(name: result.trim(), color: 0xFF2DD4A8);
    setState(() => _tagIds.add(id));
  }

  String _formatDate(DateTime d) {
    final l = d.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime d) {
    final l = d.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

class _SubtaskDraft {
  _SubtaskDraft({this.id, required this.title, this.done = false});
  final int? id;
  String title;
  bool done;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, this.theme);
  final String text;
  final M3EThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: theme.typography.emphasized.titleSmall.copyWith(
        color: theme.colorScheme.primary,
      ),
    );
  }
}

class _RecurrencePicker extends StatelessWidget {
  const _RecurrencePicker({required this.rule, required this.onChanged});

  final RecurrenceRule? rule;
  final ValueChanged<RecurrenceRule?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = rule?.unit;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        M3EChip(
          label: 'Never',
          type: M3EChipType.filter,
          selected: rule == null,
          onPressed: () => onChanged(null),
        ),
        M3EChip(
          label: 'Daily',
          type: M3EChipType.filter,
          selected: selected == RecurrenceUnit.day && rule?.interval == 1,
          onPressed: () =>
              onChanged(const RecurrenceRule(unit: RecurrenceUnit.day)),
        ),
        M3EChip(
          label: 'Weekly',
          type: M3EChipType.filter,
          selected: selected == RecurrenceUnit.week && rule?.interval == 1,
          onPressed: () =>
              onChanged(const RecurrenceRule(unit: RecurrenceUnit.week)),
        ),
        M3EChip(
          label: 'Monthly',
          type: M3EChipType.filter,
          selected: selected == RecurrenceUnit.month && rule?.interval == 1,
          onPressed: () =>
              onChanged(const RecurrenceRule(unit: RecurrenceUnit.month)),
        ),
      ],
    );
  }
}

class _TagSelector extends StatelessWidget {
  const _TagSelector({
    required this.tags,
    required this.selected,
    required this.onToggle,
    required this.onCreate,
  });

  final List<Tag> tags;
  final Set<int> selected;
  final ValueChanged<int> onToggle;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tag in tags)
          M3EChip(
            label: tag.name,
            type: M3EChipType.filter,
            selected: selected.contains(tag.id),
            onPressed: () => onToggle(tag.id),
          ),
        M3EChip(
          label: 'New tag',
          type: M3EChipType.assist,
          leading: const Icon(M3EIcons.add, size: 18),
          onPressed: onCreate,
        ),
      ],
    );
  }
}

class _SubtaskEditor extends StatefulWidget {
  const _SubtaskEditor({required this.subtasks, required this.onChanged});

  final List<_SubtaskDraft> subtasks;
  final ValueChanged<List<_SubtaskDraft>> onChanged;

  @override
  State<_SubtaskEditor> createState() => _SubtaskEditorState();
}

class _SubtaskEditorState extends State<_SubtaskEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onChanged([...widget.subtasks, _SubtaskDraft(title: text)]);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.subtasks.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                M3ECheckbox(
                  value: widget.subtasks[i].done,
                  onChanged: (v) {
                    final next = [...widget.subtasks];
                    next[i] = _SubtaskDraft(
                      id: next[i].id,
                      title: next[i].title,
                      done: v ?? false,
                    );
                    widget.onChanged(next);
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.subtasks[i].title,
                    style: theme.typography.baseline.bodyMedium.copyWith(
                      decoration: widget.subtasks[i].done
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                M3EIconButton(
                  variant: M3EIconButtonVariant.standard,
                  icon: const Icon(M3EIcons.close, size: 18),
                  tooltip: 'Remove subtask',
                  onPressed: () {
                    final next = [...widget.subtasks]..removeAt(i);
                    widget.onChanged(next);
                  },
                ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: M3ETextField(
                controller: _controller,
                label: 'Add subtask',
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            M3EIconButton(
              variant: M3EIconButtonVariant.tonal,
              icon: const Icon(M3EIcons.add),
              tooltip: 'Add subtask',
              onPressed: _add,
            ),
          ],
        ),
      ],
    );
  }
}

class _NewTagDialog extends StatefulWidget {
  const _NewTagDialog();

  @override
  State<_NewTagDialog> createState() => _NewTagDialogState();
}

class _NewTagDialogState extends State<_NewTagDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return M3EDialog(
      title: 'New tag',
      content: M3ETextField(
        controller: _controller,
        label: 'Tag name',
        autofocus: true,
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        M3EButton(
          style: M3EButtonStyle.text,
          onPressed: () => Navigator.of(context).pop(),
          label: const Text('Cancel'),
        ),
        M3EButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          label: const Text('Create'),
        ),
      ],
    );
  }
}
