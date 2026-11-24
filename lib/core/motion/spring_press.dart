import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

import 'app_motion.dart';
import 'motion_scheme_provider.dart';

/// Adds a small spring squish on press without changing layout or swallowing
/// gestures.
///
/// A [Listener] observes pointer events before the child's gesture recognizer
/// enters the arena, so wrapping a button keeps its tap behavior intact. Use it
/// sparingly: prominent controls and selection chips, not every list row.
class SpringPress extends StatefulWidget {
  const SpringPress({required this.child, this.pressedScale = 0.94, super.key});

  final Widget child;

  /// Scale at the bottom of the press. Defaults to a subtle 6% squish.
  final double pressedScale;

  @override
  State<SpringPress> createState() => _SpringPressState();
}

class _SpringPressState extends State<SpringPress>
    with SingleTickerProviderStateMixin {
  late final SingleMotionController _press;

  @override
  void initState() {
    super.initState();
    _press = SingleMotionController(
      motion: MotionTokens.expressive.spatialFast,
      vsync: this,
      initialValue: 0,
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _release(_) {
    if (_press.value != 0) _press.animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = MotionScope.of(context);
    _press.motion = tokens.spatialFast;

    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: (_) => _press.animateTo(1),
      onPointerUp: _release,
      onPointerCancel: _release,
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, child) => Transform.scale(
          scale: 1 - (1 - widget.pressedScale) * _press.value.clamp(0.0, 1.0),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
