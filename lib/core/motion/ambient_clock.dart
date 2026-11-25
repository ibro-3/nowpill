import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A monotonically increasing seconds clock for continuous ambient motion.
///
/// Springs settle, which makes a looping spring read as stiff. Ambient motion
/// instead uses elapsed time directly, so orbits, drifts and waves with
/// different frequencies stay seamless: the clock never wraps back to zero.
/// It is also a [Listenable], so callers can plug it straight into an
/// [AnimatedBuilder].
///
/// The clock is idle under reduced motion (the caller decides when to start
/// it). Passing a [TickerProvider] means go_router's `TickerMode` pauses it
/// automatically while its tab is offstage.
class AmbientClock {
  AmbientClock(this.vsync, {String? debugLabel})
    : _debugLabel = debugLabel ?? 'AmbientClock';

  final TickerProvider vsync;
  final String _debugLabel;

  /// Seconds since the clock was first started.
  final ValueNotifier<double> seconds = ValueNotifier<double>(0);

  Ticker? _ticker;

  /// Elapsed time already banked before the current ticker run. Flutter's
  /// [Ticker] resets its own elapsed value on every [Ticker.stop], so the
  /// clock keeps the total here to resume seamlessly.
  double _banked = 0;

  bool get isRunning => _ticker?.isActive ?? false;

  /// Starts (or resumes) elapsed time. Safe to call repeatedly.
  void start() {
    _ticker ??= Ticker(
      (elapsed) => seconds.value = _banked + elapsed.inMicroseconds / 1000000.0,
      debugLabel: _debugLabel,
    );
    if (!_ticker!.isActive) _ticker!.start();
  }

  /// Freezes elapsed time; [start] resumes from the same value.
  void stop() {
    if (_ticker?.isActive ?? false) {
      _banked = seconds.value;
      _ticker!.stop();
    }
  }

  /// Freezes and returns to zero (used when motion is reduced).
  void reset() {
    stop();
    _banked = 0;
    seconds.value = 0;
  }

  void dispose() {
    _ticker?.dispose();
    seconds.dispose();
  }
}
