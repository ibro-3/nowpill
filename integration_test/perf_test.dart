import 'dart:convert';

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
import 'package:nowpill/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Motion polish (Phase 10): 60fps frame-budget checks with real engine frame
/// timings via [IntegrationTestWidgetsFlutterBinding.watchPerformance].
///
/// Runs with the expressive motion scheme so springs actually animate. Budgets
/// are deliberately generous for debug builds on emulators/software rendering:
/// the goal is catching per-frame *work* regressions (jank, runaway rebuilds),
/// not pixel-perfect release performance. Release-mode numbers come from
/// `flutter drive --profile` on real hardware.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'settings.onboardingComplete': true,
      'settings.motionMode': 'expressive',
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Pumps ~[ms] of animation in 16ms slices so real frames are produced while
  /// the spring runs (a single big pump would skip the intermediate frames).
  Future<void> animateFor(WidgetTester tester, int ms) async {
    for (var t = 0; t < ms; t += 16) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  void reportBudget(String key, double budgetMs) {
    final summary = binding.reportData?[key];
    // ignore: avoid_print
    print('NOWPILL_PERF $key ${jsonEncode(summary)}');
    if (summary == null) return; // platform did not report timings
    final map = summary as Map<String, dynamic>;
    final p90Build = (map['90th_percentile_frame_build_time_millis'] as num?)
        ?.toDouble();
    final p90Raster =
        (map['90th_percentile_frame_rasterizer_time_millis'] as num?)
            ?.toDouble();
    if (p90Build != null) {
      expect(p90Build, lessThan(budgetMs), reason: '90th percentile build');
    }
    if (p90Raster != null) {
      expect(p90Raster, lessThan(budgetMs), reason: '90th percentile raster');
    }
  }

  testWidgets('all-done celebration stays within the frame budget', (
    tester,
  ) async {
    final habits = HabitRepository(db);
    final tasks = TaskRepository(db);
    final today = DateTime.now();
    await habits.create(name: 'Meditate', color: 0xFF2DD4A8);
    await tasks.create(
      title: 'Inbox zero',
      dueAt: DateTime(today.year, today.month, today.day),
    );

    await boot(tester);

    await binding.watchPerformance(() async {
      // Complete everything: triggers ring overshoot + banner + confetti.
      await tester.tap(find.bySemanticsLabel('Check in Meditate'));
      await animateFor(tester, 300);
      await tester.tap(find.bySemanticsLabel('Mark complete'));
      // Confetti runs on the ~2.5s celebration spring.
      await animateFor(tester, 2600);
    }, reportKey: 'celebration_perf');

    reportBudget('celebration_perf', 32);
  });

  testWidgets('heatmap staggered entrance stays within the frame budget', (
    tester,
  ) async {
    final habits = HabitRepository(db);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final id = await habits.create(name: 'Read', color: 0xFF5B8DEF);
    await habits.update(
      (await habits.getById(
        id,
      ))!.copyWith(createdAt: today.subtract(const Duration(days: 40)).toUtc()),
    );
    for (var i = 30; i >= 0; i--) {
      await habits.checkIn(id, formatDate(today.subtract(Duration(days: i))));
    }

    await boot(tester);
    await tester.tap(find.text('Habits').last);
    await animateFor(tester, 400);

    await binding.watchPerformance(() async {
      await tester.tap(find.text('Read'));
      // Detail route transition + 31-cell staggered heatmap pop-in.
      await animateFor(tester, 1600);
    }, reportKey: 'heatmap_perf');

    reportBudget('heatmap_perf', 32);
  });
}
