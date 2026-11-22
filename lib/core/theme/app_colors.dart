import 'package:flutter/widgets.dart';

/// NowPill brand colors.
///
/// Mint is the primary seed; coral is the secondary accent. Together they
/// drive the M3 tonal palettes (and, when enabled, harmonize with Material You
/// dynamic color).
abstract final class AppColors {
  const AppColors._();

  /// Mint — primary brand seed.
  static const Color mint = Color(0xFF2DD4A8);

  /// Coral — secondary accent.
  static const Color coral = Color(0xFFFF6B5E);

  /// Warm amber — tertiary accent (streaks, highlights).
  static const Color amber = Color(0xFFFFB454);
}
