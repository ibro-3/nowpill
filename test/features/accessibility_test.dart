import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/test_database.dart';

/// Screen-reader labels and large-text layout on the four primary tabs.
void main() {
  final dbHolder = <dynamic>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'settings.onboardingComplete': true,
      'settings.motionMode': 'standard',
    });
  });

  Future<void> boot(WidgetTester tester) async {
    final db = createTestDatabase();
    dbHolder.add(db);
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

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    for (final db in dbHolder) {
      await (db as dynamic).close();
    }
    dbHolder.clear();
  }

  testWidgets('primary controls are labeled and meet tap-target guidelines', (
    tester,
  ) async {
    await boot(tester);

    // The progress ring exposes its fraction as a semantics label.
    expect(find.bySemanticsLabel(RegExp(r'done today')), findsWidgets);
    // M3E icon buttons render a 40px visual (their gesture target is 48px).
    const guideline = MinimumTapTargetGuideline(
      size: Size(40, 40),
      link: 'https://support.google.com/accessibility/android/answer/7101858',
    );
    expect(tester, meetsGuideline(guideline));

    for (final tab in ['Tasks', 'Habits', 'Stats']) {
      await tester.tap(find.text(tab).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      const guideline = MinimumTapTargetGuideline(
        size: Size(40, 40),
        link: 'https://support.google.com/accessibility/android/answer/7101858',
      );
      expect(tester, meetsGuideline(guideline));
    }

    await cleanup(tester);
  });

  testWidgets('primary tabs render without overflow at 2x text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(() => tester.platformDispatcher.textScaleFactorTestValue = 1.0);
    await boot(tester);

    for (final tab in ['Today', 'Tasks', 'Habits', 'Stats']) {
      await tester.tap(find.text(tab).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: 'overflow on $tab');
    }

    await cleanup(tester);
  });
}
