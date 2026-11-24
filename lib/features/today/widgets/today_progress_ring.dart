import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:motor/motor.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_scheme_provider.dart';
import '../../../core/motion/shape_morph.dart';
import '../../../l10n/generated/app_localizations.dart';

/// The Today dashboard's spring-driven progress ring.
///
/// The arc sweeps with an expressive spring (overshooting slightly on the way
/// to a new value). When [celebrate] flips true, the ring springs past 100%
/// and settles while a shape-morph burst blooms behind it. Honors the active
/// motion scheme: reduced motion renders a static ring without the burst.
class TodayProgressRing extends StatefulWidget {
  const TodayProgressRing({
    required this.progress,
    required this.done,
    required this.total,
    required this.celebrate,
    this.size = 132,
    super.key,
  });

  /// 0…1 completion fraction.
  final double progress;
  final int done;
  final int total;

  /// Whether the all-done celebration should play.
  final bool celebrate;

  final double size;

  @override
  State<TodayProgressRing> createState() => _TodayProgressRingState();
}

class _TodayProgressRingState extends State<TodayProgressRing>
    with TickerProviderStateMixin {
  late final SingleMotionController _sweep;
  late final SingleMotionController _burst;
  late final Morph _bloom;
  late final Morph _settle;

  @override
  void initState() {
    super.initState();
    // Two-stage bloom: soft burst → flower → burst. The midpoint shape is
    // shared, so crossing it mid-animation is continuous.
    _bloom = shapeMorph(M3EShapeKind.softBurst, M3EShapeKind.flower);
    _settle = shapeMorph(M3EShapeKind.flower, M3EShapeKind.burst);
    _sweep = SingleMotionController(
      motion: MotionTokens.expressive.spatialSlow,
      vsync: this,
      initialValue: widget.progress,
    );
    _burst = SingleMotionController(
      motion: MotionTokens.expressive.spatialSlow,
      vsync: this,
      initialValue: 0,
    );
    if (widget.celebrate) {
      _sweep.animateTo(1);
      _burst.animateTo(1);
    }
  }

  @override
  void didUpdateWidget(TodayProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _sweep.animateTo(widget.progress);
    }
    if (!oldWidget.celebrate && widget.celebrate) {
      // Re-sweep from a partial arc; the expressive spring overshoots its
      // target, which the painter turns into a small scale pop.
      _sweep
        ..value = 0.7
        ..animateTo(1);
      _burst
        ..value = 0
        ..animateTo(1);
    } else if (oldWidget.celebrate && !widget.celebrate) {
      _burst.animateTo(0);
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final tokens = MotionScope.of(context);
    _sweep.motion = tokens.spatialSlow;
    _burst.motion = tokens.spatialSlow;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Semantics(
        container: true,
        label: AppLocalizations.of(context)
            .a11yRingProgress(widget.done, widget.total),
        child: AnimatedBuilder(
          animation: Listenable.merge([_sweep, _burst]),
          builder: (context, _) {
            // Unclamped on purpose: the expressive spring overshoots past 1.0
            // during the celebration before settling.
            final sweep = tokens.reduced ? widget.progress : _sweep.value;
            final burst = tokens.reduced ? 0.0 : _burst.value.clamp(0.0, 1.0);
            return CustomPaint(
              painter: _RingPainter(
                progress: sweep,
                burst: burst,
                bloomMorph: _bloom,
                settleMorph: _settle,
                trackColor: theme.colorScheme.surfaceContainerHigh,
                ringColor: widget.celebrate
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.primary,
                burstColor: theme.colorScheme.tertiaryContainer,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${widget.done}/${widget.total}',
                      style: theme.typography.emphasized.headlineSmall.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      widget.celebrate
                          ? AppLocalizations.of(context).statsAllDone
                          : AppLocalizations.of(context).ringDoneToday,
                      style: theme.typography.baseline.labelSmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.burst,
    required this.bloomMorph,
    required this.settleMorph,
    required this.trackColor,
    required this.ringColor,
    required this.burstColor,
  });

  final double progress;
  final double burst;
  final Morph bloomMorph;
  final Morph settleMorph;
  final Color trackColor;
  final Color ringColor;
  final Color burstColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = size.width * 0.09;
    final radius = (size.width - strokeWidth) / 2 - size.width * 0.06;

    // Celebration burst: a two-stage shape morph blooming behind the ring.
    // Both halves share the flower silhouette, so the swap is seamless.
    if (burst > 0) {
      final scale = 0.55 + 0.65 * burst;
      final firstHalf = burst <= 0.5;
      final morph = firstHalf ? bloomMorph : settleMorph;
      final local = firstHalf ? burst * 2 : (burst - 0.5) * 2;
      final path = morph.toPath(progress: local.clamp(0.0, 1.0));
      final bounds = path.getBounds();
      if (!bounds.isEmpty) {
        final target = radius * 2 * scale;
        final matrix = Matrix4.identity()
          ..scaleByDouble(target / bounds.width, target / bounds.height, 1, 1)
          ..translateByDouble(-bounds.left, -bounds.top, 0, 1);
        final scaled = path.transform(matrix.storage);
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate((burst - 0.5) * 0.18);
        canvas.translate(-center.dx, -center.dy);
        canvas.translate(center.dx - target / 2, center.dy - target / 2);
        canvas.drawPath(
          scaled,
          Paint()
            ..color = burstColor.withValues(alpha: 0.55 * (1 - burst * 0.35)),
        );
        canvas.restore();
      }
    }

    // The spring may overshoot past the target; express that as a small scale
    // pop rather than drawing more than a full circle (which overlaps arcs).
    final arcProgress = progress.clamp(0.0, 1.0);
    final ringScale = 1 + 0.05 * (progress - 1).clamp(0.0, 0.4);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(ringScale);
    canvas.translate(-center.dx, -center.dy);

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    if (arcProgress > 0) {
      final arc = Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * arcProgress,
        false,
        arc,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.burst != burst ||
      oldDelegate.bloomMorph != bloomMorph ||
      oldDelegate.settleMorph != settleMorph ||
      oldDelegate.ringColor != ringColor ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.burstColor != burstColor;
}
