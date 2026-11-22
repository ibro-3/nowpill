import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart' show Brightness, ColorScheme;

import 'app_colors.dart';

/// Builds NowPill's Material 3 Expressive theme.
///
/// The light template is the source of truth; [M3EMaterialApp] derives the
/// dark template from it automatically (`deriveDarkTemplate`). Typography uses
/// the bundled Nunito variable font across the full M3E scale, including the
/// emphasized display/headline styles used for hero moments.
abstract final class AppTheme {
  const AppTheme._();

  /// Registered family name for the bundled Nunito variable font.
  static const String fontFamily = 'Nunito';

  /// The light-oriented base theme. Dark is derived by the M3E app shell.
  static M3EThemeData light({ColorScheme? dynamicLight}) {
    return _build(Brightness.light, dynamic: dynamicLight);
  }

  static M3EThemeData _build(Brightness brightness, {ColorScheme? dynamic}) {
    final scheme = _scheme(brightness, dynamic: dynamic);
    return M3EThemeData(colorScheme: scheme, typography: _typography());
  }

  /// Mint-seeded scheme with coral secondary + amber tertiary. When a dynamic
  /// (Material You) scheme is supplied, its palette is used instead and the
  /// expressive semantic roles are harmonized to it.
  static M3EColorScheme _scheme(Brightness brightness, {ColorScheme? dynamic}) {
    if (dynamic != null) {
      return M3EColorScheme.fromColorScheme(dynamic).harmonized();
    }
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.mint,
      secondary: AppColors.coral,
      tertiary: AppColors.amber,
      brightness: brightness,
    );
    return M3EColorScheme.fromColorScheme(base);
  }

  /// Full M3E type scale (baseline + emphasized) in Nunito.
  ///
  /// Color is intentionally NOT baked in: styles inherit from the ambient
  /// `DefaultTextStyle` (set to the active scheme's onSurface by
  /// M3EResolvedTheme), so they stay correct across light/dark and dynamic
  /// color. The `textTheme` getter applies the scheme color for Material's
  /// TextTheme separately.
  static M3ETypography _typography() {
    return M3ETypography.material3().apply(fontFamily: fontFamily);
  }
}
