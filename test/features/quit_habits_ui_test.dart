import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/domain/vacation.dart' as domain_vacation;
import 'package:nowpill/features/habits/habit_detail_screen.dart';
import 'package:nowpill/features/habits/habits_screen.dart';
import 'package:nowpill/features/today/today_screen.dart';

import '../data/test_database.dart';
import '../helpers/test_localizations.dart';

/// v0.6 UI: quitting a habit, logging a relapse, and the vacation banner.
void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: M3ETheme(data: M3EThemeData.light(), child: child),
      ),
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget child, {
    double height = 900,
  }) async {
    tester.view.physicalSize = Size(420, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(child));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  }

  testWidgets('the editor can create a quit habit with a backdated quit date', (
    tester,
  ) async {
    await pumpScreen(tester, const HabitsScreen(), height: 2400);

    await tester.tap(find.bySemanticsLabel('New habit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Habit type'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.tap(find.text('Quit a habit'));
    await tester.pump();
    expect(find.text('Quit date'), findsOneWidget);
    expect(find.text('Daily goal'), findsNothing);

    await tester.enterText(find.byType(M3ETextField).first, 'Smoking');
    await tester.tap(find.text('Add habit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final habits = await db.select(db.habits).get();
    expect(habits, hasLength(1));
    expect(habits.single.kind, HabitKind.quit);
    expect(habits.single.name, 'Smoking');

    await cleanup(tester);
  });

  testWidgets('detail shows days clean and logs a relapse through the dialog', (
    tester,
  ) async {
    final repo = HabitRepository(db);
    final id = await repo.create(
      name: 'Smoking',
      color: 0xFF2DD4A8,
      kind: HabitKind.quit,
      createdAt: DateTime.now().subtract(const Duration(days: 4)),
    );

    await pumpScreen(tester, HabitDetailScreen(habitId: id), height: 1400);
    expect(find.text('5 days clean'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('log-relapse')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Log a relapse?'), findsOneWidget);

    await tester.enterText(find.byType(M3ETextField).last, 'after dinner');
    await tester.tap(find.byKey(const ValueKey('relapse-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final relapses = await repo.getRelapses(id);
    expect(relapses, hasLength(1));
    expect(relapses.single.date, formatDate(DateTime.now()));
    expect(relapses.single.note, 'after dinner');
    expect(find.text('0 days clean'), findsWidgets);

    await cleanup(tester);
  });

  testWidgets('Today shows the quit section and the vacation banner', (
    tester,
  ) async {
    final repo = HabitRepository(db);
    await repo.create(
      name: 'Smoking',
      color: 0xFFFF6B5E,
      kind: HabitKind.quit,
      createdAt: DateTime.now(),
    );
    final gymId = await repo.create(name: 'Gym', color: 0xFF2DD4A8);
    final gym = (await repo.getById(gymId))!;
    await repo.createVacation(
      formatDate(DateTime.now()),
      formatDate(DateTime.now().add(const Duration(days: 2))),
      allHabits: false,
    );
    final period = (await repo.getAllVacationPeriods()).single;
    await repo.replaceVacationScopes(period.uuid, [
      domain_vacation.VacationScope(
        periodUuid: period.uuid,
        targetKind: VacationTargetKind.habit,
        targetUuid: gym.uuid,
      ),
    ]);

    await pumpScreen(tester, const TodayScreen(), height: 1400);

    expect(find.text('Quit a habit'), findsOneWidget);
    expect(find.text('Pausing Gym'), findsOneWidget);
    expect(find.text('Paused for vacation (1)'), findsOneWidget);

    await cleanup(tester);
  });
}
