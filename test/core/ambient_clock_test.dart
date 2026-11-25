import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/core/motion/ambient_clock.dart';

/// Ambient motion is time-based so it glides instead of settling like a
/// spring. The clock must advance only while started: reduced motion leaves it
/// at zero, and pausing it mid-flight freezes the composition.
void main() {
  testWidgets('advances while running and freezes when stopped', (
    tester,
  ) async {
    late AmbientClock clock;
    await tester.pumpWidget(
      _ClockHost(onReady: (c) => clock = c, started: true),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(clock.seconds.value, greaterThan(0));

    clock.stop();
    final frozen = clock.seconds.value;
    await tester.pump(const Duration(milliseconds: 120));
    expect(clock.seconds.value, frozen);

    clock.start();
    // A ticker started outside a frame gets its start time on the next tick,
    // so give it one frame before measuring elapsed time again.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(clock.seconds.value, greaterThan(frozen));
  });

  testWidgets('stays at zero when never started (reduced motion)', (
    tester,
  ) async {
    late AmbientClock clock;
    await tester.pumpWidget(
      _ClockHost(onReady: (c) => clock = c, started: false),
    );
    await tester.pump(const Duration(milliseconds: 240));
    expect(clock.isRunning, isFalse);
    expect(clock.seconds.value, 0);
  });
}

class _ClockHost extends StatefulWidget {
  const _ClockHost({required this.onReady, required this.started});

  final ValueChanged<AmbientClock> onReady;
  final bool started;

  @override
  State<_ClockHost> createState() => _ClockHostState();
}

class _ClockHostState extends State<_ClockHost>
    with SingleTickerProviderStateMixin {
  late final AmbientClock _clock = AmbientClock(this);

  @override
  void initState() {
    super.initState();
    widget.onReady(_clock);
    if (widget.started) _clock.start();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
