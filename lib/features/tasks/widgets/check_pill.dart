import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:motor/motor.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_scheme_provider.dart';

/// The signature NowPill check-off control.
///
/// At rest it is a capsule (pill) outline. When checked, a spring drives a
/// shape morph into a cookie polygon, the fill color springs in, and the icon
/// swaps with a slight rotation overshoot. Honors the active motion scheme
/// (expressive bounce vs. standard / reduced).
class CheckPill extends StatefulWidget {
  const CheckPill({
    required this.checked,
    required this.onChanged,
    this.size = 32,
    this.activeColor,
    this.semanticLabel,
    super.key,
  });

  final bool checked;
  final ValueChanged<bool> onChanged;
  final double size;
  final Color? activeColor;
  final String? semanticLabel;

  @override
  State<CheckPill> createState() => _CheckPillState();
}

class _CheckPillState extends State<CheckPill>
    with SingleTickerProviderStateMixin {
  late final SingleMotionController _progress;
  late final Morph _morph;

  @override
  void initState() {
    super.initState();
    _morph = Morph(
      M3EMaterialNewShapes.pill,
      M3EMaterialNewShapes.cookie9Sided,
    );
    _progress = SingleMotionController(
      motion: MotionTokens.expressive.spatialFast,
      vsync: this,
      initialValue: widget.checked ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(CheckPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.checked != widget.checked) {
      _progress.animateTo(widget.checked ? 1 : 0);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final tokens = MotionScope.of(context);
    final active = widget.activeColor ?? theme.colorScheme.primary;
    final outline = theme.colorScheme.outline;

    // Retarget the spring when the motion scheme changes.
    _progress.motion = tokens.spatialFast;

    // container: true keeps the pill a distinct semantics node even inside
    // cards that merge sibling text into their spoken label — screen readers
    // (and tests) can target the check control on its own.
    return Semantics(
      container: true,
      button: true,
      checked: widget.checked,
      label:
          widget.semanticLabel ??
          (widget.checked ? 'Completed' : 'Mark complete'),
      child: GestureDetector(
        onTap: () => widget.onChanged(!widget.checked),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _progress,
            builder: (context, _) {
              final t = _progress.value.clamp(0.0, 1.0);
              final fill = Color.lerp(
                theme.colorScheme.surfaceContainerHigh,
                active,
                t,
              )!;
              final iconColor = Color.lerp(
                outline,
                theme.colorScheme.onPrimary,
                t,
              )!;
              return CustomPaint(
                painter: _CheckPillPainter(
                  morph: _morph,
                  progress: t,
                  fill: fill,
                  borderColor: Color.lerp(outline, active, t)!,
                ),
                child: Center(
                  child: Transform.rotate(
                    angle: (1 - t) * -0.4,
                    child: Icon(
                      widget.checked
                          ? M3EIcons.check
                          : M3EIcons.circle_outlined,
                      size: widget.size * 0.55,
                      color: iconColor,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CheckPillPainter extends CustomPainter {
  _CheckPillPainter({
    required this.morph,
    required this.progress,
    required this.fill,
    required this.borderColor,
  });

  final Morph morph;
  final double progress;
  final Color fill;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final path = morph.toPath(progress: progress);
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

    canvas.drawPath(scaled, Paint()..color = fill);
    canvas.drawPath(
      scaled,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_CheckPillPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.fill != fill ||
      oldDelegate.borderColor != borderColor;
}
