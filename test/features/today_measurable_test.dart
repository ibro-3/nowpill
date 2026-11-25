import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/core/motion/app_motion.dart';
import 'package:nowpill/core/motion/motion_scheme_provider.dart';
import 'package:nowpill/core/widgets/spring_progress.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/features/today/today_screen.dart';

import '../data/test_database.dart';
import '../helpers/test_localizations.dart';

/// Measurable habits on the Today dashboard: the stepper logs partial amounts
/// (UI-only progress) and only 100% of the goal counts as done.
void main() {
  late AppDatabase db;
  late HabitRepository habits;

  setUp(() {
    db = createTestDatabase();
    habits = HabitRepository(db);
  });

  Widget wrap() {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: M3ETheme(data: M3EThemeData.light(), child: const TodayScreen()),
      ),
    );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  }

  testWidgets('stepper logs partial progress without completing the day', (
    tester,
  ) async {
    final id = await habits.create(
      name: 'Water',
      color: 0xFF00B4D8,
      targetAmount: 8,
    );
    await pumpScreen(tester);

    expect(find.text('0 / 8'), findsOneWidget);

    // Log 3 units via the + stepper.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(ValueKey('amount-plus-$id')));
      await settle(tester);
    }
    expect(find.text('3 / 8'), findsOneWidget);
    // Partial: the day is NOT done (no strikethrough / goal pill unchecked).
    final checkins = await habits.getCheckins(id);
    expect(checkins.single.amount, 3);

    // Minus removes one.
    await tester.tap(find.byKey(ValueKey('amount-minus-$id')));
    await settle(tester);
    expect(find.text('2 / 8'), findsOneWidget);

    await cleanup(tester);
  });

  testWidgets('reaching the goal completes the day; goal pill toggles', (
    tester,
  ) async {
    final id = await habits.create(
      name: 'Water',
      color: 0xFF00B4D8,
      targetAmount: 3,
    );
    await pumpScreen(tester);

    // Complete via the goal pill (sets the full amount).
    await tester.tap(find.bySemanticsLabel('Complete the goal for Water'));
    await settle(tester);
    expect(find.text('3 / 3'), findsOneWidget);
    expect((await habits.getCheckins(id)).single.amount, 3);

    // The pill now clears the goal.
    await tester.tap(find.bySemanticsLabel('Clear the goal for Water'));
    await settle(tester);
    expect(await habits.getCheckins(id), isEmpty);

    await cleanup(tester);
  });

  testWidgets('minus to zero clears the check-in', (tester) async {
    final id = await habits.create(
      name: 'Water',
      color: 0xFF00B4D8,
      targetAmount: 8,
    );
    await habits.checkIn(id, formatDate(DateTime.now()), amount: 1);
    await pumpScreen(tester);
    expect(find.text('1 / 8'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('amount-minus-$id')));
    await settle(tester);
    expect(await habits.getCheckins(id), isEmpty);

    await cleanup(tester);
  });

  testWidgets('stepper controls meet the 48x48dp touch target', (tester) async {
    final id = await habits.create(
      name: 'Water',
      color: 0xFF00B4D8,
      targetAmount: 8,
    );
    await pumpScreen(tester);

    for (final key in ['amount-minus-$id', 'amount-plus-$id']) {
      final box = tester.renderObject<RenderBox>(find.byKey(ValueKey(key)));
      expect(box.size.width, greaterThanOrEqualTo(48), reason: key);
      expect(box.size.height, greaterThanOrEqualTo(48), reason: key);
    }

    await cleanup(tester);
  });

  testWidgets('measurable amount is a spring-animated M3E circular ring', (
    tester,
  ) async {
    final id = await habits.create(
      name: 'Water',
      color: 0xFF00B4D8,
      targetAmount: 4,
    );
    await habits.checkIn(id, formatDate(DateTime.now()), amount: 2);
    await pumpScreen(tester);

    final wrapper = tester.widget<SpringWavyProgressBar>(
      find.byType(SpringWavyProgressBar),
    );
    expect(wrapper.value, 0.5);
    expect(wrapper.circular, isTrue);
    expect(wrapper.semanticsLabel, '2 / 4');
    expect(find.byKey(const Key('spring-progress-circular')), findsOneWidget);
    expect(find.byKey(const Key('spring-progress-wavy')), findsNothing);

    // The fill springs from zero to the target; the flat ring has no waveform.
    await tester.pump(const Duration(milliseconds: 2000));
    final bar = tester.widget<M3EProgressIndicator>(
      find.byKey(const Key('spring-progress-circular')),
    );
    expect(bar.value, closeTo(0.5, 0.01));

    await cleanup(tester);
  });

  testWidgets('reduced motion renders a static measurable ring', (
    tester,
  ) async {
    final id = await habits.create(
      name: 'Water',
      color: 0xFF00B4D8,
      targetAmount: 4,
    );
    await habits.checkIn(id, formatDate(DateTime.now()), amount: 2);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          motionTokensProvider.overrideWithValue(MotionTokens.standard),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: M3ETheme(
            data: M3EThemeData.light(),
            child: const MotionScope(child: TodayScreen()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('spring-progress-circular')), findsOneWidget);
    expect(find.byKey(const Key('spring-progress-wavy')), findsNothing);
    final bar = tester.widget<M3EProgressIndicator>(
      find.byKey(const Key('spring-progress-circular')),
    );
    expect(bar.value, 0.5);

    await cleanup(tester);
  });
}
