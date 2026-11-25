import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/core/motion/ambient_backdrop.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/test_database.dart';

/// The decorative backdrop is owned by the shell, not by individual screens:
/// one instance must stay mounted across every tab without doubling up.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'settings.onboardingComplete': true,
      'settings.motionMode': 'standard',
    });
  });

  testWidgets('exactly one backdrop stays mounted across all four tabs', (
    tester,
  ) async {
    final db = createTestDatabase();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const NowPillApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AmbientBackdrop), findsOneWidget);
    for (final tab in ['Tasks', 'Habits', 'Stats', 'Today']) {
      await tester.tap(find.text(tab).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byType(AmbientBackdrop),
        findsOneWidget,
        reason: 'backdrop count changed on $tab',
      );
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  });
}
