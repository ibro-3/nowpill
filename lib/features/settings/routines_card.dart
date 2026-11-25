import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_surfaces.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../habits/habit_icons.dart';
import '../habits/habit_providers.dart';

/// Settings → Routines: create, rename, reorder, and delete habit groups.
class RoutinesCard extends ConsumerWidget {
  const RoutinesCard({required this.theme, super.key});

  final M3EThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final routines = ref.watch(allRoutinesProvider).value ?? const <Routine>[];

    return _SettingsCard(
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.routinesDescription,
            style: theme.typography.baseline.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < routines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    M3EIcons.circle,
                    size: 16,
                    color: AppSurfaces.graphic(
                      theme.colorScheme,
                      Color(routines[i].color),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(routines[i].name)),
                  M3EIconButton(
                    variant: M3EIconButtonVariant.standard,
                    icon: const Icon(M3EIcons.arrow_upward),
                    tooltip: l10n.routineMoveUp,
                    key: ValueKey('routine-up-${routines[i].id}'),
                    onPressed: i == 0
                        ? null
                        : () => _swap(ref, routines, i, i - 1),
                  ),
                  M3EIconButton(
                    variant: M3EIconButtonVariant.standard,
                    icon: const Icon(M3EIcons.arrow_downward),
                    tooltip: l10n.routineMoveDown,
                    key: ValueKey('routine-down-${routines[i].id}'),
                    onPressed: i == routines.length - 1
                        ? null
                        : () => _swap(ref, routines, i, i + 1),
                  ),
                  M3EIconButton(
                    variant: M3EIconButtonVariant.standard,
                    icon: const Icon(M3EIcons.edit),
                    tooltip: l10n.routineEdit,
                    key: ValueKey('routine-edit-${routines[i].id}'),
                    onPressed: () => _edit(context, ref, routines[i]),
                  ),
                  M3EIconButton(
                    variant: M3EIconButtonVariant.standard,
                    icon: const Icon(M3EIcons.delete_outline),
                    tooltip: l10n.routineDelete,
                    key: ValueKey('routine-delete-${routines[i].id}'),
                    onPressed: () => _delete(context, ref, routines[i]),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: M3EButton.icon(
              key: const ValueKey('routine-add'),
              style: M3EButtonStyle.tonal,
              icon: const Icon(M3EIcons.add),
              label: Text(l10n.routineNew),
              onPressed: () => _edit(context, ref, null),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _swap(
    WidgetRef ref,
    List<Routine> routines,
    int a,
    int b,
  ) async {
    final repo = ref.read(habitRepositoryProvider);
    final first = routines[a];
    final second = routines[b];
    await repo.updateRoutine(first.copyWith(sortOrder: second.sortOrder));
    await repo.updateRoutine(second.copyWith(sortOrder: first.sortOrder));
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Routine? routine,
  ) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: routine?.name ?? '');
    var color = routine?.color ?? kHabitColors.first;
    final saved = await M3EDialog.show<bool>(
      context,
      dialog: StatefulBuilder(
        builder: (context, setState) => M3EDialog(
          title: routine == null ? l10n.routineNew : l10n.routineEdit,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              M3ETextField(
                controller: controller,
                label: l10n.routineName,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (var ci = 0; ci < kHabitColors.length; ci++)
                    Semantics(
                      label: l10n.routineColorOption(ci + 1),
                      checked: kHabitColors[ci] == color,
                      child: GestureDetector(
                        onTap: () => setState(() => color = kHabitColors[ci]),
                        // 48dp hit box around the 28dp visual (M3 targets).
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Center(
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(kHabitColors[ci]),
                                border: Border.all(
                                  color: kHabitColors[ci] == color
                                      ? theme.colorScheme.onSurface
                                      : const Color(0x00000000),
                                  width: 2.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            M3EButton(
              style: M3EButtonStyle.text,
              label: Text(l10n.cancel),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            M3EButton(
              key: const ValueKey('routine-save'),
              label: Text(l10n.save),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final name = controller.text.trim();
    if (name.isEmpty) {
      if (context.mounted) {
        M3ESnackbar.show(context, message: l10n.routineInvalid);
      }
      return;
    }
    final repo = ref.read(habitRepositoryProvider);
    final existing = await repo.getAllRoutines();
    if (existing.any(
      (r) => r.name.toLowerCase() == name.toLowerCase() && r.id != routine?.id,
    )) {
      if (context.mounted) {
        M3ESnackbar.show(context, message: l10n.routineAlreadyExists);
      }
      return;
    }
    if (routine == null) {
      await repo.createRoutine(
        name,
        color,
        sortOrder: existing.isEmpty ? 0 : existing.last.sortOrder + 1,
      );
    } else {
      await repo.updateRoutine(routine.copyWith(name: name, color: color));
    }
    if (context.mounted) {
      M3ESnackbar.show(context, message: l10n.routineSaved);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Routine routine,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await M3EDialog.show<bool>(
      context,
      dialog: M3EDialog(
        title: l10n.routineDelete,
        content: Text(l10n.routineDeleteBody),
        actions: [
          M3EButton(
            style: M3EButtonStyle.text,
            label: Text(l10n.cancel),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          M3EButton(
            key: const ValueKey('routine-delete-confirm'),
            label: Text(l10n.delete),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(habitRepositoryProvider).deleteRoutine(routine.id);
    if (context.mounted) {
      M3ESnackbar.show(context, message: l10n.routineDeleted);
    }
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.theme, required this.child});

  final M3EThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return M3ECard(
      variant: M3ECardVariant.filled,
      padding: const EdgeInsets.all(20),
      child: child,
    );
  }
}
