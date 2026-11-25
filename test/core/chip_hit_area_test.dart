import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/core/widgets/chip_hit_area.dart';

void main() {
  testWidgets('extends a 32dp chip visual to a 48dp target', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ChipHitArea(
            onTap: () => taps++,
            child: const SizedBox(width: 32, height: 32),
          ),
        ),
      ),
    );

    final box = tester.renderObject<RenderBox>(find.byType(ChipHitArea));
    expect(box.size.height, 48);

    // Tap in the padding above the visual: the transparent layer behind the
    // chip must still receive it.
    final center = tester.getCenter(find.byType(ChipHitArea));
    await tester.tapAt(center - const Offset(0, 20));
    expect(taps, 1);
  });
}
