import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    await tester.pumpWidget(const ProviderScope(child: NowPillApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Tasks').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('To-dos with due dates, subtasks, tags, and recurrence.'),
      findsOneWidget,
    );
  });
}
