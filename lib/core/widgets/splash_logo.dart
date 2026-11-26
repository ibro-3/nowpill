import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';

/// Asset path shared with the native launch screens (Android/iOS use their own
/// density-specific copies of the same transparent pill artwork).
const String kSplashLogoAsset = 'assets/branding/icon-foreground-512.png';

/// The brand pill on a filled mint circle.
///
/// The logo's white half disappears on a bare white splash, so the circle is a
/// fill behind it — not a border. Brand mint is the same color as the launcher
/// icon background (`#2DD4A8`), keeping the splash and icon consistent.
class SplashLogo extends StatelessWidget {
  const SplashLogo({this.diameter = 112, super.key});

  /// Diameter of the filled circle in logical pixels.
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('splash-circle'),
      width: diameter,
      height: diameter,
      decoration: const BoxDecoration(
        color: AppColors.mint,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Image.asset(
          kSplashLogoAsset,
          width: diameter * 0.68,
          height: diameter * 0.68,
          fit: BoxFit.contain,
          semanticLabel: 'NowPill',
        ),
      ),
    );
  }
}
