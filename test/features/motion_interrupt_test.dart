import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/core/motion/motion_scheme_provider.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/features/tasks/widgets/check_pill.dart';
import 'package:nowpill/features/today/today_screen.dart';

import '../data/test_database.dart';
import '../helpers/test_localizations.dart';

/// Motion polish (Phase 10): interrupt/retarget sanity. Springs must survive
/// rapid taps mid-animation and motion-scheme switches mid-flight without
/// stacking animations, leaking controllers, or landing in a wrong state.
void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  Widget wrap(Widget child, {bool osReduced = false}) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
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

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  }

  testWidgets('rapid CheckPill taps retarget the spring and settle correctly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var checked = false;
    await tester.pumpWidget(
      wrap(
        StatefulBuilder(
          builder: (context, setState) => Center(
            child: CheckPill(
              checked: checked,
              semanticLabel: 'rapid-pill',
              onChanged: (v) => setState(() => checked = v),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 7 rapid taps: each lands while the previous morph is still in flight.
    for (var i = 0; i < 7; i++) {
      await tester.tap(find.bySemanticsLabel('rapid-pill'));
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(checked, isTrue); // odd number of taps

    // Let the final spring settle; no exceptions, no stacked tickers.
    await tester.pump(const Duration(milliseconds: 900));
    expect(checked, isTrue);
    expect(tester.takeException(), isNull);
    await cleanup(tester);
  });

  testWidgets('motion scheme switch mid-animation retargets safely', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var checked = false;
    Widget tree({required bool reduced}) => wrap(
      StatefulBuilder(
        builder: (context, setState) => Center(
          child: CheckPill(
            checked: checked,
            semanticLabel: 'scheme-pill',
            onChanged: (v) => setState(() => checked = v),
          ),
        ),
      ),
      osReduced: reduced,
    );

    await tester.pumpWidget(tree(reduced: false));
    await tester.pump();

    // Start the expressive morph, then flip OS reduce-motion mid-flight.
    await tester.tap(find.bySemanticsLabel('scheme-pill'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(tree(reduced: true));
    await tester.pump(const Duration(milliseconds: 60));

    // And back to expressive while still animating.
    await tester.pumpWidget(tree(reduced: false));
    await tester.pump(const Duration(milliseconds: 900));

    expect(checked, isTrue);
    expect(tester.takeException(), isNull);
    await cleanup(tester);
  });

  testWidgets('rapid habit check-in taps leave a consistent database', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final habits = HabitRepository(db);
    await habits.create(name: 'Meditate', color: 0xFF2DD4A8);

    await tester.pumpWidget(wrap(const TodayScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 6 rapid toggles (even → unchecked). Each tap fires while the pill morph
    // and streak odometer are still animating; the unique(habitId,date)
    // constraint and idempotent check-in must keep the DB consistent.
    for (var i = 0; i < 6; i++) {
      final label = i.isEven
          ? 'Check in Meditate'
          : 'Undo check-in for Meditate';
      await tester.tap(find.bySemanticsLabel(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.pump(const Duration(milliseconds: 600));

    expect(await habits.getAllCheckins(), isEmpty);
    expect(find.bySemanticsLabel('Check in Meditate'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await cleanup(tester);
  });
}
