import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:motor/motor.dart';

import 'app_motion.dart';
import 'motion_scheme_provider.dart';

/// Cached [Morph] instances, keyed by ordered shape pair.
///
/// Matching two polygons is relatively expensive; caching means a list of
/// habit badges all share one match instead of recomputing it per row.
final Map<(M3EShapeKind, M3EShapeKind), Morph> _morphCache = {};

/// Returns the cached morph from [from] to [to].
///
/// To animate in reverse, pass the pair in reverse order rather than running
/// the same morph backwards — the cache keeps both directions separate.
Morph shapeMorph(M3EShapeKind from, M3EShapeKind to) =>
    _morphCache.putIfAbsent((from, to), () => Morph(from.polygon, to.polygon));

/// Paints an expressive shape morph fitted to the available box.
///
/// Text and icons are drawn by the caller as a child, so they stay legible and
/// unaffected by the silhouette changing underneath them.
class MorphShapePainter extends CustomPainter {
  const MorphShapePainter({
    required this.morph,
    required this.progress,
    this.fill,
    this.borderColor,
    this.borderWidth = 0,
    this.rotation = 0,
  });

  final Morph morph;

  /// 0…1. Values are clamped: overshoot is expressed as scale by the caller,
  /// never by extrapolating polygon geometry.
  final double progress;
  final Color? fill;
  final Color? borderColor;
  final double borderWidth;
  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final path = morph.toPath(progress: progress.clamp(0.0, 1.0));
    final bounds = path.getBounds();
    if (bounds.isEmpty) return;
    final matrix = Matrix4.identity()
      ..scaleByDouble(
        size.width / bounds.width,
        size.height / bounds.height,
        1,
        1,
      )
      ..translateByDouble(-bounds.left, -bounds.top, 0, 1);
    final scaled = path.transform(matrix.storage);

    canvas.save();
    if (rotation != 0) {
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(rotation);
      canvas.translate(-size.width / 2, -size.height / 2);
    }
    if (fill != null) {
      canvas.drawPath(scaled, Paint()..color = fill!);
    }
    if (borderColor != null && borderWidth > 0) {
      canvas.drawPath(
        scaled,
        Paint()
          ..color = borderColor!
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(MorphShapePainter oldDelegate) =>
      oldDelegate.morph != morph ||
      oldDelegate.progress != progress ||
      oldDelegate.fill != fill ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.borderWidth != borderWidth ||
      oldDelegate.rotation != rotation;
}

/// A spring-driven counterpart to [M3EShapeContainer].
///
/// Morphs from [from] to [to] when [active] flips, using the spatial spring for
/// geometry and the effects spring for color (so fills never overshoot). Use it
/// for state changes — completion, selection, expansion — not as ornament.
class MorphingShape extends StatefulWidget {
  const MorphingShape({
    required this.from,
    required this.to,
    required this.active,
    required this.size,
    required this.color,
    required this.activeColor,
    this.child,
    this.activeChild,
    this.childBuilder,
    this.borderColor,
    this.activeBorderColor,
    this.borderWidth = 0,
    super.key,
  });

  final M3EShapeKind from;
  final M3EShapeKind to;
  final bool active;
  final double size;
  final Color color;
  final Color activeColor;

  /// Content shown when inactive. Ignored when [childBuilder] is supplied.
  final Widget? child;

  /// Optional replacement content, crossfaded with [child] during the morph.
  final Widget? activeChild;

  /// Receives the clamped morph progress (0…1) so icons can scale with shape.
  final Widget Function(double progress)? childBuilder;

  final Color? borderColor;
  final Color? activeBorderColor;
  final double borderWidth;

  @override
  State<MorphingShape> createState() => _MorphingShapeState();
}

class _MorphingShapeState extends State<MorphingShape>
    with TickerProviderStateMixin {
  late final SingleMotionController _shape;
  late final SingleMotionController _color;
  late Morph _morph;
  late M3EShapeKind _from;
  late M3EShapeKind _to;

  @override
  void initState() {
    super.initState();
    _from = widget.from;
    _to = widget.to;
    _morph = shapeMorph(_from, _to);
    _shape = SingleMotionController(
      motion: MotionTokens.expressive.spatialDefault,
      vsync: this,
      initialValue: widget.active ? 1 : 0,
    );
    _color = SingleMotionController(
      motion: MotionTokens.expressive.effectsDefault,
      vsync: this,
      initialValue: widget.active ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(MorphingShape oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.from != widget.from || oldWidget.to != widget.to) {
      _from = widget.from;
      _to = widget.to;
      _morph = shapeMorph(_from, _to);
    }
    if (oldWidget.active != widget.active) {
      final target = widget.active ? 1.0 : 0.0;
      _shape.animateTo(target);
      _color.animateTo(target);
    }
  }

  @override
  void dispose() {
    _shape.dispose();
    _color.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = MotionScope.of(context);
    // Retarget in flight when the scheme changes; no restart, no stacked
    // simulations.
    _shape.motion = tokens.spatialDefault;
    _color.motion = tokens.effectsDefault;

    return AnimatedBuilder(
      animation: Listenable.merge([_shape, _color]),
      builder: (context, _) {
        final shapeT = _shape.value.clamp(0.0, 1.0);
        final colorT = _color.value.clamp(0.0, 1.0);
        final resting = widget.childBuilder?.call(shapeT) ?? widget.child;
        Widget? content;
        if (widget.activeChild == null || resting == null) {
          content = resting;
        } else {
          content = Stack(
            alignment: Alignment.center,
            children: [
              IgnorePointer(
                // Opacity is an effect: crossfade on the non-overshooting
                // color spring, never on the morphing shape spring.
                child: Opacity(opacity: 1 - colorT, child: resting),
              ),
              IgnorePointer(
                child: Opacity(opacity: colorT, child: widget.activeChild),
              ),
            ],
          );
        }
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: MorphShapePainter(
              morph: _morph,
              progress: shapeT,
              fill: Color.lerp(widget.color, widget.activeColor, colorT),
              borderColor: widget.borderColor == null
                  ? null
                  : Color.lerp(
                      widget.borderColor,
                      widget.activeBorderColor ?? widget.borderColor,
                      colorT,
                    ),
              borderWidth: widget.borderWidth,
            ),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}
