import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/core/theme/app_surfaces.dart';
import 'package:nowpill/core/theme/app_theme.dart';

/// Per-entity colors are user-chosen, so M3 has no `on *` role for them.
/// [AppSurfaces.onAccent] must pick a paired scheme role that stays readable
/// over the accent in both themes (M3 minimum: 4.5:1 small text / 3:1 graphics).
void main() {
  const accents = <int>[
    0xFF2DD4A8, // mint
    0xFFFF6B5E, // coral
    0xFFFFB454, // amber
    0xFF5B8DEF, // blue
    0xFF9B6DFF, // purple
    0xFFEF5DA8, // pink
    0xFF4CB944, // green
    0xFF00B4D8, // cyan
    0xFFFFC24B, // yellow
    0xFFB889F8, // tag palette
  ];

  // WCAG relative luminance / contrast ratio from sRGB channels (0…1).
  double luminance(Color color) {
    double channel(double c) => c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  const themes = <(String, bool)>[('light', false), ('dark', true)];
  for (final (name, isDark) in themes) {
    test('onAccent clears 4.5:1 over every brand accent in $name theme', () {
      final base = AppTheme.light();
      final scheme = isDark
          ? base.deriveDarkTemplate().colorScheme
          : base.colorScheme;
      for (final hex in accents) {
        final accent = Color(hex);
        final foreground = AppSurfaces.onAccent(scheme, accent);
        expect(
          contrast(foreground, accent),
          greaterThanOrEqualTo(4.5),
          reason: 'accent ${hex.toRadixString(16)} in $name theme',
        );
      }
    });
  }
}
