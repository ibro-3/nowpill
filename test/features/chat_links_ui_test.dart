import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/core/platform/link_launcher.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/chat_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/test_database.dart';

class _FakeLauncher extends LinkLauncher {
  _FakeLauncher({this.result = true});

  final bool result;
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return result;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'settings.onboardingComplete': true,
      'settings.motionMode': 'standard',
    });
  });

  Future<void> boot(
    WidgetTester tester,
    AppDatabase db,
    LinkLauncher launcher,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          linkLauncherProvider.overrideWithValue(launcher),
        ],
        child: const NowPillApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('To me').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> cleanup(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  }

  Finder linkFinder() => find.byWidgetPredicate(
    (w) =>
        w is RichText && w.text.toPlainText().contains('https://example.com/a'),
  );

  TextSpan linkSpan(WidgetTester tester) {
    final rich = linkFinder();
    expect(rich, findsOneWidget);
    TextSpan? found;
    void walk(InlineSpan span) {
      if (span is! TextSpan) return;
      if (span.recognizer != null) {
        found = span;
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }

    walk(tester.widget<RichText>(rich).text);
    expect(found, isNotNull, reason: 'the URL should be a tappable span');
    return found!;
  }

  testWidgets('URLs render as underlined links and open externally', (
    tester,
  ) async {
    final db = createTestDatabase();
    await ChatRepository(db).create('See https://example.com/a now');
    final launcher = _FakeLauncher();
    await boot(tester, db, launcher);

    final span = linkSpan(tester);
    expect(
      span.style?.decoration,
      TextDecoration.underline,
      reason: 'M3 links are primary and underlined',
    );
    expect(span.style?.color, isNotNull);
    final recognizer = span.recognizer! as TapGestureRecognizer;
    recognizer.onTap?.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(launcher.opened, [Uri.parse('https://example.com/a')]);
    await cleanup(tester, db);
  });

  testWidgets('a failed launch shows a snackbar', (tester) async {
    final db = createTestDatabase();
    await ChatRepository(db).create('https://example.com/a');
    await boot(tester, db, _FakeLauncher(result: false));

    final span = linkSpan(tester);
    (span.recognizer! as TapGestureRecognizer).onTap?.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Could not open that link.'), findsOneWidget);
    await cleanup(tester, db);
  });
}
