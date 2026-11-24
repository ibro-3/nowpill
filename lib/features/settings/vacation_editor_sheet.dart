import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/providers.dart';
import '../../domain/date_utils.dart';
import '../../domain/enums.dart';
import '../../domain/vacation.dart' as vacation_domain;
import '../../l10n/generated/app_localizations.dart';
import '../habits/habit_providers.dart';

const Uuid _uuid = Uuid();

/// Opens the vacation editor. Pass a period (and its scopes) to edit it, or
/// null to plan a new one. Returns true when a change was saved.
Future<bool?> showVacationEditor(
  BuildContext context, {
  VacationPeriod? period,
  List<VacationScope> scopes = const [],
}) {
  final l10n = AppLocalizations.of(context);
  return M3EBottomSheet.showAdaptive<bool>(
    context,
    title: period == null ? l10n.vacationAdd : l10n.vacationEdit,
    initialValue: M3EBottomSheetValue.expanded,
    expandToFullScreen: true,
    builder: (context) => VacationEditorForm(period: period, scopes: scopes),
  );
}

class VacationEditorForm extends ConsumerStatefulWidget {
  const VacationEditorForm({super.key, this.period, this.scopes = const []});

  final VacationPeriod? period;
  final List<VacationScope> scopes;

  @override
  ConsumerState<VacationEditorForm> createState() => VacationEditorFormState();
}

class VacationEditorFormState extends ConsumerState<VacationEditorForm> {
  late DateTime _start;
  late DateTime _end;
  late bool _allHabits;
  late Set<String> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = widget.period == null ? now : parseDate(widget.period!.startDate);
    _end = widget.period == null
        ? now.add(const Duration(days: 2))
        : parseDate(widget.period!.endDate);
    _allHabits = widget.period?.allHabits ?? true;
    _selected = {
      for (final s in widget.scopes) '${s.targetKind.index}:${s.targetUuid}',
    };
  }

  Future<void> _pickDate({required bool start}) async {
    final picked = await M3EDatePicker.show(
      context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final from = formatDate(_start);
    final to = formatDate(_end);
    if (from.compareTo(to) > 0) {
      M3ESnackbar.show(context, message: l10n.vacationInvalid);
      return;
    }
    if (!_allHabits && _selected.isEmpty) {
      M3ESnackbar.show(context, message: l10n.vacationScopeHint);
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(habitRepositoryProvider);
    final period = widget.period;
    final uuid = period?.uuid ?? _uuid.v4();
    if (period == null) {
      await repo.createVacation(from, to, allHabits: _allHabits, uuid: uuid);
    } else {
      await repo.updateVacation(
        period.copyWith(startDate: from, endDate: to, allHabits: _allHabits),
      );
    }
    final targets = <vacation_domain.VacationScope>[];
    for (final key in _selected) {
      final parts = key.split(':');
      final existing = widget.scopes
          .where((s) => key == '${s.targetKind.index}:${s.targetUuid}')
          .firstOrNull;
      targets.add(
        vacation_domain.VacationScope(
          periodUuid: uuid,
          targetKind: parts.first == 'r'
              ? VacationTargetKind.routine
              : VacationTargetKind.habit,
          targetUuid: parts.sublist(1).join(':'),
          uuid: existing?.uuid ?? '',
          updatedAt: existing?.updatedAt.millisecondsSinceEpoch ?? 0,
        ),
      );
    }
    await repo.replaceVacationScopes(uuid, targets);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = M3ETheme.of(context);
    final routines = ref.watch(allRoutinesProvider).value ?? const <Routine>[];
    final habits = ref.watch(activeHabitsProvider).value ?? const <Habit>[];

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _SectionLabel(l10n.vacationStart, theme),
        const SizedBox(height: 8),
        M3EButton.icon(
          style: M3EButtonStyle.tonal,
          icon: const Icon(M3EIcons.calendar_today),
          label: Text(formatDate(_start)),
          onPressed: () => _pickDate(start: true),
        ),
        const SizedBox(height: 16),
        _SectionLabel(l10n.vacationEnd, theme),
        const SizedBox(height: 8),
        M3EButton.icon(
          style: M3EButtonStyle.tonal,
          icon: const Icon(M3EIcons.calendar_today),
          label: Text(formatDate(_end)),
          onPressed: () => _pickDate(start: false),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.vacationAllHabits,
                    style: theme.typography.emphasized.titleMedium,
                  ),
                  Text(
                    l10n.vacationDescription,
                    style: theme.typography.baseline.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            M3ESwitch(
              key: const ValueKey('vacation-all-habits'),
              value: _allHabits,
              onChanged: (v) => setState(() => _allHabits = v),
            ),
          ],
        ),
        if (!_allHabits) ...[
          const SizedBox(height: 20),
          _SectionLabel(l10n.vacationScopeTitle, theme),
          if (routines.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.settingsRoutines,
              style: theme.typography.emphasized.titleSmall,
            ),
            for (final routine in routines)
              _ScopeTile(
                key: ValueKey('vacation-scope-r-${routine.uuid}'),
                label: routine.name,
                color: Color(routine.color),
                selected: _selected.contains('r:${routine.uuid}'),
                onChanged: (v) => setState(() {
                  if (v) {
                    _selected.add('r:${routine.uuid}');
                  } else {
                    _selected.remove('r:${routine.uuid}');
                  }
                }),
              ),
          ],
          const SizedBox(height: 12),
          Text(l10n.navHabits, style: theme.typography.emphasized.titleSmall),
          for (final habit in habits)
            _ScopeTile(
              key: ValueKey('vacation-scope-h-${habit.uuid}'),
              label: habit.name,
              color: Color(habit.color),
              selected: _selected.contains('h:${habit.uuid}'),
              onChanged: (v) => setState(() {
                if (v) {
                  _selected.add('h:${habit.uuid}');
                } else {
                  _selected.remove('h:${habit.uuid}');
                }
              }),
            ),
        ],
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            M3EButton(
              style: M3EButtonStyle.text,
              onPressed: () => Navigator.of(context).pop(false),
              label: Text(l10n.cancel),
            ),
            const SizedBox(width: 8),
            M3EButton(
              key: const ValueKey('vacation-editor-save'),
              onPressed: _saving ? null : _save,
              label: Text(l10n.save),
            ),
          ],
        ),
      ],
    );
  }
}

class _ScopeTile extends StatelessWidget {
  const _ScopeTile({
    required this.label,
    required this.color,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final String label;
  final Color color;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      checked: selected,
      child: GestureDetector(
        onTap: () => onChanged(!selected),
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              Icon(M3EIcons.circle, color: color, size: 16),
              const SizedBox(width: 12),
              Expanded(child: Text(label)),
              M3ECheckbox(
                value: selected,
                onChanged: (value) => onChanged(value ?? false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, this.theme);

  final String label;
  final M3EThemeData theme;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: theme.typography.emphasized.titleSmall.copyWith(
      color: theme.colorScheme.primary,
    ),
  );
}
