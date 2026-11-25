import 'package:flutter/physics.dart';
import 'package:motor/motor.dart';

/// NowPill's central motion tokens, mapped from the Material 3 Expressive
/// spring system (via `motor`'s [MaterialSpringMotion]).
///
/// Every animation in the app reads its spring from here — no ad-hoc
/// curves/durations in feature code. Two schemes are provided:
///
/// * **expressive** (default): spatial springs overshoot and bounce; effects
///   springs (color/opacity) never overshoot.
/// * **standard**: critically/over-damped, minimal bounce — used when the user
///   or the OS requests reduced motion.
///
/// See `core/motion/motion_scheme_provider.dart` for scheme selection.
abstract final class AppMotion {
  const AppMotion._();

  // ---------------------------------------------------------------------------
  // Expressive scheme (playful, default)
  // ---------------------------------------------------------------------------

  /// Press squish, icon swaps, chip morphs. Damping 0.6 / stiffness 800.
  static const Motion expressiveSpatialFast =
      MaterialSpringMotion.expressiveSpatialFast();

  /// List insert/remove, sheet detents, nav indicator. 0.8 / 380.
  static const Motion expressiveSpatialDefault =
      MaterialSpringMotion.expressiveSpatialDefault();

  /// Hero moments, celebration settle. 0.8 / 200.
  static const Motion expressiveSpatialSlow =
      MaterialSpringMotion.expressiveSpatialSlow();

  /// Color & opacity (never overshoot). 1.0 / 3800.
  static const Motion expressiveEffectsFast =
      MaterialSpringMotion.expressiveEffectsFast();

  /// Color & opacity default. 1.0 / 1600.
  static const Motion expressiveEffectsDefault =
      MaterialSpringMotion.expressiveEffectsDefault();

  /// Color & opacity slow. 1.0 / 800.
  static const Motion expressiveEffectsSlow =
      MaterialSpringMotion.expressiveEffectsSlow();

  /// Confetti shower / celebration timeline. Critically damped and slow
  /// (~2.5s to settle) so particle effects run their full course; the
  /// spatial springs would overshoot past the end and cut them short.
  /// Damping ratio 1.0 at stiffness 12 → coefficient 2·√12 ≈ 6.9282.
  static const Motion expressiveCelebration = SpringMotion(
    SpringDescription(mass: 1, stiffness: 12, damping: 6.928203230275509),
  );

  // ---------------------------------------------------------------------------
  // Standard scheme (reduced motion)
  // ---------------------------------------------------------------------------

  /// Quick spatial, minimal bounce. 0.9 / 1400.
  static const Motion standardSpatialFast =
      MaterialSpringMotion.standardSpatialFast();

  /// Balanced spatial. 0.9 / 700.
  static const Motion standardSpatialDefault =
      MaterialSpringMotion.standardSpatialDefault();

  /// Gentle spatial. 0.9 / 300.
  static const Motion standardSpatialSlow =
      MaterialSpringMotion.standardSpatialSlow();

  /// Effects fast. 1.0 / 3800.
  static const Motion standardEffectsFast =
      MaterialSpringMotion.standardEffectsFast();

  /// Effects default. 1.0 / 1600.
  static const Motion standardEffectsDefault =
      MaterialSpringMotion.standardEffectsDefault();

  /// Effects slow. 1.0 / 800.
  static const Motion standardEffectsSlow =
      MaterialSpringMotion.standardEffectsSlow();

  // ---------------------------------------------------------------------------
  // Ambient (continuous) motion
  // ---------------------------------------------------------------------------

  /// Period of the slow background-shape drift. Deliberately much longer than
  /// any spring: decorative motion should glide, never snap or settle.
  static const Duration ambientDrift = Duration(seconds: 42);

  /// Period of one orbit/rotation of the empty-state illustration.
  static const Duration ambientOrbit = Duration(seconds: 22);

  /// Period of one rotation of the empty-state illustration's center shape.
  /// Faster than the satellite orbit so the spin reads at a glance.
  static const Duration ambientSpin = Duration(seconds: 6);

  /// Period of one wave travelling along the Today progress ring.
  static const Duration ambientWave = Duration(milliseconds: 2600);

  /// Period of one slow morph cycle of the decorative background shapes.
  /// Deliberately much longer than the wave so the silhouette drift reads as
  /// ambient rather than as a state change.
  static const Duration ambientMorph = Duration(seconds: 28);
}

/// A resolved set of motion tokens for the active scheme.
///
/// Feature code calls `ref.watch(motionTokensProvider)` (or
/// `MotionScope.of(context)`) and uses these fields instead of picking springs
/// directly, so a scheme switch retargets every animation at once.
class MotionTokens {
  const MotionTokens({
    required this.spatialFast,
    required this.spatialDefault,
    required this.spatialSlow,
    required this.effectsFast,
    required this.effectsDefault,
    required this.effectsSlow,
    required this.celebration,
    required this.reduced,
    this.ambientDrift = AppMotion.ambientDrift,
    this.ambientOrbit = AppMotion.ambientOrbit,
    this.ambientSpin = AppMotion.ambientSpin,
    this.ambientWave = AppMotion.ambientWave,
    this.ambientMorph = AppMotion.ambientMorph,
  });

  /// The expressive (playful) token set.
  static const MotionTokens expressive = MotionTokens(
    spatialFast: AppMotion.expressiveSpatialFast,
    spatialDefault: AppMotion.expressiveSpatialDefault,
    spatialSlow: AppMotion.expressiveSpatialSlow,
    effectsFast: AppMotion.expressiveEffectsFast,
    effectsDefault: AppMotion.expressiveEffectsDefault,
    effectsSlow: AppMotion.expressiveEffectsSlow,
    celebration: AppMotion.expressiveCelebration,
    reduced: false,
  );

  /// The standard (reduced-motion) token set.
  static const MotionTokens standard = MotionTokens(
    spatialFast: AppMotion.standardSpatialFast,
    spatialDefault: AppMotion.standardSpatialDefault,
    spatialSlow: AppMotion.standardSpatialSlow,
    effectsFast: AppMotion.standardEffectsFast,
    effectsDefault: AppMotion.standardEffectsDefault,
    effectsSlow: AppMotion.standardEffectsSlow,
    celebration: AppMotion.expressiveCelebration,
    reduced: true,
  );

  final Motion spatialFast;
  final Motion spatialDefault;
  final Motion spatialSlow;
  final Motion effectsFast;
  final Motion effectsDefault;
  final Motion effectsSlow;

  /// Long, non-overshooting spring for particle/celebration timelines.
  final Motion celebration;

  /// Whether this token set is the reduced-motion variant.
  final bool reduced;

  /// Clock period for slow decorative drift (background shapes).
  final Duration ambientDrift;

  /// Clock period for orbiting/rotating illustration shapes.
  final Duration ambientOrbit;

  /// Clock period for the empty-state center shape's spin.
  final Duration ambientSpin;

  /// Clock period for a wave travelling along a progress indicator.
  final Duration ambientWave;

  /// Clock period for a decorative background shape's morph cycle.
  final Duration ambientMorph;
}
