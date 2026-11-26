import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/test_database.dart';

/// End-to-end widget coverage for the personal chat destination.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'settings.onboardingComplete': true,
      'settings.motionMode': 'standard',
    });
  });

  Future<void> boot(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const NowPillApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('To me').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> cleanup(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  }

  testWidgets('empty stream offers a single primary action', (tester) async {
    final db = createTestDatabase();
    await boot(tester, db);

    expect(find.text('A space for your thoughts'), findsOneWidget);
    expect(
      find.widgetWithText(M3EButton, 'Write your first note'),
      findsOneWidget,
    );
    expect(find.byType(M3ETextField), findsOneWidget);

    await cleanup(tester, db);
  });

  testWidgets('sending a note appends it and clearing disables Send', (
    tester,
  ) async {
    final db = createTestDatabase();
    await boot(tester, db);

    final sendButton = find
        .ancestor(
          of: find.bySemanticsLabel('Send note').last,
          matching: find.byType(M3EIconButton),
        )
        .last;
    expect(
      tester.widget<M3EIconButton>(sendButton).onPressed,
      isNull,
      reason: 'Send is disabled while the composer is empty',
    );
    await tester.enterText(find.byType(M3ETextField), '  remember the milk  ');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('remember the milk'), findsOneWidget);
    // The day heading shares its label with the Today nav destination.
    expect(find.text('Today'), findsNWidgets(2));
    expect(find.byType(M3ETextField), findsOneWidget);

    await cleanup(tester, db);
  });

  testWidgets('a note can be deleted after confirmation', (tester) async {
    final db = createTestDatabase();
    await boot(tester, db);

    await tester.enterText(find.byType(M3ETextField), 'delete me');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('delete me'), findsOneWidget);

    await tester.tap(find.byIcon(M3EIcons.delete_outlined).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Delete note?'), findsOneWidget);

    await tester.tap(find.widgetWithText(M3EButton, 'Delete').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('delete me'), findsNothing);

    await cleanup(tester, db);
  });

  testWidgets('chat renders without overflow at 2x text on a 320dp phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(() => tester.platformDispatcher.textScaleFactorTestValue = 1.0);

    final db = createTestDatabase();
    await boot(tester, db);
    expect(tester.takeException(), isNull, reason: 'chat overflowed');
    await cleanup(tester, db);
  });
}
