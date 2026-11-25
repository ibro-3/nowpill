import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:motor/motor.dart';

import '../../../core/motion/ambient_clock.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_scheme_provider.dart';
import '../../../l10n/generated/app_localizations.dart';

/// The Today dashboard's spring-driven progress ring.
///
/// The arc sweeps with an expressive spring (overshooting slightly on the way
/// to a new value). When [celebrate] flips true, the ring springs past 100%
/// and settles while its color blends to tertiary. Honors the active motion
/// scheme: reduced motion renders a static ring.
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
  late final SingleMotionController _ringBlend;

  /// Travelling wave along the arc. Time-based (not a spring) so the wiggle
  /// keeps a constant tempo while the progress spring sweeps independently.
  late final AmbientClock _wave = AmbientClock(
    this,
    debugLabel: 'TodayProgressRing.wave',
  );
  MotionTokens? _applied;
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    _sweep = SingleMotionController(
      motion: MotionTokens.expressive.spatialSlow,
      vsync: this,
      initialValue: widget.progress,
    );
    // Color is an effect: it never inherits the sweep's bounce.
    _ringBlend = SingleMotionController(
      motion: MotionTokens.expressive.effectsFast,
      vsync: this,
      initialValue: 0,
    );
    if (widget.celebrate) {
      _sweep.animateTo(1);
      _ringBlend.animateTo(1);
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
      _ringBlend.animateTo(1);
    } else if (oldWidget.celebrate && !widget.celebrate) {
      _ringBlend.animateTo(0);
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _ringBlend.dispose();
    _wave.dispose();
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
        if (!mounted) return;
        if (tokens.reduced) {
          _wave.reset();
        } else {
          _wave.start();
        }
      });
    }
    _sweep.motion = tokens.spatialSlow;
    _ringBlend.motion = tokens.effectsFast;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Semantics(
        container: true,
        label: AppLocalizations.of(context)
            .a11yRingProgress(widget.done, widget.total),
        child: AnimatedBuilder(
          animation: Listenable.merge([_sweep, _ringBlend, _wave.seconds]),
          builder: (context, _) {
            // Unclamped on purpose: the expressive spring overshoots past 1.0
            // during the celebration before settling.
            final sweep = tokens.reduced ? widget.progress : _sweep.value;
            final ringT = tokens.reduced
                ? (widget.celebrate ? 1.0 : 0.0)
                : _ringBlend.value.clamp(0.0, 1.0);
            final ringColor = Color.lerp(
              theme.colorScheme.primary,
              theme.colorScheme.tertiary,
              ringT,
            )!;
            return CustomPaint(
              painter: _RingPainter(
                progress: sweep,
                wavePhase: tokens.reduced
                    ? 0.0
                    : 2 *
                          math.pi *
                          (_wave.seconds.value /
                              (tokens.ambientWave.inMicroseconds / 1000000.0)),
                trackColor: theme.colorScheme.surfaceContainerHigh,
                ringColor: ringColor,
              ),
              child: Center(
                // The label must never overflow the ring at large system text
                // (or when the hero card narrows the available width).
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${widget.done}/${widget.total}',
                        style: theme.typography.emphasized.headlineSmall
                            .copyWith(color: theme.colorScheme.onSurface),
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
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Radial distance of the hero ring's wavy stroke at [t] along the swept arc.
///
/// The wave keeps its full amplitude at both ends. **My design decision (not
/// in M3):** the caller uses a whole number of cycles so the wave's value at
/// t=0 and t=1 matches and a full circle closes without flattening the top.
double wavyRingRadius({
  required double t,
  required double radius,
  required double amplitude,
  required double cycles,
  required double wavePhase,
}) {
  return radius + amplitude * math.sin(2 * math.pi * cycles * t - wavePhase);
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.wavePhase,
    required this.trackColor,
    required this.ringColor,
  });

  final double progress;

  /// Phase of the wiggly arc, advanced by the ambient wave clock.
  final double wavePhase;
  final Color trackColor;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    // From M3: circular progress ActiveThickness/TrackThickness default to 4dp,
    // and M3 Expressive makes track height configurable. My design decision
    // (not in M3): 6dp here — a touch heavier than the default, still far from
    // the old diameter-scaled band (~12dp at 132dp).
    const strokeWidth = 6.0;
    final radius = (size.width - strokeWidth) / 2 - size.width * 0.06;

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
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      // A wiggly stroke: radial offset follows a travelling sine wave. The
      // wave is sampled along the swept arc so its wavelength stays constant
      // in logical pixels as progress grows. Very short arcs stay calm.
      // Whole cycles keep the wave continuous where the full circle closes.
      final sweep = 2 * math.pi * arcProgress;
      final amplitude = strokeWidth * 0.42 * math.min(1.0, arcProgress * 6);
      // From M3: the waveform scales with the component size (feedback.md).
      // My design decision (not in M3): 0.25 of the diameter rather than the
      // 0.375 ratio of M3's 15dp/40dp default, giving ~11 waves at 132dp
      // instead of 7.
      final wavelength = size.width * 0.25;
      final cycles = math.max(
        1.0,
        (sweep * radius / wavelength).roundToDouble(),
      );
      const steps = 120;
      final wavy = Path();
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final theta = -math.pi / 2 + sweep * t;
        final r = wavyRingRadius(
          t: t,
          radius: radius,
          amplitude: amplitude,
          cycles: cycles,
          wavePhase: wavePhase,
        );
        final p = Offset(
          center.dx + r * math.cos(theta),
          center.dy + r * math.sin(theta),
        );
        if (i == 0) {
          wavy.moveTo(p.dx, p.dy);
        } else {
          wavy.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(wavy, arc);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.wavePhase != wavePhase ||
      oldDelegate.ringColor != ringColor ||
      oldDelegate.trackColor != trackColor;
}
