import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

import 'app_motion.dart';
import 'motion_scheme_provider.dart';

/// A one-shot spring entrance: the child fades in and rises into place.
///
/// [index] staggers siblings, capped at [maxStagger] so a long list never
/// keeps the last item invisible. The rise is spatial (it overshoots on the
/// expressive scheme); opacity is carried by a separate effects spring so it
/// never bounces. Under reduced motion the child renders statically.
class SpringEntrance extends StatefulWidget {
  const SpringEntrance({
    required this.child,
    this.index = 0,
    this.rise = 18,
    this.staggerStep = const Duration(milliseconds: 60),
    this.maxStagger = const Duration(milliseconds: 180),
    super.key,
  });

  final Widget child;
  final int index;
  final double rise;
  final Duration staggerStep;
  final Duration maxStagger;

  @override
  State<SpringEntrance> createState() => _SpringEntranceState();
}

class _SpringEntranceState extends State<SpringEntrance>
    with SingleTickerProviderStateMixin {
  late final SingleMotionController _rise;

  @override
  void initState() {
    super.initState();
    _rise = SingleMotionController(
      motion: MotionTokens.expressive.spatialDefault,
      vsync: this,
      initialValue: 0,
    );
    // Design decision (M3 publishes no stagger values): a bounded, short
    // stagger. A Future rather than a Timer keeps widget tests bounded.
    final delay = Duration(
      microseconds: (widget.staggerStep.inMicroseconds * widget.index).clamp(
        0,
        widget.maxStagger.inMicroseconds,
      ),
    );
    Future<void>.delayed(delay, () {
      if (mounted) _rise.animateTo(1);
    });
  }

  @override
  void dispose() {
    _rise.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = MotionScope.of(context);
    _rise.motion = tokens.spatialDefault;
    if (tokens.reduced) return widget.child;
    return AnimatedBuilder(
      animation: _rise,
      builder: (context, child) {
        final t = _rise.value.clamp(0.0, 1.0);
        return Opacity(
          // Keep semantics available from the first frame: an entrance must
          // not hide controls from screen readers (or from widget tests).
          alwaysIncludeSemantics: true,
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, widget.rise * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
