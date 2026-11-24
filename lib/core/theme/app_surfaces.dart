import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

/// NowPill's surface/shape decisions, kept in one place so containers stay
/// consistent across screens and follow Material 3 Expressive's shape scale.
///
/// The radius values below are M3's ten-step scale from `tokens.md`. Cards stay
/// on the smaller steps (information-dense containers clip with large corners);
/// the bold steps are reserved for low-density hero panels and decoration.
abstract final class AppShape {
  const AppShape._();

  /// M3 `medium` — the card step (M3 cards specify 12dp).
  static const double card = 12;

  /// M3 `large` — grouped sections and summary tiles.
  static const double section = 16;

  /// M3 `large increased` — bold but still safe for short text.
  static const double panel = 20;

  /// M3 `extra large` — hero surfaces with little or no text.
  static const double hero = 28;

  /// M3 `full`.
  static const double pill = 999;

  /// Optical roundness: a nested child must not reuse its parent's radius.
  static double inner(double outer, double padding) =>
      (outer - padding).clamp(0.0, outer);
}

/// Tonal helpers that keep accent colors as *fills* and text on the matching
/// `on *` role. Accent colors are never used as body text on tinted surfaces.
abstract final class AppSurfaces {
  const AppSurfaces._();

  /// A subtle accent wash for a card container. The result is still a surface,
  /// so `onSurface` / `onSurfaceVariant` remain the correct foreground roles.
  static Color tint(
    M3EColorScheme scheme,
    Color accent, {
    double alpha = 0.06,
  }) {
    return Color.alphaBlend(
      accent.withValues(alpha: alpha),
      scheme.surfaceContainerHighest,
    );
  }

  /// An accent border for a tinted card. Kept low-contrast on purpose: the
  /// card's own container already provides the boundary.
  static Color accentBorder(Color accent, {double alpha = 0.35}) =>
      accent.withValues(alpha: alpha);
}
