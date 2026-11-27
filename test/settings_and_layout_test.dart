import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/test_database.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'settings.onboardingComplete': true,
    });
  });

  /// Boots the app with an isolated in-memory DB and registers teardown that
  /// flushes drift's stream timers and closes it inside the test zone.
  Future<void> boot(WidgetTester tester) async {
    final db = createTestDatabase();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await db.close();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const NowPillApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('Compact layout shows a bottom navigation bar', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await boot(tester);

    // All four destinations are present in the bottom bar.
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Tasks'), findsWidgets);
    expect(find.text('Habits'), findsWidgets);
    expect(find.text('Stats'), findsWidgets);
  });

  testWidgets('Bottom bar includes the system gesture inset', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    // Gesture-navigation devices reserve a bottom inset. The bar must grow to
    // include it; clamping it to a fixed height used to overflow by exactly the
    // inset and paint over the screen body.
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.reset);

    await boot(tester);

    expect(tester.takeException(), isNull);
    // Baseline content (80) + the 24px gesture inset.
    expect(tester.getSize(find.byType(M3ENavigationBar)).height, 104);
  });

  testWidgets('Settings screen opens and shows motion + theme controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await boot(tester);

    await tester.tap(find.bySemanticsLabel('Settings').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Motion'), findsOneWidget);
    // Connected button groups build an offstage measurement copy of each
    // label; the first copy is the visible one.
    expect(find.text('Expressive').first, findsOneWidget);
    expect(find.text('Standard').first, findsOneWidget);
    expect(find.text('Dynamic color'), findsOneWidget);
  });

  testWidgets('Toggling motion to Standard persists the choice', (
    tester,
  ) async {
    // Wide viewport: this test checks persistence, not label fitting. Flutter
    // tests use the wide Ahem font, which pushes the motion group's labels into
    // its overflow menu at phone width.
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await boot(tester);

    await tester.tap(find.bySemanticsLabel('Settings').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Standard').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.motionMode'), 'standard');
  });

  Future<void> openSettings(WidgetTester tester, String semanticLabel) async {
    await tester.tap(find.bySemanticsLabel(semanticLabel).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Settings is a lazy ListView: walk down a page at a time until the finder
  /// has a match, so offscreen cards aren't false failures.
  Future<void> scrollUntilFound(WidgetTester tester, Finder finder) async {
    for (var step = 0; step < 30 && finder.evaluate().isEmpty; step++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsWidgets);
  }

  /// A connected group that spans its surface splits into equal segments and
  /// ellipsizes long labels; every Settings group must use the trailing menu.
  void expectOverflowMenuGroups(WidgetTester tester) {
    final groups = find.byType(M3EButtonGroup).evaluate();
    expect(groups, isNotEmpty);
    for (final element in groups) {
      expect(
        (element.widget as M3EButtonGroup).overflow,
        M3EButtonGroupOverflow.menu,
        reason: 'connected groups must move long labels into a trailing menu',
      );
    }
  }

  Future<void> expectWrappedActionButtons(
    WidgetTester tester,
    String exportLabel,
  ) async {
    await scrollUntilFound(tester, find.text(exportLabel));
    expect(
      find.ancestor(
        of: find.text(exportLabel).first,
        matching: find.byType(Wrap),
      ),
      findsWidgets,
      reason: 'paired actions size to their labels instead of equal halves',
    );
  }

  testWidgets('Settings uses readable buttons on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await boot(tester);
    await openSettings(tester, 'Settings');

    expectOverflowMenuGroups(tester);
    await expectWrappedActionButtons(tester, 'Export');
    await scrollUntilFound(tester, find.text('Weekly'));
    expectOverflowMenuGroups(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings uses readable buttons in Spanish at 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({
      'settings.onboardingComplete': true,
      'settings.localeCode': 'es',
    });

    await boot(tester);
    await openSettings(tester, 'Ajustes');

    expectOverflowMenuGroups(tester);
    await expectWrappedActionButtons(tester, 'Exportar');
    await scrollUntilFound(tester, find.text('Semanalmente'));
    expectOverflowMenuGroups(tester);
    expect(tester.takeException(), isNull);
  });
}
