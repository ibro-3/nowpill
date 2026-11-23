import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/providers.dart';
import '../../domain/enums.dart';
import '../../l10n/generated/app_localizations.dart';
import 'habit_icons.dart';

/// Opens the habit editor sheet. Pass [habit] to edit, or null to create.
Future<void> showHabitEditor(BuildContext context, {Habit? habit}) {
  final l10n = AppLocalizations.of(context);
  return M3EBottomSheet.showAdaptive<void>(
    context,
    title: habit == null ? l10n.newHabit : l10n.editHabit,
    initialValue: M3EBottomSheetValue.expanded,
    expandToFullScreen: true,
    builder: (context) => _HabitEditorForm(habit: habit),
  );
}

class _HabitEditorForm extends ConsumerStatefulWidget {
  const _HabitEditorForm({this.habit});

  final Habit? habit;

  @override
  ConsumerState<_HabitEditorForm> createState() => _HabitEditorFormState();
}

class _HabitEditorFormState extends ConsumerState<_HabitEditorForm> {
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late String _iconKey;
  late int _color;
  late HabitScheduleType _scheduleType;
  late Set<int> _weekdays;
  late int _targetPerWeek;
  DateTime? _reminderTime;
  late FreezeMode _freezeMode;
  bool _saving = false;

  bool get _isEdit => widget.habit != null;

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    _name = TextEditingController(text: h?.name ?? '');
    _notes = TextEditingController(text: h?.notes ?? '');
    _iconKey = h?.iconKey ?? 'spark';
    _color = h?.color ?? kHabitColors.first;
    _scheduleType = h?.scheduleType ?? HabitScheduleType.daily;
    _weekdays = (h?.weekdays ?? const []).toSet();
    _targetPerWeek = h?.targetPerWeek ?? 3;
    _reminderTime = h?.reminderTime;
    _freezeMode = h?.freezeMode ?? FreezeMode.auto;
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickReminder() async {
    final local = _reminderTime?.toLocal();
    final picked = await M3ETimePicker.show(
      context,
      initialTime: M3ETime(hour: local?.hour ?? 9, minute: local?.minute ?? 0),
    );
    if (picked == null) return;
    final now = DateTime.now();
    setState(() {
      _reminderTime = DateTime(
        now.year,
        now.month,
        now.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    if (_scheduleType == HabitScheduleType.weekdays && _weekdays.isEmpty) {
      return;
    }
    setState(() => _saving = true);

    final repo = ref.read(habitRepositoryProvider);
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    final weekdays = _scheduleType == HabitScheduleType.weekdays
        ? (_weekdays.toList()..sort())
        : null;
    final target = _scheduleType == HabitScheduleType.weeklyTarget
        ? _targetPerWeek
        : null;
    final reminderUtc = _reminderTime?.toUtc();

    if (_isEdit) {
      await repo.update(
        widget.habit!.copyWith(
          name: name,
          notes: Value(notes),
          iconKey: _iconKey,
          color: _color,
          scheduleType: _scheduleType,
          weekdays: Value(weekdays),
          targetPerWeek: Value(target),
          reminderTime: Value(reminderUtc),
          freezeMode: _freezeMode,
        ),
      );
    } else {
      await repo.create(
        name: name,
        color: _color,
        notes: notes,
        iconKey: _iconKey,
        scheduleType: _scheduleType,
        weekdays: weekdays,
        targetPerWeek: target,
        reminderTime: reminderUtc,
        freezeMode: _freezeMode,
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: ListView(
        shrinkWrap: true,
        children: [
          M3ETextField(
            controller: _name,
            label: l10n.habitName,
            autofocus: !_isEdit,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          M3ETextField(
            controller: _notes,
            label: l10n.notes,
            maxLines: 2,
            minLines: 1,
          ),
          const SizedBox(height: 20),
          _SectionLabel(l10n.icon, theme),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in kHabitIcons)
                _IconChoice(
                  icon: h.icon,
                  label: habitIconLabel(l10n, h.key),
                  selected: _iconKey == h.key,
                  color: Color(_color),
                  onTap: () => setState(() => _iconKey = h.key),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionLabel(l10n.color, theme),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in kHabitColors)
                _ColorChoice(
                  color: Color(c),
                  selected: _color == c,
                  onTap: () => setState(() => _color = c),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionLabel(l10n.schedule, theme),
          const SizedBox(height: 8),
          M3ESegmentedButton<HabitScheduleType>(
            selected: {_scheduleType},
            onSelectionChanged: (s) => setState(() => _scheduleType = s.first),
            segments: [
              M3ESegment(
                value: HabitScheduleType.daily,
                label: l10n.scheduleDaily,
              ),
              M3ESegment(
                value: HabitScheduleType.weekdays,
                label: l10n.scheduleWeekdays,
              ),
              M3ESegment(
                value: HabitScheduleType.weeklyTarget,
                label: l10n.scheduleWeekly,
              ),
            ],
          ),
          if (_scheduleType == HabitScheduleType.weekdays) ...[
            const SizedBox(height: 12),
            _WeekdayPicker(
              selected: _weekdays,
              onToggle: (d) => setState(() {
                _weekdays.contains(d) ? _weekdays.remove(d) : _weekdays.add(d);
              }),
            ),
          ],
          if (_scheduleType == HabitScheduleType.weeklyTarget) ...[
            const SizedBox(height: 12),
            _TargetPicker(
              value: _targetPerWeek,
              onChanged: (v) => setState(() => _targetPerWeek = v),
            ),
          ],
          const SizedBox(height: 20),
          _SectionLabel(l10n.reminder, theme),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: M3EButton.icon(
                  onPressed: _pickReminder,
                  style: M3EButtonStyle.tonal,
                  icon: const Icon(M3EIcons.notifications),
                  label: Text(
                    _reminderTime == null
                        ? l10n.setReminder
                        : _formatTime(_reminderTime!),
                  ),
                ),
              ),
              if (_reminderTime != null) ...[
                const SizedBox(width: 8),
                M3EIconButton(
                  variant: M3EIconButtonVariant.standard,
                  icon: const Icon(M3EIcons.close),
                  tooltip: l10n.clearReminder,
                  onPressed: () => setState(() => _reminderTime = null),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          _SectionLabel(l10n.freezeTokens, theme),
          const SizedBox(height: 8),
          M3ESegmentedButton<FreezeMode>(
            selected: {_freezeMode},
            onSelectionChanged: (s) => setState(() => _freezeMode = s.first),
            segments: [
              M3ESegment(value: FreezeMode.auto, label: l10n.freezeAuto),
              M3ESegment(value: FreezeMode.manual, label: l10n.freezeManual),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _freezeMode == FreezeMode.auto
                ? l10n.freezeAutoDesc
                : l10n.freezeManualDesc,
            style: theme.typography.baseline.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          Align(
            alignment: Alignment.centerRight,
            child: M3EButton(
              onPressed: _saving ? null : _save,
              label: Text(_isEdit ? l10n.save : l10n.addHabit),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime d) {
    final l = d.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
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

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: M3EShapeContainer(
          kind: selected ? M3EShapeKind.cookie6Sided : M3EShapeKind.circle,
          width: 44,
          height: 44,
          color: selected
              ? color.withValues(alpha: 0.2)
              : theme.colorScheme.surfaceContainerHigh,
          child: Icon(
            icon,
            size: 22,
            color: selected ? color : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? theme.colorScheme.onSurface : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: selected
            ? Icon(M3EIcons.check, size: 18, color: theme.colorScheme.surface)
            : null,
      ),
    );
  }
}

class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.selected, required this.onToggle});

  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var d = 1; d <= 7; d++)
          M3EChip(
            label: labels[d - 1],
            type: M3EChipType.filter,
            selected: selected.contains(d),
            onPressed: () => onToggle(d),
          ),
      ],
    );
  }
}

class _TargetPicker extends StatelessWidget {
  const _TargetPicker({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Text(l10n.goal, style: theme.typography.baseline.bodyMedium),
        const SizedBox(width: 12),
        M3EIconButton(
          variant: M3EIconButtonVariant.tonal,
          icon: const Icon(M3EIcons.remove),
          tooltip: l10n.decrease,
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.goalPerWeek(value),
            style: theme.typography.emphasized.titleMedium,
          ),
        ),
        M3EIconButton(
          variant: M3EIconButtonVariant.tonal,
          icon: const Icon(M3EIcons.add),
          tooltip: l10n.increase,
          onPressed: value < 7 ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}
