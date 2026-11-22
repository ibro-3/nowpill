import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/test_database.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App boots into the Today tab', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: NowPillApp()));
    // Let preferences load, then render a bounded number of frames (the M3E
    // springs and progress indicators can keep scheduling frames, so we avoid
    // pumpAndSettle here).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Today'), findsWidgets);
  });

  testWidgets('Bottom navigation switches tabs', (WidgetTester tester) async {
    final db = createTestDatabase();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const NowPillApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Tasks').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // The real Tasks screen shows its filter button group.
    expect(find.text('Upcoming'), findsWidgets);
    expect(find.text('Done'), findsWidgets);

    // Flush drift's stream-cache timers and close the DB inside the test zone.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  });
}
