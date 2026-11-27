import 'dart:ui' show FontVariation;

import 'package:flutter/widgets.dart' show FontWeight, TextStyle;
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart' show Brightness, ColorScheme;

import 'app_colors.dart';

/// Builds NowPill's Material 3 Expressive theme.
///
/// Light and dark are built side by side from the same brand seeds, so the
/// coral/amber accents survive in both brightnesses. Typography uses the
/// bundled Nunito variable font across the full M3E scale, including the
/// emphasized display/headline styles used for hero moments.
abstract final class AppTheme {
  const AppTheme._();

  /// Registered family name for the bundled Nunito variable font.
  static const String fontFamily = 'Nunito';

  /// The light-oriented brand theme.
  static M3EThemeData light({ColorScheme? dynamicLight}) {
    return _build(Brightness.light, dynamic: dynamicLight);
  }

  /// The dark-oriented brand theme.
  ///
  /// Built the same way as [light] (mint seed, coral secondary, amber tertiary)
  /// rather than via `M3EThemeData.deriveDarkTemplate()`. That helper re-seeds
  /// from a single color — the light scheme's primary — which discards our
  /// explicit secondary/tertiary overrides and loses the brand palette in dark
  /// mode. The app shell uses this template directly for M3E components too.
  static M3EThemeData dark({ColorScheme? dynamicDark}) {
    return _build(Brightness.dark, dynamic: dynamicDark);
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
  /// Nunito's variable `wght` axis runs 200–1000; the stock M3E scale leaves
  /// it at 400/500, which reads timid for a playful product. We keep M3's
  /// sizes and tracking but weight each role deliberately: bold display and
  /// titles, medium body (long text stays readable), semibold labels.
  ///
  /// Color is intentionally NOT baked in: styles inherit from the ambient
  /// `DefaultTextStyle` (set to the active scheme's onSurface by
  /// M3EResolvedTheme), so they stay correct across light/dark and dynamic
  /// color. The `textTheme` getter applies the scheme color for Material's
  /// TextTheme separately.
  static M3ETypography _typography() {
    final base = M3ETypography.material3(mode: M3ETypeScaleMode.variable)
        .apply(fontFamily: fontFamily);
    return M3ETypography(
      baseline: _weightRoles(base.baseline, emphasized: false),
      emphasized: _weightRoles(base.emphasized, emphasized: true),
    );
  }

  static FontWeight _weight(M3ETypeRole role, {required bool emphasized}) {
    return switch (role) {
      M3ETypeRole.displayLarge ||
      M3ETypeRole.displayMedium ||
      M3ETypeRole.displaySmall ||
      M3ETypeRole.headlineLarge ||
      M3ETypeRole.headlineMedium ||
      M3ETypeRole.headlineSmall ||
      M3ETypeRole.titleLarge => FontWeight.w800,
      M3ETypeRole.titleMedium => FontWeight.w700,
      M3ETypeRole.titleSmall => FontWeight.w700,
      M3ETypeRole.bodyLarge ||
      M3ETypeRole.bodyMedium ||
      M3ETypeRole.bodySmall => FontWeight.w500,
      M3ETypeRole.labelLarge => FontWeight.w700,
      M3ETypeRole.labelMedium ||
      M3ETypeRole.labelSmall => emphasized ? FontWeight.w700 : FontWeight.w600,
    };
  }

  static M3ETypeScale _weightRoles(
    M3ETypeScale scale, {
    required bool emphasized,
  }) {
    TextStyle heavier(M3ETypeRole role) {
      final weight = _weight(role, emphasized: emphasized);
      return scale
          .roleStyle(role)
          .copyWith(
            fontWeight: weight,
            // The bundled Nunito is a variable font: set the axis explicitly so
            // Flutter doesn't fall back to synthetic emboldening.
            fontVariations: [FontVariation('wght', weight.value.toDouble())],
          );
    }

    return M3ETypeScale(
      displayLarge: heavier(M3ETypeRole.displayLarge),
      displayMedium: heavier(M3ETypeRole.displayMedium),
      displaySmall: heavier(M3ETypeRole.displaySmall),
      headlineLarge: heavier(M3ETypeRole.headlineLarge),
      headlineMedium: heavier(M3ETypeRole.headlineMedium),
      headlineSmall: heavier(M3ETypeRole.headlineSmall),
      titleLarge: heavier(M3ETypeRole.titleLarge),
      titleMedium: heavier(M3ETypeRole.titleMedium),
      titleSmall: heavier(M3ETypeRole.titleSmall),
      bodyLarge: heavier(M3ETypeRole.bodyLarge),
      bodyMedium: heavier(M3ETypeRole.bodyMedium),
      bodySmall: heavier(M3ETypeRole.bodySmall),
      labelLarge: heavier(M3ETypeRole.labelLarge),
      labelMedium: heavier(M3ETypeRole.labelMedium),
      labelSmall: heavier(M3ETypeRole.labelSmall),
    );
  }
}
