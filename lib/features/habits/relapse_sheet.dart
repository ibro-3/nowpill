import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';

/// Confirms a relapse and collects an optional note. Returns null when the
/// user cancels, otherwise the note (possibly empty).
Future<String?> showRelapseDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController();
  final result = await M3EDialog.show<String?>(
    context,
    dialog: M3EDialog(
      title: l10n.relapseTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.relapseBody,
            style: M3ETheme.of(context).typography.baseline.bodyMedium,
          ),
          const SizedBox(height: 12),
          M3ETextField(
            controller: controller,
            label: l10n.relapseNote,
            maxLines: 2,
            minLines: 1,
          ),
        ],
      ),
      actions: [
        M3EButton(
          style: M3EButtonStyle.text,
          onPressed: () => Navigator.of(context).pop(),
          label: Text(l10n.cancel),
        ),
        M3EButton(
          key: const ValueKey('relapse-confirm'),
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          label: Text(l10n.logRelapse),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
