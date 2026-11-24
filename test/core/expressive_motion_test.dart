import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/core/motion/motion_scheme_provider.dart';
import 'package:nowpill/core/motion/spring_entrance.dart';
import 'package:nowpill/core/motion/spring_switcher.dart';

/// v0.9.4: the shared expressive motion primitives keep controls in the
/// semantics tree during an entrance, replay on key changes, and render
/// statically when the OS requests reduced motion.
void main() {
  Widget wrap(Widget child, {bool reduced = false}) {
    return ProviderScope(
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: M3ETheme(
            data: M3EThemeData.light(),
            child: MotionScope(child: child),
          ),
        ),
      ),
    );
  }

  testWidgets('SpringEntrance keeps the child semantic from the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SpringEntrance(
          child: Semantics(
            button: true,
            label: 'target',
            child: const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('target'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Let the bounded entrance timer fire before disposing the tree.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('SpringSwitcher replays when its key changes', (tester) async {
    await tester.pumpWidget(
      wrap(const SpringSwitcher(switchKey: 0, child: Text('page'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('page'), findsOneWidget);

    await tester.pumpWidget(
      wrap(const SpringSwitcher(switchKey: 1, child: Text('page'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('page'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('reduced motion renders both primitives without Opacity', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const Column(
          children: [
            SpringEntrance(child: Text('entrance')),
            SpringSwitcher(switchKey: 0, child: Text('switch')),
          ],
        ),
        reduced: true,
      ),
    );
    await tester.pump();

    expect(find.text('entrance'), findsOneWidget);
    expect(find.text('switch'), findsOneWidget);
    expect(find.byType(Opacity), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
