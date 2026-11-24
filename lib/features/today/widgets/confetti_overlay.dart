import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_scheme_provider.dart';

/// A subtle confetti shower for the all-done celebration.
///
/// Pieces burst outward from the top-center, fall with a gentle sway, spin,
/// and fade. Driven by a single spring; plays once per [playToken] change and
/// is skipped entirely under reduced motion.
class ConfettiOverlay extends StatefulWidget {
  const ConfettiOverlay({
    required this.playToken,
    required this.colors,
    super.key,
  });

  /// Increment to fire a new burst. 0 = never played.
  final int playToken;

  /// Brand palette for the pieces.
  final List<Color> colors;

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final SingleMotionController _fall;
  late List<_Piece> _pieces;
  int _lastToken = 0;

  @override
  void initState() {
    super.initState();
    _fall = SingleMotionController(
      motion: MotionTokens.expressive.celebration,
      vsync: this,
      initialValue: 1,
    );
    _pieces = _generate(widget.playToken);
    _lastToken = widget.playToken;
    if (widget.playToken > 0) {
      _fall
        ..value = 0
        ..animateTo(1);
    }
  }

  @override
  void didUpdateWidget(ConfettiOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playToken != _lastToken) {
      _lastToken = widget.playToken;
      _pieces = _generate(widget.playToken);
      _fall
        ..value = 0
        ..animateTo(1);
    }
  }

  List<_Piece> _generate(int seed) {
    final rng = math.Random(seed * 7919 + 13);
    return List.generate(26, (i) {
      final angle = -math.pi / 2 + (rng.nextDouble() - 0.5) * 1.9;
      return _Piece(
        color: widget.colors[i % widget.colors.length],
        angle: angle,
        speed: 0.35 + rng.nextDouble() * 0.5,
        sway: (rng.nextDouble() - 0.5) * 0.16,
        spin: (rng.nextDouble() - 0.5) * 10,
        width: 5 + rng.nextDouble() * 5,
        height: 8 + rng.nextDouble() * 7,
        round: rng.nextBool(),
        delay: rng.nextDouble() * 0.12,
      );
    });
  }

  @override
  void dispose() {
    _fall.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = MotionScope.of(context);
    _fall.motion = tokens.celebration;
    if (tokens.reduced || widget.playToken == 0) {
      return const SizedBox.shrink();
    }
    return ExcludeSemantics(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _fall,
          builder: (context, _) {
            final t = _fall.value.clamp(0.0, 1.0);
            if (t >= 1) return const SizedBox.shrink();
            return CustomPaint(
              painter: _ConfettiPainter(pieces: _pieces, t: t),
              size: Size.infinite,
            );
          },
        ),
      ),
    );
  }
}

class _Piece {
  const _Piece({
    required this.color,
    required this.angle,
    required this.speed,
    required this.sway,
    required this.spin,
    required this.width,
    required this.height,
    required this.round,
    required this.delay,
  });

  final Color color;
  final double angle;
  final double speed;
  final double sway;
  final double spin;
  final double width;
  final double height;
  final bool round;
  final double delay;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.pieces, required this.t});

  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final origin = Offset(size.width / 2, size.height * 0.22);
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      // Outward burst decelerates; gravity takes over.
      final travel =
          p.speed * size.height * (0.5 * local + 0.5 * local * local);
      final x =
          origin.dx +
          math.cos(p.angle) * travel * 0.7 +
          math.sin(local * math.pi * 2 + p.spin) * p.sway * size.width;
      final y = origin.dy + math.sin(p.angle) * travel * 0.4 + travel;
      if (y > size.height + 20) continue;
      final opacity = local < 0.7 ? 1.0 : (1 - local) / 0.3;
      final paint = Paint()..color = p.color.withValues(alpha: opacity);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * local);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.width / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.width,
              height: p.height * (0.4 + 0.6 * math.cos(local * math.pi)),
            ),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => oldDelegate.t != t;
}
