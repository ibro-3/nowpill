import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/repositories/providers.dart';
import '../../domain/date_utils.dart';
import '../../l10n/generated/app_localizations.dart';
import '../today/widgets/floating_pills.dart';
import 'habit_icons.dart';
import 'habit_providers.dart';

/// Browse archived habits and restore or permanently delete them. Archived
/// habits keep their check-in history; deleting one does not.
class ArchivedHabitsScreen extends ConsumerWidget {
  const ArchivedHabitsScreen({super.key});

  Future<void> _restore(WidgetRef ref, BuildContext context, int id) async {
    await ref.read(habitRepositoryProvider).unarchive(id);
    if (!context.mounted) return;
    M3ESnackbar.show(
      context,
      message: AppLocalizations.of(context).habitRestored,
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    int id,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await M3EDialog.show<bool>(
      context,
      dialog: M3EDialog(
        title: l10n.deleteHabitTitle,
        content: Text(l10n.deleteHabitBody),
        actions: [
          M3EButton(
            style: M3EButtonStyle.text,
            onPressed: () => Navigator.of(context).pop(false),
            label: Text(l10n.cancel),
          ),
          M3EButton(
            onPressed: () => Navigator.of(context).pop(true),
            label: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(habitRepositoryProvider).delete(id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);
    final archived = ref.watch(archivedHabitsProvider);

    return Scaffold(
      appBar: M3EAppBar.top(
        titleText: l10n.archivedHabits,
        leading: M3EIconButton(
          variant: M3EIconButtonVariant.standard,
          icon: const Icon(M3EIcons.arrow_back),
          tooltip: l10n.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: archived.isEmpty
          ? FloatingPills(
              icon: M3EIcons.archive,
              message: l10n.archivedHabitsEmpty,
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: archived.length,
              itemBuilder: (context, index) {
                final habit = archived[index];
                final color = Color(habit.color);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: M3ECard(
                    variant: M3ECardVariant.filled,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        M3EShapeContainer(
                          kind: M3EShapeKind.cookie6Sided,
                          width: 40,
                          height: 40,
                          color: color.withValues(alpha: 0.18),
                          child: Icon(
                            habitIconForKey(habit.iconKey),
                            size: 20,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                habit.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.typography.baseline.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l10n.archivedOn(
                                  formatDate(habit.archivedAt!.toLocal()),
                                ),
                                style: theme.typography.baseline.labelSmall
                                    .copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        M3EIconButton(
                          key: ValueKey('restore-habit-${habit.id}'),
                          variant: M3EIconButtonVariant.standard,
                          icon: const Icon(M3EIcons.restore),
                          tooltip: l10n.restoreHabit,
                          onPressed: () => _restore(ref, context, habit.id),
                        ),
                        M3EIconButton(
                          key: ValueKey('delete-archived-habit-${habit.id}'),
                          variant: M3EIconButtonVariant.standard,
                          icon: Icon(
                            M3EIcons.delete_forever,
                            color: theme.colorScheme.error,
                          ),
                          tooltip: l10n.deleteHabit,
                          onPressed: () =>
                              _confirmDelete(context, ref, habit.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
