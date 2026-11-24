import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/data/backup/auto_backup_service.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/export/export_service.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_localizations.dart';

/// Settings automatic-backup list: snapshots render newest-first and restore
/// goes through the replace-all confirm flow.
void main() {
  late AppDatabase db;
  late Directory dir;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'settings.onboardingComplete': true,
    });
    db = AppDatabase.withExecutor(NativeDatabase.memory(), deviceId: 'devA');
    dir = Directory.systemTemp.createTempSync('nowpill_autobackup_ui_');
  });
  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget wrap() {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        autoBackupServiceProvider.overrideWith(
          (ref) async => AutoBackupService(
            export: ExportService(db),
            directoryPath: dir.path,
          ),
        ),
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

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The vacation stream provider cancels its Drift subscription
    // asynchronously; flush the disposal before the test ends.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    });
  }

  testWidgets('empty state when no snapshots exist', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Automatic backups'), findsOneWidget);
    expect(find.textContaining('No automatic backups yet'), findsOneWidget);
  });

  testWidgets('lists snapshots and restores via confirm', (tester) async {
    final habits = HabitRepository(db);
    final id = await habits.create(name: 'Read', color: 1);
    await habits.checkIn(id, '2026-11-20');
    // Write a snapshot dated today, then delete the habit so restore is visible.
    final svc = AutoBackupService(
      export: ExportService(db),
      directoryPath: dir.path,
    );
    await svc.runDailyBackup();
    await habits.delete(id);

    await pumpScreen(tester);
    final today = DateTime.now();
    final key =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    expect(find.text(key), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('auto-backup-restore-$key')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Restore this backup?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('auto-backup-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Backup restored.'), findsOneWidget);
    expect((await habits.getAll()).single.name, 'Read');
    expect(await habits.getAllCheckins(), hasLength(1));
  });
}
