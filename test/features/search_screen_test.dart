import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/chat_repository.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/data/repositories/tag_repository.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/features/search/search_screen.dart';

import '../data/test_database.dart';
import '../helpers/test_localizations.dart';

/// Search screen: live grouped results over tasks/habits/tags/notes, accent-
/// insensitive matching, subtask matches, and the empty/no-result states.
void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  Widget wrap() {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: M3ETheme(data: M3EThemeData.light(), child: const SearchScreen()),
      ),
    );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> type(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(EditableText).first, query);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  }

  testWidgets('empty query shows the hint, not results', (tester) async {
    await TaskRepository(db).create(title: 'Buy groceries');
    await pumpScreen(tester);
    expect(find.textContaining('Find anything'), findsOneWidget);
    expect(find.text('Buy groceries'), findsNothing);
    await cleanup(tester);
  });

  testWidgets('finds tasks, habits, and tags grouped', (tester) async {
    await TaskRepository(db).create(title: 'Buy groceries');
    await HabitRepository(db).create(name: 'Grocery run', color: 1);
    await TagRepository(db).create(name: 'groceries', color: 2);
    await pumpScreen(tester);
    await type(tester, 'grocer');

    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Habits'), findsOneWidget);
    expect(find.text('Tags'), findsOneWidget);
    expect(find.text('Buy groceries'), findsOneWidget);
    expect(find.text('Grocery run'), findsOneWidget);
    expect(find.text('#groceries'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('finds personal chat notes grouped with other results', (
    tester,
  ) async {
    await ChatRepository(db).create('Remember the groceries');
    await pumpScreen(tester);
    await type(tester, 'grocer');

    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Remember the groceries'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('accent-insensitive matching', (tester) async {
    await TaskRepository(db).create(title: 'Llamar mañana');
    await pumpScreen(tester);
    await type(tester, 'manana');
    expect(find.text('Llamar mañana'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('matches subtask titles and task notes', (tester) async {
    final tasks = TaskRepository(db);
    final id = await tasks.create(title: 'Big cleanup', notes: 'kitchen first');
    await tasks.addSubtask(id, 'Descale the kettle');
    await pumpScreen(tester);

    await type(tester, 'kettle');
    expect(find.text('Big cleanup'), findsOneWidget);

    await type(tester, 'kitchen');
    expect(find.text('Big cleanup'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('no results state', (tester) async {
    await TaskRepository(db).create(title: 'Buy groceries');
    await pumpScreen(tester);
    await type(tester, 'zzzznotfound');
    expect(find.byKey(const ValueKey('search-no-results')), findsOneWidget);
    await cleanup(tester);
  });
}
