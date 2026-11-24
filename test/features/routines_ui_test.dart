import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/features/habits/habits_screen.dart';
import 'package:nowpill/features/settings/settings_screen.dart';
import 'package:nowpill/features/settings/vacation_editor_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/test_database.dart';
import '../helpers/test_localizations.dart';

/// v0.7 UI: routine grouping/filtering, routine management, and the scoped
/// vacation editor.
void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'settings.onboardingComplete': true,
    });
    db = createTestDatabase();
  });

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: M3ETheme(data: M3EThemeData.light(), child: child),
      ),
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(420, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(child));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
  }

  Future<void> cleanup(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await db.close();
    });
  }

  testWidgets('habits group by routine and filter chips narrow the list', (
    tester,
  ) async {
    final repo = HabitRepository(db);
    final morning = await repo.createRoutine('Morning', 0xFF2DD4A8);
    final evening = await repo.createRoutine('Evening', 0xFFFFB454);
    final water = await repo.create(name: 'Water', color: 1);
    final read = await repo.create(name: 'Read', color: 2);
    await repo.setHabitRoutine(water, morning);
    await repo.setHabitRoutine(read, evening);

    await pumpScreen(tester, const HabitsScreen(), size: const Size(420, 1200));
    expect(find.text('Morning'), findsNWidgets(2));
    expect(find.text('Evening'), findsNWidgets(2));
    expect(find.text('Water'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);

    await tester.tap(find.text('Evening').first);
    await settle(tester);
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Water'), findsNothing);

    await cleanup(tester);
  });

  testWidgets('settings can create a routine', (tester) async {
    await pumpScreen(
      tester,
      const SettingsScreen(),
      size: const Size(420, 1600),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('routine-add')),
      300,
    );
    await tester.tap(find.byKey(const ValueKey('routine-add')));
    await settle(tester);
    await tester.enterText(find.byType(M3ETextField).first, 'Workout');
    await tester.tap(find.byKey(const ValueKey('routine-save')));
    await settle(tester);

    expect(
      (await HabitRepository(db).getAllRoutines()).map((r) => r.name),
      contains('Workout'),
    );

    await cleanup(tester);
  });

  testWidgets('vacation editor can scope a pause to one habit', (tester) async {
    final repo = HabitRepository(db);
    final habitId = await repo.create(name: 'Gym', color: 1);
    final habit = (await repo.getById(habitId))!;

    await pumpScreen(
      tester,
      const VacationEditorForm(),
      size: const Size(420, 1800),
    );

    await tester.tap(find.byKey(const ValueKey('vacation-all-habits')));
    await settle(tester);
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('vacation-scope-h-${habit.uuid}')),
      400,
    );
    await tester.tap(find.byKey(ValueKey('vacation-scope-h-${habit.uuid}')));
    await tester.tap(find.byKey(const ValueKey('vacation-editor-save')));
    await settle(tester);

    final period = (await repo.getAllVacationPeriods()).single;
    expect(period.allHabits, isFalse);
    final scopes = await repo.getVacationScopes();
    expect(scopes, hasLength(1));
    expect(scopes.single.targetKind, VacationTargetKind.habit);
    expect(scopes.single.targetUuid, habit.uuid);

    await cleanup(tester);
  });
}
