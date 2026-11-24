import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/features/stats/stats_providers.dart';

import '../data/test_database.dart';

/// Regression: a vacation day is neutral, so habits are never "at risk" for
/// skipping it (v0.6.1).
void main() {
  late AppDatabase db;

  setUp(() async {
    db = createTestDatabase();
    final habits = HabitRepository(db);
    final id = await habits.create(
      name: 'Meditate',
      color: 0xFF2DD4A8,
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
    );
    await habits.checkIn(
      id,
      formatDate(DateTime.now().subtract(const Duration(days: 2))),
    );
    await habits.checkIn(
      id,
      formatDate(DateTime.now().subtract(const Duration(days: 1))),
    );
  });

  tearDown(() => db.close());

  Widget probe() {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: M3ETheme(data: M3EThemeData.light(), child: const _AtRiskProbe()),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('paused habits drop out of the at-risk list', (tester) async {
    await tester.pumpWidget(probe());
    await settle(tester);
    expect(find.text('at-risk: Meditate'), findsOneWidget);

    await HabitRepository(db)
        .createVacation(formatDate(DateTime.now()), formatDate(DateTime.now()));
    await settle(tester);
    expect(find.text('at-risk: none'), findsOneWidget);

    // Flush Drift's async stream cancellation before the database closes.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    });
  });
}

class _AtRiskProbe extends ConsumerWidget {
  const _AtRiskProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final atRisk = ref.watch(statsViewModelProvider).review.atRisk;
    return Scaffold(
      body: Text(
        atRisk.isEmpty ? 'at-risk: none' : 'at-risk: ${atRisk.join(',')}',
      ),
    );
  }
}
