import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/export/export_service.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/data/sync/sync_coordinator.dart';
import 'package:nowpill/data/sync/sync_folder.dart';
import 'package:nowpill/data/sync/sync_providers.dart';
import 'package:nowpill/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_localizations.dart';

/// Settings sync section: enable toggle, folder label, live status, and the
/// manual Sync now action — over a real temp-dir folder.
void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'settings.onboardingComplete': true,
    });
    db = AppDatabase.withExecutor(NativeDatabase.memory(), deviceId: 'testDev');
  });

  tearDown(() async {
    await db.close();
  });

  void useLinux(WidgetTester tester) {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  }

  Widget wrap({SyncCoordinator? coordinator}) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        if (coordinator != null)
          syncCoordinatorProvider.overrideWithValue(coordinator),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: M3ETheme(
          data: M3EThemeData.light(),
          child: const SettingsScreen(),
        ),
      ),
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    SyncCoordinator? coordinator,
  }) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(coordinator: coordinator));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Flush the async Drift stream cancellation from the vacation provider.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    });
  }

  testWidgets('sync section shows idle state with no folder', (tester) async {
    useLinux(tester);
    await pumpScreen(tester);

    expect(find.text('Sync'), findsOneWidget);
    expect(find.text('Folder sync'), findsOneWidget);
    expect(find.text('No folder chosen'), findsOneWidget);
    expect(find.text('Choose folder'), findsOneWidget);
    expect(find.text('Sync is off.'), findsOneWidget);
    // Sync now is disabled without a folder.
    final syncNow = tester.widget<M3EButton>(
      find
          .ancestor(of: find.text('Sync now'), matching: find.byType(M3EButton))
          .first,
    );
    expect(syncNow.onPressed, isNull);
  });

  testWidgets('desktop shows the enable toggle and device id', (tester) async {
    useLinux(tester);
    await pumpScreen(tester);
    expect(find.text('Enable sync'), findsOneWidget);
    expect(find.textContaining('This device:'), findsOneWidget);
  });

  testWidgets('persisted folder + enabled shows status and runs sync', (
    tester,
  ) async {
    useLinux(tester);
    // Real file IO only completes in the real async zone under the binding.
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('nowpill_sync_ui_'),
    );
    addTearDown(() async {
      await tester.runAsync(() => dir!.delete(recursive: true));
    });
    SharedPreferences.setMockInitialValues({
      'settings.onboardingComplete': true,
      'flutter.settings.syncEnabled': true,
      'flutter.settings.syncFolderHandle': dir!.path,
    });
    await tester.runAsync(
      () => HabitRepository(db).create(name: 'Read', color: 1),
    );

    // A fresh container so the coordinator override and the status notifier
    // live in the same scope (overrides can't be added to a pumped scope).
    late final ProviderContainer container;
    final sync = SyncCoordinator(
      export: ExportService(db),
      deviceId: 'testDev',
      folder: IoSyncFolder(dir.path),
      pollInterval: const Duration(hours: 1),
      onStateChanged: (s) => container.read(syncStateProvider.notifier).set(s),
    );
    addTearDown(sync.dispose);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        syncCoordinatorProvider.overrideWithValue(sync),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: M3ETheme(
            data: M3EThemeData.light(),
            child: const SettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Folder label = directory basename; toggle on.
    expect(find.text(dir.path.split('/').last), findsOneWidget);
    expect(find.text('Change folder'), findsOneWidget);

    // Manual sync writes the envelope and reports ok.
    await tester.tap(find.text('Sync now'));
    await tester.runAsync(() async {
      await sync.syncNow();
      // Let the queued follow-up cycle (from the tap) drain too.
      await Future<void>.delayed(const Duration(milliseconds: 700));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(File('${dir.path}/nowpill-sync-testDev.json').existsSync(), isTrue);
    expect(sync.state.status, SyncStatus.ok);
    expect(find.textContaining('Up to date'), findsOneWidget);
  });
}
