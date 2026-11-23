import 'package:go_router/go_router.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';

/// App-bar action that opens the settings route. Used on compact layouts where
/// there is no navigation rail trailing slot.
class SettingsAction extends StatelessWidget {
  const SettingsAction({super.key});

  @override
  Widget build(BuildContext context) {
    return M3EIconButton(
      variant: M3EIconButtonVariant.standard,
      icon: const Icon(M3EIcons.settings_outlined),
      tooltip: 'Settings',
      onPressed: () => context.push(AppRoutes.settings),
    );
  }
}
