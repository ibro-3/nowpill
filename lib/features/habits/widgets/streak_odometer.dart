import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:motor/motor.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_scheme_provider.dart';
import '../../../l10n/generated/app_localizations.dart';

/// A rolling "odometer" number for streak counts. When the value changes, the
/// digits slide vertically with a spring, giving a satisfying tally effect.
class StreakOdometer extends StatefulWidget {
  const StreakOdometer({
    required this.value,
    this.style,
    this.color,
    super.key,
  });

  final int value;
  final TextStyle? style;
  final Color? color;

  @override
  State<StreakOdometer> createState() => _StreakOdometerState();
}

class _StreakOdometerState extends State<StreakOdometer>
    with TickerProviderStateMixin {
  late final SingleMotionController _slide;
  late final SingleMotionController _fade;
  late int _previous;
  late int _current;
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    _previous = widget.value;
    _current = widget.value;
    _slide = SingleMotionController(
      motion: MotionTokens.expressive.spatialDefault,
      vsync: this,
      initialValue: 1,
    );
    // Digit position slides (spatial); the crossfade is an effect so it can
    // never overshoot past fully opaque.
    _fade = SingleMotionController(
      motion: MotionTokens.expressive.effectsDefault,
      vsync: this,
      initialValue: 1,
    );
  }

  @override
  void didUpdateWidget(StreakOdometer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _previous = oldWidget.value;
      _current = widget.value;
      _forward = _current >= _previous;
      _slide
        ..value = 0
        ..animateTo(1);
      _fade
        ..value = 0
        ..animateTo(1);
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final tokens = MotionScope.of(context);
    _slide.motion = tokens.spatialDefault;
    _fade.motion = tokens.effectsDefault;
    final style = (widget.style ?? theme.typography.emphasized.titleMedium)
        .copyWith(color: widget.color ?? theme.colorScheme.onSurface);

    return AnimatedBuilder(
      animation: Listenable.merge([_slide, _fade]),
      builder: (context, _) {
        final t = _slide.value.clamp(0.0, 1.0);
        final f = _fade.value.clamp(0.0, 1.0);
        // Outgoing digit slides away, incoming digit slides in.
        final dir = _forward ? 1.0 : -1.0;
        final outgoingOffset = -dir * t;
        final incomingOffset = dir * (1 - t);
        return Semantics(
          label: AppLocalizations.of(context).a11yStreak(widget.value),
          child: ExcludeSemantics(
            child: ClipRect(
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // Invisible sizer keeps the box stable.
                  Opacity(opacity: 0, child: Text('$_current', style: style)),
                  Positioned.fill(
                    child: FractionalTranslation(
                      translation: Offset(0, outgoingOffset),
                      child: Opacity(
                        opacity: 1 - f,
                        child: Align(
                          alignment: Alignment.center,
                          child: Text('$_previous', style: style),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: FractionalTranslation(
                      translation: Offset(0, incomingOffset),
                      child: Opacity(
                        opacity: f,
                        child: Align(
                          alignment: Alignment.center,
                          child: Text('$_current', style: style),
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
    );
  }
}
