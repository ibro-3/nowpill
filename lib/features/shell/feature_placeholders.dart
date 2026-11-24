import 'package:go_router/go_router.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';
import '../../l10n/generated/app_localizations.dart';

/// App-bar action that opens the settings route. Used on compact layouts where
/// there is no navigation rail trailing slot.
class SettingsAction extends StatelessWidget {
  const SettingsAction({super.key});

  @override
  Widget build(BuildContext context) {
    return M3EIconButton(
      variant: M3EIconButtonVariant.standard,
      icon: const Icon(M3EIcons.settings_outlined),
      tooltip: AppLocalizations.of(context).settings,
      onPressed: () => context.push(AppRoutes.settings),
    );
  }
}

/// App-bar action that opens the archived-habit manager.
class ArchivedHabitsAction extends StatelessWidget {
  const ArchivedHabitsAction({super.key});

  @override
  Widget build(BuildContext context) {
    return M3EIconButton(
      key: const ValueKey('archived-habits-action'),
      variant: M3EIconButtonVariant.standard,
      icon: const Icon(M3EIcons.archive),
      tooltip: AppLocalizations.of(context).archivedHabits,
      onPressed: () => context.push(AppRoutes.archivedHabits),
    );
  }
}

/// App-bar action that opens global search (v0.4). Sits beside [SettingsAction]
/// on every primary tab.
class SearchAction extends StatelessWidget {
  const SearchAction({super.key});

  @override
  Widget build(BuildContext context) {
    return M3EIconButton(
      variant: M3EIconButtonVariant.standard,
      icon: const Icon(M3EIcons.search),
      tooltip: AppLocalizations.of(context).search,
      onPressed: () => context.push(AppRoutes.search),
    );
  }
}
