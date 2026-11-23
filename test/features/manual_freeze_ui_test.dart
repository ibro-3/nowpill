import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/features/habits/habit_detail_screen.dart';
import 'package:nowpill/features/habits/habit_providers.dart';
import 'package:nowpill/features/habits/widgets/token_wallet.dart';

import '../data/test_database.dart';
import '../helpers/test_localizations.dart';

/// Manual freeze mode UI: tapping a missed day offers Backfill / Freeze, and
/// tapping a frozen day refunds the token.
void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

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

  Future<void> pumpScreen(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(420, 1200);
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

  /// Seeds a manual-mode habit with a 7-day streak (1 token) and yesterday
  /// missed. Returns the habit id and yesterday's date.
  Future<(int, DateTime)> seedManualHabit() async {
    final repo = HabitRepository(db);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final id = await repo.create(
      name: 'Stretch',
      color: 0xFFEF5DA8,
      freezeMode: FreezeMode.manual,
    );
    await repo.update(
      (await repo.getById(
        id,
      ))!.copyWith(createdAt: today.subtract(const Duration(days: 12)).toUtc()),
    );
    // Days -8..-2 checked → 7-day streak earns 1 token. Yesterday (-1) missed.
    for (var i = 8; i >= 2; i--) {
      await repo.checkIn(id, formatDate(today.subtract(Duration(days: i))));
    }
    return (id, today.subtract(const Duration(days: 1)));
  }

  testWidgets('manual mode shows spend copy and a freeze choice on tap', (
    tester,
  ) async {
    final (id, yesterday) = await seedManualHabit();
    await pumpScreen(tester, HabitDetailScreen(habitId: id));
    await tester.pump(const Duration(milliseconds: 300));

    // Manual copy + a spendable token.
    expect(find.textContaining('Tap a missed day to spend'), findsOneWidget);
    expect(tester.widget<TokenWallet>(find.byType(TokenWallet)).tokens, 1);

    // Tap the missed day → choice dialog.
    final cellKey = ValueKey('heatmap-${formatDate(yesterday)}');
    await tester.ensureVisible(find.byKey(cellKey));
    await tester.pump();
    await tester.tap(find.byKey(cellKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('This day was missed'), findsOneWidget);
    expect(find.byKey(const ValueKey('day-freeze')), findsOneWidget);
    expect(find.byKey(const ValueKey('day-backfill')), findsOneWidget);

    // Choose Freeze → places an explicit freeze, spends the token.
    await tester.tap(find.byKey(const ValueKey('day-freeze')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final repo = HabitRepository(db);
    expect(await repo.getFreezes(id), hasLength(1));
    expect((await repo.getFreezes(id)).single.date, formatDate(yesterday));
    expect(tester.widget<TokenWallet>(find.byType(TokenWallet)).tokens, 0);
    final streak = ProviderScope.containerOf(
      tester.element(find.byType(HabitDetailScreen)),
    ).read(habitStreakProvider(id));
    expect(streak.frozenDates, contains(formatDate(yesterday)));
    await cleanup(tester);
  });

  testWidgets('tapping a frozen day removes the freeze and refunds', (
    tester,
  ) async {
    final (id, yesterday) = await seedManualHabit();
    final repo = HabitRepository(db);
    await repo.placeFreeze(id, formatDate(yesterday));

    await pumpScreen(tester, HabitDetailScreen(habitId: id));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<TokenWallet>(find.byType(TokenWallet)).tokens, 0);

    final cellKey = ValueKey('heatmap-${formatDate(yesterday)}');
    await tester.ensureVisible(find.byKey(cellKey));
    await tester.pump();
    await tester.tap(find.byKey(cellKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // No dialog — frozen day tap removes directly.
    expect(find.text('This day was missed'), findsNothing);
    expect(await repo.getFreezes(id), isEmpty);
    expect(tester.widget<TokenWallet>(find.byType(TokenWallet)).tokens, 1);
    await cleanup(tester);
  });

  testWidgets('backfill choice adds a real check-in instead of a freeze', (
    tester,
  ) async {
    final (id, yesterday) = await seedManualHabit();
    await pumpScreen(tester, HabitDetailScreen(habitId: id));
    await tester.pump(const Duration(milliseconds: 300));

    final cellKey = ValueKey('heatmap-${formatDate(yesterday)}');
    await tester.ensureVisible(find.byKey(cellKey));
    await tester.pump();
    await tester.tap(find.byKey(cellKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('day-backfill')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final repo = HabitRepository(db);
    expect(await repo.getFreezes(id), isEmpty);
    expect(
      (await repo.getCheckins(id)).any((c) => c.date == formatDate(yesterday)),
      isTrue,
    );
    await cleanup(tester);
  });
}
