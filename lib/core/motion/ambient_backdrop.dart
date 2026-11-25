import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import 'ambient_clock.dart';
import 'app_motion.dart';
import 'motion_scheme_provider.dart';
import 'shape_morph.dart';

/// Slow, low-contrast shapes drifting behind app content.
///
/// This is decoration only: it is ignored by hit testing and semantics, never
/// sits behind text, and freezes completely under reduced motion. The shapes
/// glide on a monotonic time clock (two sine frequencies per axis) instead of
/// a spring — a settling spring would read as stiff for ambient motion. Each
/// shape also morphs slowly between a pair of M3 shapes; morph is geometry, so
/// the easing is a cosine rather than an effects spring.
class AmbientBackdrop extends StatefulWidget {
  const AmbientBackdrop({super.key});

  @override
  State<AmbientBackdrop> createState() => _AmbientBackdropState();
}

class _AmbientBackdropState extends State<AmbientBackdrop>
    with SingleTickerProviderStateMixin {
  // (from, to, base x, base y, size, phase, speed, drift reach)
  static const _shapes =
      <
        (
          M3EShapeKind,
          M3EShapeKind,
          double,
          double,
          double,
          double,
          double,
          double,
        )
      >[
        (
          M3EShapeKind.softBurst,
          M3EShapeKind.flower,
          0.10,
          0.16,
          260,
          0.0,
          1.0,
          1.0,
        ),
        (
          M3EShapeKind.clover4Leaf,
          M3EShapeKind.cookie9Sided,
          0.91,
          0.53,
          210,
          2.1,
          0.73,
          0.85,
        ),
        (
          M3EShapeKind.cookie6Sided,
          M3EShapeKind.cookie9Sided,
          0.17,
          0.87,
          190,
          4.2,
          1.31,
          1.15,
        ),
      ];

  late final AmbientClock _clock = AmbientClock(
    this,
    debugLabel: 'AmbientBackdrop.drift',
  );

  /// Morphs are cached per ordered pair in [shapeMorph], so this is cheap.
  late final List<Morph> _morphs = [
    for (final shape in _shapes) shapeMorph(shape.$1, shape.$2),
  ];

  MotionTokens? _applied;
  bool _pending = false;

  void _apply(MotionTokens tokens) {
    if (!mounted) return;
    if (tokens.reduced) {
      _clock.reset();
    } else {
      _clock.start();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final tokens = MotionScope.of(context);
    if (tokens != _applied && !_pending) {
      _applied = tokens;
      _pending = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _pending = false;
        _apply(tokens);
      });
    }

    final colors = <Color>[
      theme.colorScheme.primary.withValues(alpha: 0.07),
      theme.colorScheme.tertiary.withValues(alpha: 0.06),
      theme.colorScheme.secondary.withValues(alpha: 0.055),
    ];

    return RepaintBoundary(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: _clock.seconds,
            builder: (context, _) => CustomPaint(
              painter: _BackdropPainter(
                seconds: tokens.reduced ? 0 : _clock.seconds.value,
                period: tokens.ambientDrift.inMicroseconds / 1000000.0,
                morphPeriod: tokens.ambientMorph.inMicroseconds / 1000000.0,
                morphs: _morphs,
                colors: colors,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter({
    required this.seconds,
    required this.period,
    required this.morphPeriod,
    required this.morphs,
    required this.colors,
  });

  final double seconds;
  final double period;
  final double morphPeriod;
  final List<Morph> morphs;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || period <= 0) return;
    final scale = math.max(0.7, math.min(1.25, size.width / 420));

    for (var i = 0; i < _AmbientBackdropState._shapes.length; i++) {
      final (_, _, baseX, baseY, baseSize, phase, speed, reach) =
          _AmbientBackdropState._shapes[i];
      // Two incommensurate frequencies per axis keep the drift from looking
      // like a metronome, while the monotonic clock avoids a jump at a loop.
      final a = 2 * math.pi * (seconds / period) * speed + phase;
      final dx = 22 * reach * math.sin(a) + 9 * math.cos(a * 2.7);
      final dy = 18 * reach * math.cos(a * 0.83) + 8 * math.sin(a * 1.9);
      final rotation = a * (i.isEven ? 0.16 : -0.12);
      final pulse = 1 + 0.08 * math.sin(a * 1.3 + phase);
      final target = baseSize * scale * pulse;

      // Cosine easing runs 0 → 1 → 0 seamlessly; no spring overshoot, so the
      // silhouette never extrapolates past either shape.
      final morphT = morphPeriod > 0
          ? 0.5 - 0.5 * math.cos(2 * math.pi * seconds / morphPeriod + phase)
          : 0.0;
      final path = morphs[i].toPath(progress: morphT.clamp(0.0, 1.0));
      final bounds = path.getBounds();
      if (bounds.isEmpty) continue;
      final matrix = Matrix4.identity()
        ..scaleByDouble(target / bounds.width, target / bounds.height, 1, 1)
        ..translateByDouble(-bounds.left, -bounds.top, 0, 1);
      final scaled = path.transform(matrix.storage);

      canvas.save();
      canvas.translate(baseX * size.width + dx, baseY * size.height + dy);
      canvas.rotate(rotation);
      canvas.translate(-target / 2, -target / 2);
      canvas.drawPath(scaled, Paint()..color = colors[i]);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) {
    if (old.seconds != seconds ||
        old.period != period ||
        old.morphPeriod != morphPeriod) {
      return true;
    }
    for (var i = 0; i < colors.length; i++) {
      if (old.colors[i] != colors[i]) return true;
    }
    return false;
  }
}
