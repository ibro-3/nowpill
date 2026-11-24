import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/core/motion/motion_scheme_provider.dart';
import 'package:nowpill/core/motion/shape_morph.dart';
import 'package:nowpill/core/motion/spring_press.dart';

/// v0.9.2 motion primitives: cached morphs, state-driven shape changes, and a
/// press wrapper that does not steal taps from its child.
void main() {
  Widget wrap(Widget child, {bool osReduced = false}) {
    return ProviderScope(
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: osReduced),
          child: M3ETheme(
            data: M3EThemeData.light(),
            child: MotionScope(child: child),
          ),
        ),
      ),
    );
  }

  test('shapeMorph caches each ordered pair', () {
    final forward = shapeMorph(M3EShapeKind.pill, M3EShapeKind.cookie9Sided);
    final again = shapeMorph(M3EShapeKind.pill, M3EShapeKind.cookie9Sided);
    final reverse = shapeMorph(M3EShapeKind.cookie9Sided, M3EShapeKind.pill);

    expect(identical(forward, again), isTrue);
    expect(identical(forward, reverse), isFalse);
  });

  testWidgets('MorphingShape crossfades its child as the state changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var active = false;
    await tester.pumpWidget(
      wrap(
        StatefulBuilder(
          builder: (context, setState) => Center(
            child: MorphingShape(
              key: const ValueKey('badge'),
              from: M3EShapeKind.cookie6Sided,
              to: M3EShapeKind.cookie9Sided,
              active: active,
              size: 44,
              color: const Color(0xFFDDDDDD),
              activeColor: const Color(0xFF2DD4A8),
              activeChild: const SizedBox(key: ValueKey('active')),
              child: const SizedBox(key: ValueKey('resting')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    Opacity opacityAt(int index) => tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('badge')),
        matching: find.byType(Opacity),
      ).at(index),
    );

    expect(opacityAt(1).opacity, 0);
    active = true;
    await tester.pumpWidget(
      wrap(
        StatefulBuilder(
          builder: (context, setState) => Center(
            child: MorphingShape(
              key: const ValueKey('badge'),
              from: M3EShapeKind.cookie6Sided,
              to: M3EShapeKind.cookie9Sided,
              active: active,
              size: 44,
              color: const Color(0xFFDDDDDD),
              activeColor: const Color(0xFF2DD4A8),
              activeChild: const SizedBox(key: ValueKey('active')),
              child: const SizedBox(key: ValueKey('resting')),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));

    expect(opacityAt(1).opacity, greaterThan(0.99));
    expect(tester.takeException(), isNull);
  });

  testWidgets('SpringPress keeps the wrapped tap target tappable', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      wrap(
        Center(
          child: SpringPress(
            child: GestureDetector(
              key: const ValueKey('target'),
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox(width: 48, height: 48),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('target')));
    await tester.pump();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MorphingShape settles under OS reduce-motion', (tester) async {
    var active = false;
    Widget tree() => wrap(
      StatefulBuilder(
        builder: (context, setState) => Center(
          child: MorphingShape(
            key: const ValueKey('reduced-badge'),
            from: M3EShapeKind.circle,
            to: M3EShapeKind.cookie6Sided,
            active: active,
            size: 32,
            color: const Color(0xFFDDDDDD),
            activeColor: const Color(0xFF2DD4A8),
            activeChild: const SizedBox(key: ValueKey('active')),
            child: const SizedBox(key: ValueKey('resting')),
          ),
        ),
      ),
      osReduced: true,
    );

    await tester.pumpWidget(tree());
    await tester.pump();
    active = true;
    await tester.pumpWidget(tree());
    await tester.pump(const Duration(milliseconds: 900));

    final incoming = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('reduced-badge')),
        matching: find.byType(Opacity),
      ).at(1),
    );
    expect(incoming.opacity, greaterThan(0.99));
    expect(tester.takeException(), isNull);
  });
}
