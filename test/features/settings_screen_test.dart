import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/export/backup_service.dart';
import 'package:nowpill/data/export/export_service.dart';
import 'package:nowpill/data/notifications/notification_permission_service.dart';
import 'package:nowpill/data/notifications/notification_service.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/test_database.dart';
import '../helpers/test_localizations.dart';

/// A [BackupService] that skips native file dialogs: export reports success,
/// and the picked file is an in-memory string the test controls.
class FakeBackupService extends BackupService {
  FakeBackupService(super.export) : super();

  String? pickedJson;
  int exportCalls = 0;

  @override
  Future<ExportOutcome> exportToFile() async {
    exportCalls++;
    return ExportOutcome.shared;
  }

  @override
  Future<String?> pickBackupFile() async => pickedJson;
}

/// A permission service with scripted state, skipping platform channels.
class FakePermissionService extends NotificationPermissionService {
  FakePermissionService() : super();

  NotificationPermissionStatus scriptedStatus =
      NotificationPermissionStatus.denied;
  NotificationPermissionStatus requestResult =
      NotificationPermissionStatus.granted;
  bool canExact = false;
  bool exactAfterRequest = true;
  int requestCalls = 0;
  int exactRequestCalls = 0;

  @override
  Future<NotificationPermissionStatus> status() async => scriptedStatus;

  @override
  Future<NotificationPermissionStatus> request() async {
    requestCalls++;
    return requestResult;
  }

  @override
  Future<bool> canScheduleExactAlarms() async => canExact;

  @override
  Future<bool> requestExactAlarmsPermission() async {
    exactRequestCalls++;
    canExact = exactAfterRequest;
    return canExact;
  }
}

/// A notification service that records test fires instead of touching a
/// platform plugin.
class FakeNotificationService extends NotificationService {
  FakeNotificationService() : super();

  bool showResult = true;
  bool supported = true;
  int showCalls = 0;

  @override
  bool get webSupported => supported;

  @override
  Future<bool> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    showCalls++;
    return showResult;
  }
}

void main() {
  late AppDatabase db;
  late FakeBackupService backup;
  late FakePermissionService permission;
  late FakeNotificationService notifications;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'settings.onboardingComplete': true,
    });
    db = createTestDatabase();
    backup = FakeBackupService(ExportService(db));
    permission = FakePermissionService();
    notifications = FakeNotificationService();
  });

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        backupServiceProvider.overrideWithValue(backup),
        notificationPermissionServiceProvider.overrideWithValue(permission),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: M3ETheme(data: M3EThemeData.light(), child: child),
      ),
    );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  }

  testWidgets('shows all sections including data and about', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Motion'), findsOneWidget);
    expect(find.text('Reminders & week'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    // Data/About sit below the fold once the Language section is present.
    await tester.scrollUntilVisible(find.text('Data'), 200);
    expect(find.text('Data'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('About'), 200);
    expect(find.text('About'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('NowPill'), 200);
    expect(find.text('NowPill'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Set default'), -200);
    expect(find.text('Set default'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('week-start switch persists the choice', (tester) async {
    await pumpScreen(tester);
    // The week-start switch is the second M3ESwitch (first is dynamic color).
    await tester.tap(find.byType(M3ESwitch).at(1));
    await settle(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('settings.weekStartsOnMonday'), isFalse);
    await cleanup(tester);
  });

  testWidgets('export reports success via snackbar', (tester) async {
    await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('Export'), 300);
    await tester.tap(find.text('Export'));
    await settle(tester);
    expect(backup.exportCalls, 1);
    expect(find.text('Backup exported.'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('import validates, confirms, then replaces all data', (
    tester,
  ) async {
    // Seed a backup payload: one habit + one task.
    await HabitRepository(db).create(name: 'ImportedHabit', color: 0xFF2DD4A8);
    await TaskRepository(db).create(title: 'ImportedTask');
    backup.pickedJson = await ExportService(db).exportToString();

    // Add different live data that must be wiped on restore.
    await TaskRepository(db).create(title: 'LiveTask');

    await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('Import'), 300);
    await tester.tap(find.text('Import'));
    await settle(tester);

    // Confirm dialog shows the payload summary.
    expect(find.text('Replace all data?'), findsOneWidget);
    expect(find.textContaining('1 habits'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-confirm')));
    await settle(tester);

    expect(find.text('Backup restored.'), findsOneWidget);
    final tasks = await db.select(db.tasks).get();
    expect(tasks, hasLength(1));
    expect(tasks.single.title, 'ImportedTask');
    expect(await db.select(db.habits).get(), hasLength(1));
    await cleanup(tester);
  });

  testWidgets('import cancel leaves data untouched', (tester) async {
    await TaskRepository(db).create(title: 'KeepMe');
    backup.pickedJson = await ExportService(db).exportToString();
    await TaskRepository(db).create(title: 'AlsoKeep');

    await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('Import'), 300);
    await tester.tap(find.text('Import'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('import-cancel')));
    await settle(tester);

    expect(find.text('Backup restored.'), findsNothing);
    expect(await db.select(db.tasks).get(), hasLength(2));
    await cleanup(tester);
  });

  testWidgets('invalid backup shows an error and keeps data', (tester) async {
    await TaskRepository(db).create(title: 'Safe');
    backup.pickedJson = 'this is not a valid backup';

    await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('Import'), 300);
    await tester.tap(find.text('Import'));
    await settle(tester);

    expect(find.textContaining('Invalid backup'), findsOneWidget);
    expect(find.text('Replace all data?'), findsNothing);
    expect(await db.select(db.tasks).get(), hasLength(1));
    await cleanup(tester);
  });

  testWidgets('denied permission offers Enable, which requests access', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.text('Enable'), findsOneWidget);
    await tester.tap(find.text('Enable'));
    await settle(tester);
    expect(permission.requestCalls, 1);
    expect(find.text('Notifications are enabled.'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('iOS priming dialog gates the system permission request', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await pumpScreen(tester);
    await tester.tap(find.text('Enable'));
    await settle(tester);

    // Priming explains the ask before the one-shot system prompt.
    expect(find.text('Stay on track'), findsOneWidget);
    expect(permission.requestCalls, 0);

    // "Not now" cancels without ever calling the platform request.
    await tester.tap(find.byKey(const ValueKey('ios-priming-cancel')));
    await settle(tester);
    expect(permission.requestCalls, 0);

    // Continue primes then requests.
    await tester.tap(find.text('Enable'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ios-priming-continue')));
    await settle(tester);
    expect(permission.requestCalls, 1);
    await cleanup(tester);
  });

  testWidgets('Android exact-alarm row requests settings access', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await pumpScreen(tester);
    expect(find.textContaining('Exact alarms are off'), findsOneWidget);

    await tester.tap(find.text('Allow'));
    await settle(tester);

    expect(permission.exactRequestCalls, 1);
    expect(
      find.text('Exact alarms allowed — reminders fire on time.'),
      findsOneWidget,
    );
    await cleanup(tester);
  });

  testWidgets('exact-alarm row hidden when access is already granted', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    permission.canExact = true;

    await pumpScreen(tester);
    expect(
      find.text('Exact alarms allowed — reminders fire on time.'),
      findsOneWidget,
    );
    expect(find.text('Allow'), findsNothing);
    await cleanup(tester);
  });

  testWidgets('test notification fires and reports success', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Send test notification'));
    await settle(tester);
    expect(notifications.showCalls, 1);
    expect(find.text('Test notification sent.'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('failed test notification reports an error', (tester) async {
    notifications.showResult = false;
    await pumpScreen(tester);
    await tester.tap(find.text('Send test notification'));
    await settle(tester);
    expect(find.text('Could not send a test notification.'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('unsupported browser shows a hint instead of firing', (
    tester,
  ) async {
    notifications.supported = false;
    await pumpScreen(tester);
    await tester.tap(find.text('Send test notification'));
    await settle(tester);
    expect(notifications.showCalls, 0);
    expect(
      find.textContaining('does not support notifications'),
      findsOneWidget,
    );
    await cleanup(tester);
  });
}
