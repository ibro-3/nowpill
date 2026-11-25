import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/motion/shape_morph.dart';
import '../../core/motion/spring_press.dart';
import '../../core/theme/app_surfaces.dart';
import '../../core/widgets/chip_hit_area.dart';
import '../../core/widgets/connected_choice_group.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/providers.dart';
import '../../domain/date_utils.dart';
import '../../domain/enums.dart';
import '../../l10n/generated/app_localizations.dart';
import 'habit_icons.dart';
import 'habit_providers.dart';

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
  late final TextEditingController _targetAmount;
  late String _iconKey;
  late int _color;
  late HabitScheduleType _scheduleType;
  late Set<int> _weekdays;
  late int _targetPerWeek;
  DateTime? _reminderTime;
  late FreezeMode _freezeMode;
  late HabitKind _kind;
  DateTime? _quitDate;
  int? _routineId;
  bool _saving = false;

  bool get _isEdit => widget.habit != null;

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    _name = TextEditingController(text: h?.name ?? '');
    _notes = TextEditingController(text: h?.notes ?? '');
    final amount = h?.targetAmount;
    _targetAmount = TextEditingController(
      text: amount == null
          ? ''
          : (amount == amount.roundToDouble()
                ? amount.toInt().toString()
                : amount.toString()),
    );
    _iconKey = h?.iconKey ?? 'spark';
    _color = h?.color ?? kHabitColors.first;
    _scheduleType = h?.scheduleType ?? HabitScheduleType.daily;
    _weekdays = (h?.weekdays ?? const []).toSet();
    _targetPerWeek = h?.targetPerWeek ?? 3;
    _reminderTime = h?.reminderTime;
    _freezeMode = h?.freezeMode ?? FreezeMode.auto;
    _kind = h?.kind ?? HabitKind.build;
    _quitDate = _kind == HabitKind.quit
        ? (h?.createdAt.toLocal() ?? DateTime.now())
        : null;
    _routineId = h?.routineId;
  }

  Future<void> _createRoutine() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await M3EDialog.show<String>(
      context,
      dialog: M3EDialog(
        title: l10n.routineNew,
        content: M3ETextField(
          controller: controller,
          label: l10n.routineName,
          autofocus: true,
        ),
        actions: [
          M3EButton(
            style: M3EButtonStyle.text,
            label: Text(l10n.cancel),
            onPressed: () => Navigator.of(context).pop(),
          ),
          M3EButton(
            key: const ValueKey('routine-save'),
            style: M3EButtonStyle.text,
            label: Text(l10n.save),
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final repo = ref.read(habitRepositoryProvider);
    final existing = await repo.getAllRoutines();
    if (existing.any((r) => r.name.toLowerCase() == name.toLowerCase())) {
      final match = existing.firstWhere(
        (r) => r.name.toLowerCase() == name.toLowerCase(),
      );
      setState(() => _routineId = match.id);
      return;
    }
    final id = await repo.createRoutine(
      name,
      kHabitColors.first,
      sortOrder: existing.isEmpty ? 0 : existing.last.sortOrder + 1,
    );
    if (mounted) setState(() => _routineId = id);
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _targetAmount.dispose();
    super.dispose();
  }

  Future<void> _pickQuitDate() async {
    final now = DateTime.now();
    final picked = await M3EDatePicker.show(
      context,
      initialDate: _quitDate ?? now,
      firstDate: DateTime(now.year - 20),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      _quitDate = DateTime(picked.year, picked.month, picked.day);
    });
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
    // Kind is locked once a habit has history: converting past check-ins into
    // clean days would silently rewrite the meaning of its streak.
    var kind = _kind;
    if (_isEdit && widget.habit!.kind != kind) {
      final id = widget.habit!.id;
      if ((await repo.getCheckins(id)).isNotEmpty ||
          (await repo.getRelapses(id)).isNotEmpty) {
        kind = widget.habit!.kind;
      }
    }
    final isQuit = kind == HabitKind.quit;
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    final weekdays = _scheduleType == HabitScheduleType.weekdays
        ? (_weekdays.toList()..sort())
        : null;
    final target = _scheduleType == HabitScheduleType.weeklyTarget
        ? _targetPerWeek
        : null;
    final reminderUtc = _reminderTime?.toUtc();
    final amountText = _targetAmount.text.trim().replaceAll(',', '.');
    final parsedAmount = double.tryParse(amountText);
    final targetAmount = !isQuit && parsedAmount != null && parsedAmount > 0
        ? parsedAmount
        : null;
    final createdAt = isQuit && _quitDate != null ? _quitDate!.toUtc() : null;

    int habitId;
    if (_isEdit) {
      habitId = widget.habit!.id;
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
          freezeMode: isQuit ? FreezeMode.auto : _freezeMode,
          targetAmount: Value(targetAmount),
          kind: kind,
          createdAt: createdAt ?? widget.habit!.createdAt,
        ),
      );
    } else {
      habitId = await repo.create(
        name: name,
        color: _color,
        notes: notes,
        iconKey: _iconKey,
        scheduleType: _scheduleType,
        weekdays: weekdays,
        targetPerWeek: target,
        reminderTime: reminderUtc,
        freezeMode: isQuit ? FreezeMode.auto : _freezeMode,
        targetAmount: targetAmount,
        kind: kind,
        createdAt: createdAt,
      );
    }
    await repo.setHabitRoutine(habitId, _routineId);

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
          _SectionLabel(l10n.habitKind, theme),
          const SizedBox(height: 8),
          ConnectedChoiceGroup<HabitKind>(
            values: HabitKind.values,
            labels: [l10n.kindBuild, l10n.kindQuit],
            selected: _kind,
            onChanged: (value) => setState(() => _kind = value),
          ),
          const SizedBox(height: 8),
          Text(
            _kind == HabitKind.quit ? l10n.kindQuitDesc : l10n.kindBuildDesc,
            style: theme.typography.baseline.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          _SectionLabel(l10n.routine, theme),
          const SizedBox(height: 8),
          Text(
            l10n.routinePickerHint,
            style: theme.typography.baseline.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ChipHitArea(
                  onTap: () => setState(() => _routineId = null),
                  child: M3EChip(
                    label: l10n.unrouted,
                    type: M3EChipType.filter,
                    selected: _routineId == null,
                    onPressed: () => setState(() => _routineId = null),
                  ),
                ),
                const SizedBox(width: 8),
                for (final routine
                    in ref.watch(allRoutinesProvider).value ??
                        const <Routine>[])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChipHitArea(
                      onTap: () => setState(() => _routineId = routine.id),
                      child: M3EChip(
                        label: routine.name,
                        type: M3EChipType.filter,
                        selected: _routineId == routine.id,
                        onPressed: () =>
                            setState(() => _routineId = routine.id),
                      ),
                    ),
                  ),
                ChipHitArea(
                  onTap: _createRoutine,
                  child: M3EChip(
                    label: l10n.routineNew,
                    type: M3EChipType.assist,
                    leading: const Icon(M3EIcons.add, size: 18),
                    onPressed: _createRoutine,
                  ),
                ),
              ],
            ),
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
          if (_kind == HabitKind.quit) ...[
            const SizedBox(height: 20),
            _SectionLabel(l10n.quitDate, theme),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: M3EButton.icon(
                    onPressed: _pickQuitDate,
                    style: M3EButtonStyle.tonal,
                    icon: const Icon(M3EIcons.calendar_today),
                    label: Text(
                      _quitDate == null
                          ? l10n.setQuitDate
                          : formatDate(_quitDate!),
                    ),
                  ),
                ),
                if (_quitDate != null) ...[
                  const SizedBox(width: 8),
                  M3EIconButton(
                    variant: M3EIconButtonVariant.standard,
                    icon: const Icon(M3EIcons.close),
                    tooltip: l10n.clearQuitDate,
                    onPressed: () => setState(() => _quitDate = DateTime.now()),
                  ),
                ],
              ],
            ),
          ],
          if (_kind == HabitKind.build) ...[
            const SizedBox(height: 20),
            _SectionLabel(l10n.schedule, theme),
            const SizedBox(height: 8),
            ConnectedChoiceGroup<HabitScheduleType>(
              values: HabitScheduleType.values,
              labels: [
                l10n.scheduleDaily,
                l10n.scheduleWeekdays,
                l10n.scheduleWeekly,
              ],
              selected: _scheduleType,
              onChanged: (value) => setState(() => _scheduleType = value),
            ),
            if (_scheduleType == HabitScheduleType.weekdays) ...[
              const SizedBox(height: 12),
              _WeekdayPicker(
                selected: _weekdays,
                onToggle: (d) => setState(() {
                  _weekdays.contains(d)
                      ? _weekdays.remove(d)
                      : _weekdays.add(d);
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
            _SectionLabel(l10n.dailyGoal, theme),
            const SizedBox(height: 8),
            M3ETextField(
              controller: _targetAmount,
              label: l10n.dailyGoalHint,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.dailyGoalDesc,
              style: theme.typography.baseline.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
          if (_kind == HabitKind.build) ...[
            const SizedBox(height: 20),
            _SectionLabel(l10n.freezeTokens, theme),
            const SizedBox(height: 8),
            ConnectedChoiceGroup<FreezeMode>(
              values: FreezeMode.values,
              labels: [l10n.freezeAuto, l10n.freezeManual],
              selected: _freezeMode,
              onChanged: (value) => setState(() => _freezeMode = value),
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
          ],
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
      child: SpringPress(
        child: GestureDetector(
          onTap: onTap,
          // 48dp hit box around the 44dp visual.
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: MorphingShape(
                from: M3EShapeKind.circle,
                to: M3EShapeKind.cookie6Sided,
                active: selected,
                size: 44,
                color: theme.colorScheme.surfaceContainerHigh,
                activeColor: color.withValues(alpha: 0.2),
                childBuilder: (t) => Icon(
                  icon,
                  size: 22 * (0.96 + 0.04 * t),
                  // The wash is a fill; the foreground stays a role color.
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
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
    return SpringPress(
      child: GestureDetector(
        onTap: onTap,
        // 48dp hit box around the 36dp swatch.
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.onSurface
                      : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: selected
                  ? Icon(
                      M3EIcons.check,
                      size: 18,
                      color: AppSurfaces.onAccent(theme.colorScheme, color),
                    )
                  : null,
            ),
          ),
        ),
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
    // Wrap instead of Row: seven chips overflowed at 320dp. Each gets a 48dp
    // box so the row has room for M3's minimum target height.
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        for (var d = 1; d <= 7; d++)
          ChipHitArea(
            onTap: () => onToggle(d),
            child: M3EChip(
              label: labels[d - 1],
              type: M3EChipType.filter,
              selected: selected.contains(d),
              onPressed: () => onToggle(d),
            ),
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
            style: theme.typography.baseline.titleMedium,
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
