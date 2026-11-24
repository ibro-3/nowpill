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
    with SingleTickerProviderStateMixin {
  late final SingleMotionController _reveal;

  @override
  void initState() {
    super.initState();
    _reveal = SingleMotionController(
      motion: MotionTokens.expressive.spatialFast,
      vsync: this,
      initialValue: 1,
    );
  }

  @override
  void didUpdateWidget(SpringSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.switchKey != widget.switchKey) {
      _reveal
        ..value = 0
        ..animateTo(1);
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = MotionScope.of(context);
    _reveal.motion = tokens.spatialFast;
    if (tokens.reduced) return widget.child;
    return AnimatedBuilder(
      animation: _reveal,
      builder: (context, child) {
        final t = _reveal.value.clamp(0.0, 1.0);
        return Opacity(
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
