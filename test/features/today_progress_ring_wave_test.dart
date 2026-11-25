import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/features/today/widgets/today_progress_ring.dart';

/// The hero ring's wavy stroke keeps its amplitude at the top of the arc, and
/// a full circle closes on itself because the caller uses whole cycles.
void main() {
  double radiusAt(double t, {double phase = 0.0}) => wavyRingRadius(
    t: t,
    radius: 50,
    amplitude: 6,
    // Whole cycles: the painter snaps to this integer.
    cycles: 4,
    wavePhase: phase,
  );

  test('wave is active at the top of the arc', () {
    for (final phase in [0.6, 1.3, 3.9, 5.7]) {
      expect((radiusAt(0, phase: phase) - 50).abs(), greaterThan(0.5));
    }
  });

  test('a whole number of cycles closes the full-circle seam', () {
    for (final phase in [0.0, 1.3, 3.9, 5.7]) {
      expect(
        radiusAt(1, phase: phase),
        closeTo(radiusAt(0, phase: phase), 1e-9),
      );
    }
  });

  test('the middle of the arc still oscillates', () {
    final radii = [for (var i = 1; i < 10; i++) radiusAt(i / 10, phase: 0.4)];
    expect(radii.any((r) => r > 50.5), isTrue);
    expect(radii.any((r) => r < 49.5), isTrue);
  });
}
