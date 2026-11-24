import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/features/habits/archived_habits_screen.dart';

import '../data/test_database.dart';
import '../helpers/test_localizations.dart';

/// v0.9: archived-habit manager — list, restore, and permanent delete.
void main() {
  late AppDatabase db;

  setUp(() {
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

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(const ArchivedHabitsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  }

  testWidgets('empty state shows when nothing is archived', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Archived habits'), findsOneWidget);
    expect(find.textContaining('No archived habits'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('lists archived habits with their archive date', (tester) async {
    final repo = HabitRepository(db);
    final id = await repo.create(name: 'Old habit', color: 0xFF2DD4A8);
    await repo.archive(id, at: DateTime(2026, 11, 20, 12));

    await pumpScreen(tester);
    expect(find.text('Old habit'), findsOneWidget);
    expect(find.text('Archived 2026-11-20'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('restore returns the habit to the active list', (tester) async {
    final repo = HabitRepository(db);
    final id = await repo.create(name: 'Walk', color: 0xFF4CB944);
    await repo.archive(id);

    await pumpScreen(tester);
    await tester.tap(find.byKey(ValueKey('restore-habit-$id')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final habit = await repo.getById(id);
    expect(habit!.archivedAt, isNull);
    expect(find.textContaining('No archived habits'), findsOneWidget);
    expect(find.text('Habit restored'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('delete asks for confirmation and removes history', (
    tester,
  ) async {
    final repo = HabitRepository(db);
    final id = await repo.create(name: 'Draft', color: 0xFF9B6DFF);
    await repo.checkIn(id, '2026-11-20');
    await repo.archive(id);

    await pumpScreen(tester);
    await tester.tap(find.byKey(ValueKey('delete-archived-habit-$id')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Delete habit?'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(M3EDialog),
        matching: find.text('Delete'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(await repo.getAll(), isEmpty);
    expect(await repo.getAllCheckins(), isEmpty);
    await cleanup(tester);
  });
}
