import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:motor/motor.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_scheme_provider.dart';
import '../../../core/motion/shape_morph.dart';
import '../../../core/motion/spring_press.dart';
import '../../../l10n/generated/app_localizations.dart';

/// The signature NowPill check-off control.
///
/// At rest it is a capsule (pill) outline. When checked, a spatial spring
/// drives a shape morph into a cookie polygon while an effects spring carries
/// the fill and border — so color never overshoots, but the silhouette and icon
/// bounce. A press squish gives immediate feedback before the data changes.
/// Honors the active motion scheme (expressive bounce vs. standard / reduced).
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

class _CheckPillState extends State<CheckPill> with TickerProviderStateMixin {
  late final SingleMotionController _shape;
  late final SingleMotionController _fill;
  late final Morph _morph;

  @override
  void initState() {
    super.initState();
    _morph = shapeMorph(M3EShapeKind.pill, M3EShapeKind.cookie9Sided);
    _shape = SingleMotionController(
      motion: MotionTokens.expressive.spatialFast,
      vsync: this,
      initialValue: widget.checked ? 1 : 0,
    );
    _fill = SingleMotionController(
      motion: MotionTokens.expressive.effectsFast,
      vsync: this,
      initialValue: widget.checked ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(CheckPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.checked != widget.checked) {
      final target = widget.checked ? 1.0 : 0.0;
      _shape.animateTo(target);
      _fill.animateTo(target);
    }
  }

  @override
  void dispose() {
    _shape.dispose();
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final tokens = MotionScope.of(context);
    final active = widget.activeColor ?? theme.colorScheme.primary;
    final outline = theme.colorScheme.outline;

    // Retarget both springs in flight on a scheme switch.
    _shape.motion = tokens.spatialFast;
    _fill.motion = tokens.effectsFast;

    // container: true keeps the pill a distinct semantics node even inside
    // cards that merge sibling text into their spoken label — screen readers
    // (and tests) can target the check control on its own.
    return Semantics(
      container: true,
      button: true,
      checked: widget.checked,
      label:
          widget.semanticLabel ??
          (widget.checked
              ? AppLocalizations.of(context).completedLabel
              : AppLocalizations.of(context).markComplete),
      child: SpringPress(
        child: GestureDetector(
          onTap: () => widget.onChanged(!widget.checked),
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: AnimatedBuilder(
              animation: Listenable.merge([_shape, _fill]),
              builder: (context, _) {
                final shapeT = _shape.value.clamp(0.0, 1.0);
                final fillT = _fill.value.clamp(0.0, 1.0);
                // Spring overshoot is expressed as scale, never as progress
                // past the end of the polygon morph (which would extrapolate
                // its geometry).
                final overshoot = (_shape.value - 1).clamp(0.0, 0.35);
                final fill = Color.lerp(
                  theme.colorScheme.surfaceContainerHigh,
                  active,
                  fillT,
                )!;
                final iconColor = Color.lerp(
                  outline,
                  theme.colorScheme.onPrimary,
                  fillT,
                )!;
                final border = Color.lerp(outline, active, fillT)!;
                return Transform.scale(
                  scale: 1 + 0.12 * overshoot,
                  child: CustomPaint(
                    painter: MorphShapePainter(
                      morph: _morph,
                      progress: shapeT,
                      fill: fill,
                      borderColor: border,
                      borderWidth: 1.5,
                    ),
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          IgnorePointer(
                            child: Opacity(
                              opacity: 1 - shapeT,
                              child: Transform.rotate(
                                angle: shapeT * 0.4,
                                child: Icon(
                                  M3EIcons.circle_outlined,
                                  size: widget.size * 0.55,
                                  color: iconColor,
                                ),
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: Opacity(
                              opacity: shapeT,
                              child: Transform.rotate(
                                angle: (1 - shapeT) * -0.4,
                                child: Icon(
                                  M3EIcons.check,
                                  size: widget.size * 0.55,
                                  color: iconColor,
                                ),
                              ),
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
        ),
      ),
    );
  }
}
