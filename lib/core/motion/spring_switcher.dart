import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

import 'app_motion.dart';
import 'motion_scheme_provider.dart';

/// A token-driven fade-through that replays whenever [switchKey] changes.
///
/// Used for tab branches and filter changes, where the content widget is
/// replaced instantly: the incoming content fades and rises into place instead
/// of snapping. State is preserved because the child itself is not rebuilt by
/// this widget — only its transition is. Reduced motion renders the child
/// directly.
class SpringSwitcher extends StatefulWidget {
  const SpringSwitcher({
    required this.switchKey,
    required this.child,
    this.rise = 8,
    super.key,
  });

  /// Changing this value replays the entrance.
  final Object switchKey;
  final Widget child;
  final double rise;

  @override
  State<SpringSwitcher> createState() => _SpringSwitcherState();
}

class _SpringSwitcherState extends State<SpringSwitcher>
    with TickerProviderStateMixin {
  late final SingleMotionController _rise;
  late final SingleMotionController _fade;

  @override
  void initState() {
    super.initState();
    _rise = SingleMotionController(
      motion: MotionTokens.expressive.spatialFast,
      vsync: this,
      initialValue: 1,
    );
    _fade = SingleMotionController(
      motion: MotionTokens.expressive.effectsFast,
      vsync: this,
      initialValue: 1,
    );
  }

  @override
  void didUpdateWidget(SpringSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.switchKey != widget.switchKey) {
      _rise
        ..value = 0
        ..animateTo(1);
      _fade
        ..value = 0
        ..animateTo(1);
    }
  }

  @override
  void dispose() {
    _rise.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = MotionScope.of(context);
    _rise.motion = tokens.spatialFast;
    _fade.motion = tokens.effectsFast;
    if (tokens.reduced) return widget.child;
    return AnimatedBuilder(
      animation: Listenable.merge([_rise, _fade]),
      builder: (context, child) {
        final rise = _rise.value.clamp(0.0, 1.0);
        final fade = _fade.value.clamp(0.0, 1.0);
        return Opacity(
          alwaysIncludeSemantics: true,
          opacity: fade,
          child: Transform.translate(
            offset: Offset(0, widget.rise * (1 - rise)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
