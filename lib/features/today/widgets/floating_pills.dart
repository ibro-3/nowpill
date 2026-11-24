import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:motor/motor.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_scheme_provider.dart';

/// A floating-pill illustration for empty states: expressive shapes bobbing
/// gently around a central icon cookie. Static under reduced motion.
class FloatingPills extends StatefulWidget {
  const FloatingPills({required this.icon, required this.message, super.key});

  final IconData icon;
  final String message;

  @override
  State<FloatingPills> createState() => _FloatingPillsState();
}

class _FloatingPillsState extends State<FloatingPills>
    with SingleTickerProviderStateMixin {
  late final SequenceMotionController<int, double> _bob;
  MotionTokens? _applied;
  bool _pending = false;

  static const _satellites = <(M3EShapeKind, double, double, double)>[
    // (shape, dx, dy, size) relative to the illustration center.
    (M3EShapeKind.pill, -64, -34, 34),
    (M3EShapeKind.cookie6Sided, 62, -26, 30),
    (M3EShapeKind.circle, -52, 40, 22),
    (M3EShapeKind.softBurst, 58, 42, 28),
  ];

  @override
  void initState() {
    super.initState();
    _bob = SequenceMotionController<int, double>(
      motion: MotionTokens.expressive.spatialSlow,
      vsync: this,
      converter: const SingleMotionConverter(),
      initialValue: 0,
    );
  }

  /// Starts a physics-driven ping-pong loop. A sequence controller keeps the
  /// velocity through each phase and needs no `whenComplete` re-arming chain.
  void _apply(MotionTokens tokens) {
    if (!mounted) return;
    if (tokens.reduced) {
      _bob.value = 0;
      return;
    }
    _bob.motion = tokens.spatialSlow;
    _bob.playSequence(
      MotionSequence.steps(
        [0.0, 1.0],
        motion: tokens.spatialSlow,
        loop: LoopMode.pingPong,
      ),
    );
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final tokens = MotionScope.of(context);
    if (tokens != _applied) {
      _applied = tokens;
      if (!_pending) {
        _pending = true;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _pending = false;
          _apply(tokens);
        });
      }
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 200,
              height: 150,
              child: AnimatedBuilder(
                animation: _bob,
                builder: (context, _) {
                  final wave = tokens.reduced ? 0.0 : _bob.value;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      for (var i = 0; i < _satellites.length; i++)
                        _satellite(theme, i, wave),
                      M3EShapeContainer(
                        kind: M3EShapeKind.cookie9Sided,
                        width: 84,
                        height: 84,
                        color: theme.colorScheme.primaryContainer,
                        child: Icon(
                          widget.icon,
                          size: 36,
                          color: theme.colorScheme.onPrimaryContainer,
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

  Widget _satellite(M3EThemeData theme, int i, double wave) {
    final (kind, dx, dy, size) = _satellites[i];
    // Each satellite bobs out of phase.
    final phase = (wave + i * 0.25) % 1.0;
    final lift = -6 * (0.5 - (phase - 0.5).abs()) * 2;
    final colors = [
      theme.colorScheme.secondaryContainer,
      theme.colorScheme.tertiaryContainer,
      theme.colorScheme.surfaceContainerHigh,
      theme.colorScheme.primaryContainer,
    ];
    return Transform.translate(
      offset: Offset(dx, dy + lift),
      child: M3EShapeContainer(
        kind: kind,
        width: size,
        height: size,
        color: colors[i % colors.length],
      ),
    );
  }
}
