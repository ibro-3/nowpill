import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import '../../../core/motion/ambient_clock.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_scheme_provider.dart';

/// A floating-pill illustration for empty states: a slowly rotating center
/// shape circled by expressive satellites that breathe in and out. Static
/// under reduced motion.
class FloatingPills extends StatefulWidget {
  const FloatingPills({required this.icon, required this.message, super.key});

  final IconData icon;
  final String message;

  @override
  State<FloatingPills> createState() => _FloatingPillsState();
}

class _FloatingPillsState extends State<FloatingPills>
    with SingleTickerProviderStateMixin {
  // (shape, orbit x, orbit y, size, phase, speed, pulse speed)
  static const _satellites =
      <(M3EShapeKind, double, double, double, double, double, double)>[
        (M3EShapeKind.pill, 76, 50, 34, 0.0, 1.0, 1.3),
        (M3EShapeKind.cookie6Sided, 72, 48, 30, 1.6, 1.27, 0.8),
        (M3EShapeKind.circle, 70, 46, 22, 3.1, 0.79, 1.6),
        (M3EShapeKind.softBurst, 74, 50, 28, 4.7, 1.43, 1.1),
      ];

  late final AmbientClock _clock = AmbientClock(
    this,
    debugLabel: 'FloatingPills.orbit',
  );
  MotionTokens? _applied;
  bool _pending = false;

  /// Ambient motion is time-based rather than spring-based: a settling spring
  /// would make an orbit look stiff, and a monotonic clock never jumps.
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

    final period = tokens.ambientOrbit.inMicroseconds / 1000000.0;
    // The center spins on its own faster clock: the satellites keep their slow
    // orbit, but the center's turn is obvious at a glance.
    final spinPeriod = tokens.ambientSpin.inMicroseconds / 1000000.0;
    final colors = [
      theme.colorScheme.secondaryContainer,
      theme.colorScheme.tertiaryContainer,
      theme.colorScheme.surfaceContainerHigh,
      theme.colorScheme.primaryContainer,
    ];

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 220,
              height: 180,
              child: AnimatedBuilder(
                animation: _clock.seconds,
                builder: (context, _) {
                  // Read the clock here, not in build: the value must be fresh
                  // on every tick or the animation redraws with a stale angle.
                  final seconds = tokens.reduced ? 0.0 : _clock.seconds.value;
                  final centerTurn = spinPeriod > 0
                      ? 2 * math.pi * seconds / spinPeriod
                      : 0.0;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      for (var i = 0; i < _satellites.length; i++)
                        _satellite(theme, colors, i, seconds, period),
                      Transform.rotate(
                        key: const Key('floating-pills-center'),
                        angle: centerTurn,
                        child: M3EShapeContainer(
                          kind: M3EShapeKind.cookie9Sided,
                          width: 84,
                          height: 84,
                          color: theme.colorScheme.primaryContainer,
                          // The container spins, but the glyph must stay
                          // upright: cancel the parent's rotation here.
                          child: Transform.rotate(
                            key: const Key('floating-pills-center-icon'),
                            angle: -centerTurn,
                            child: Icon(
                              widget.icon,
                              size: 36,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: theme.typography.baseline.bodyLarge.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _satellite(
    M3EThemeData theme,
    List<Color> colors,
    int i,
    double seconds,
    double period,
  ) {
    final (kind, rx, ry, size, phase, speed, pulseSpeed) = _satellites[i];
    final a = period > 0 ? 2 * math.pi * (seconds / period) * speed + phase : 0;
    final scale = 1 + 0.14 * math.sin(a * pulseSpeed);
    return Transform.translate(
      offset: Offset(rx * math.cos(a), ry * math.sin(a)),
      child: Transform.rotate(
        angle: a * 0.25,
        child: Transform.scale(
          scale: scale,
          child: M3EShapeContainer(
            kind: kind,
            width: size,
            height: size,
            color: colors[i % colors.length],
          ),
        ),
      ),
    );
  }
}
