import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/domain/recurrence_rule.dart';
import 'package:nowpill/features/habits/habit_detail_screen.dart';
import 'package:nowpill/features/habits/widgets/streak_odometer.dart';
import 'package:nowpill/features/habits/widgets/token_wallet.dart';
import 'package:nowpill/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end flows on a real (in-memory) database, driving the actual app UI.
///
/// Covers the three plan-mandated journeys:
///  1. habit → check-in → streak = 1
///  2. recurring task → complete → next occurrence spawned
///  3. backfill → freeze-token refund
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    // Standard (reduced) motion keeps the e2e deterministic: no perpetual bob
    // loops or spring overshoot, so the live binding advances cleanly. This
    // also exercises the reduce-motion code path end to end.
    SharedPreferences.setMockInitialValues({
      'settings.onboardingComplete': true,
      'settings.motionMode': 'standard',
    });
    db = AppDatabase.withExecutor(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const NowPillApp(),
      ),
    );
    // Bounded pumps: M3E springs never fully settle, so avoid pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpFor(WidgetTester tester, [int ms = 350]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
  }

  // Screenshots are only supported when driven by `flutter drive` (the
  // onScreenshot callback is registered there). Under `flutter test -d linux`
  // the captureScreenshot channel has no implementation, so skip gracefully.
  Future<void> screenshot(WidgetTester tester, String name) async {
    try {
      await binding.takeScreenshot(name);
    } catch (_) {
      // No screenshot handler on this runner — assertions still ran.
    }
  }

  testWidgets('habit check-in drives the streak to 1', (tester) async {
    final habits = HabitRepository(db);
    await habits.create(name: 'Meditate', color: 0xFF2DD4A8);

    await boot(tester);

    // Navigate to the Habits tab.
    await tester.tap(find.text('Habits').last);
    await pumpFor(tester, 400);

    expect(find.text('Meditate'), findsOneWidget);
    // Streak starts at 0.
    expect(
      tester.widget<StreakOdometer>(find.byType(StreakOdometer).first).value,
      0,
    );

    // One-tap check-in via the signature pill.
    await tester.tap(find.bySemanticsLabel('Check in Meditate'));
    await pumpFor(tester, 500);

    // The streak odometer rolls to 1 and the pill flips to undo.
    expect(
      tester.widget<StreakOdometer>(find.byType(StreakOdometer).first).value,
      1,
    );
    expect(find.bySemanticsLabel('Undo check-in for Meditate'), findsOneWidget);

    // Persisted to the database.
    final checkins = await habits.getAllCheckins();
    expect(checkins, hasLength(1));
    expect(checkins.single.date, formatDate(DateTime.now()));

    // Undo returns the streak to 0.
    await tester.tap(find.bySemanticsLabel('Undo check-in for Meditate'));
    await pumpFor(tester, 500);
    expect(
      tester.widget<StreakOdometer>(find.byType(StreakOdometer).first).value,
      0,
    );
    expect(await habits.getAllCheckins(), isEmpty);

    await screenshot(tester, 'habit_check_in_streak');
  });

  testWidgets('completing a recurring task spawns the next occurrence', (
    tester,
  ) async {
    final tasks = TaskRepository(db);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await tasks.create(
      title: 'Water plants',
      dueAt: today,
      recurrence: const RecurrenceRule(unit: RecurrenceUnit.day),
    );

    await boot(tester);

    await tester.tap(find.text('Tasks').last);
    await pumpFor(tester, 400);

    expect(find.text('Water plants'), findsOneWidget);

    // Complete it via the check pill.
    await tester.tap(find.bySemanticsLabel('Mark complete'));
    await pumpFor(tester, 500);

    // The completed row is kept and a new occurrence is spawned for tomorrow.
    final all = await tasks.getAll();
    expect(all, hasLength(2));
    final completed = all.firstWhere((t) => t.completedAt != null);
    final spawned = all.firstWhere((t) => t.completedAt == null);
    expect(completed.title, 'Water plants');
    expect(spawned.title, 'Water plants');
    expect(
      formatDate(spawned.dueAt!.toLocal()),
      formatDate(today.add(const Duration(days: 1))),
    );
    expect(
      spawned.recurrenceRule,
      const RecurrenceRule(unit: RecurrenceUnit.day),
    );

    // The open spawned task is shown under the Upcoming filter.
    await tester.tap(find.text('Upcoming').first);
    await pumpFor(tester, 400);
    expect(find.text('Water plants'), findsOneWidget);

    await screenshot(tester, 'recurring_task_spawn');
  });

  testWidgets('backfilling a frozen day refunds the freeze token', (
    tester,
  ) async {
    final habits = HabitRepository(db);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Build a history that earns a token then spends it on a missed day:
    // days -10..-4 checked (7-day streak earns 1 token at day -4), day -3
    // missed (token auto-consumed → frozen), days -2..0 checked.
    final id = await habits.create(name: 'Read', color: 0xFF5B8DEF);
    final created = today.subtract(const Duration(days: 12));
    await habits.update(
      (await habits.getById(id))!.copyWith(createdAt: created.toUtc()),
    );
    for (var i = 10; i >= 4; i--) {
      await habits.checkIn(id, formatDate(today.subtract(Duration(days: i))));
    }
    // day -3 intentionally left unchecked → freeze bridges it.
    for (var i = 2; i >= 0; i--) {
      await habits.checkIn(id, formatDate(today.subtract(Duration(days: i))));
    }

    await boot(tester);
    await tester.tap(find.text('Habits').last);
    await pumpFor(tester, 400);

    // Open the habit detail.
    await tester.tap(find.text('Read'));
    await pumpFor(tester, 600);

    expect(find.text('Current streak'), findsOneWidget);
    // The missed day consumed the only token → wallet empty, streak alive.
    expect(tester.widget<TokenWallet>(find.byType(TokenWallet)).tokens, 0);

    // The frozen day renders a ❄ cell.
    final frozenDay = today.subtract(const Duration(days: 3));
    final frozenKey = ValueKey('heatmap-${formatDate(frozenDay)}');
    expect(find.byKey(frozenKey), findsOneWidget);

    // v0.9's insights card makes the detail page taller, so bring the cell
    // into view before tapping it.
    await tester.scrollUntilVisible(
      find.byKey(frozenKey),
      200,
      scrollable: find
          .ancestor(
            of: find.byKey(frozenKey),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await pumpFor(tester, 200);

    // Backfill the frozen day by tapping its heatmap cell.
    await tester.tap(find.byKey(frozenKey));
    await pumpFor(tester, 600);

    // The check-in now exists, so replay no longer needs the freeze: the token
    // is refunded back into the wallet.
    final checkins = await habits.getCheckins(id);
    expect(checkins.any((c) => c.date == formatDate(frozenDay)), isTrue);

    // The wallet was disposed while scrolled down; bring it back into view.
    await tester.scrollUntilVisible(
      find.byType(TokenWallet),
      -200,
      scrollable: find
          .descendant(
            of: find.byType(HabitDetailScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await pumpFor(tester, 200);
    expect(tester.widget<TokenWallet>(find.byType(TokenWallet)).tokens, 1);

    await screenshot(tester, 'backfill_freeze_refund');
  });
}
