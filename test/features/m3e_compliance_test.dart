import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/core/motion/motion_scheme_provider.dart';
import 'package:nowpill/features/tasks/widgets/check_pill.dart';

import '../helpers/test_localizations.dart';

/// Regressions for the M3 Expressive audit: touch-target size and contrast of
/// the signature check control when a user-chosen accent is its fill.
void main() {
  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(),
          child: M3ETheme(
            data: M3EThemeData.light(),
            child: MotionScope(child: child),
          ),
        ),
      ),
    );
  }

  double luminance(Color color) {
    double channel(double c) => c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  testWidgets('CheckPill exposes a 48x48dp target around its 32dp visual', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(Center(child: CheckPill(checked: false, onChanged: (_) {}))),
    );

    final hit = find.byWidgetPredicate(
      (w) => w is SizedBox && w.width == 48 && w.height == 48,
    );
    expect(hit, findsOneWidget);
    expect(tester.renderObject<RenderBox>(hit).size, const Size(48, 48));

    final visual = find.byWidgetPredicate(
      (w) => w is SizedBox && w.width == 32 && w.height == 32,
    );
    expect(visual, findsOneWidget);
  });

  testWidgets('checking the pill spins the box once', (tester) async {
    var checked = false;
    await tester.pumpWidget(
      wrap(
        StatefulBuilder(
          builder: (context, setState) => Center(
            child: CheckPill(
              checked: checked,
              semanticLabel: 'spin-pill',
              onChanged: (v) => setState(() => checked = v),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final spin = find.byKey(const Key('check-pill-spin'));
    expect(spin, findsOneWidget);
    // storage[1] of a Z-rotation is sin(angle): upright before the tap.
    expect(
      tester.widget<Transform>(spin).transform.storage[1],
      closeTo(0, 1e-6),
    );

    await tester.tap(find.bySemanticsLabel('spin-pill'));
    final observed = <double>[];
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      observed.add(tester.widget<Transform>(spin).transform.storage[1]);
    }
    expect(observed.map((v) => v.abs()).reduce(math.max), greaterThan(0.01));

    await tester.pump(const Duration(milliseconds: 1500));
    expect(checked, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('checked icon contrasts with a light accent fill', (
    tester,
  ) async {
    const accent = Color(0xFFFFB454); // amber: ~1.8:1 against white
    await tester.pumpWidget(
      wrap(
        Center(
          child: CheckPill(
            checked: true,
            activeColor: accent,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));

    final icon = tester.widget<Icon>(
      find.byWidgetPredicate((w) => w is Icon && w.icon == M3EIcons.check),
    );
    expect(contrast(icon.color!, accent), greaterThanOrEqualTo(3.0));
  });
}
