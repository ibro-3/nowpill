import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:motor/motor.dart';

import '../motion/app_motion.dart';
import '../motion/motion_scheme_provider.dart';

/// A determinate M3 progress indicator whose fill springs to its target.
///
/// M3 says a determinate indicator fills 0%→100%, and the wavy shape is the
/// expressive variant. The package draws the waveform and animates its phase,
/// but feeds `value` straight into the painter — so without this wrapper the
/// bar jumps between values. The fill is a geometry change, so it uses the
/// spatial spring; the waveform keeps the package's ambient phase animation.
///
/// [circular] switches to the flat circular variant: a closed 40dp ring with a
/// 4dp stroke (M3's published circular token set), which reads thinner than the
/// wavy linear shape's 10dp wave height. The circle has no waveform, so only
/// the spring drives it; under reduced motion the value is applied directly.
///
/// Under reduced motion the linear variant renders flat instead: it carries the
/// same semantics but stops the package's wave ticker entirely, rather than
/// leaving it running with a zero speed and no visible change.
class SpringWavyProgressBar extends StatefulWidget {
  const SpringWavyProgressBar({
    required this.value,
    this.circular = false,
    this.color,
    this.trackColor,
    this.semanticsLabel,
    this.semanticsValue,
    super.key,
  });

  /// Determinate progress in 0…1.
  final double value;

  /// Render a flat circular ring instead of a linear bar.
  final bool circular;

  final Color? color;
  final Color? trackColor;
  final String? semanticsLabel;
  final String? semanticsValue;

  @override
  State<SpringWavyProgressBar> createState() => _SpringWavyProgressBarState();
}

class _SpringWavyProgressBarState extends State<SpringWavyProgressBar>
    with TickerProviderStateMixin {
  late final SingleMotionController _fill = SingleMotionController(
    motion: MotionTokens.expressive.spatialDefault,
    vsync: this,
    initialValue: 0,
  );

  @override
  void initState() {
    super.initState();
    _fill.animateTo(widget.value.clamp(0.0, 1.0));
  }

  @override
  void didUpdateWidget(SpringWavyProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _fill.animateTo(widget.value.clamp(0.0, 1.0));
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  M3EProgressIndicator _indicator(double value, {required bool reduced}) {
    if (widget.circular) {
      return M3EProgressIndicator.circular(
        value: value,
        size: 40,
        color: widget.color,
        trackColor: widget.trackColor,
        semanticsLabel: widget.semanticsLabel,
        semanticsValue: widget.semanticsValue,
        key: const Key('spring-progress-circular'),
      );
    }
    if (reduced) {
      return M3EProgressIndicator.linear(
        value: value,
        color: widget.color,
        trackColor: widget.trackColor,
        semanticsLabel: widget.semanticsLabel,
        semanticsValue: widget.semanticsValue,
        key: const Key('spring-progress-flat'),
      );
    }
    return M3EProgressIndicator.linearWavy(
      value: value,
      color: widget.color,
      trackColor: widget.trackColor,
      semanticsLabel: widget.semanticsLabel,
      semanticsValue: widget.semanticsValue,
      key: const Key('spring-progress-wavy'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = MotionScope.of(context);
    // Retarget in flight if the scheme changes mid-animation.
    _fill.motion = tokens.spatialDefault;
    if (tokens.reduced) {
      return _indicator(widget.value.clamp(0.0, 1.0), reduced: true);
    }
    return AnimatedBuilder(
      animation: _fill,
      builder: (context, _) =>
          _indicator(_fill.value.clamp(0.0, 1.0), reduced: false),
    );
  }
}
