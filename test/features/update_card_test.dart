import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/core/platform/link_launcher.dart';
import 'package:nowpill/data/updates/github_release_service.dart';
import 'package:nowpill/data/updates/update_coordinator.dart';
import 'package:nowpill/data/updates/update_installer.dart';
import 'package:nowpill/domain/update_checker.dart';
import 'package:nowpill/features/settings/update_card.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_localizations.dart';

class _Source implements ReleaseSource {
  const _Source();

  @override
  Future<ReleaseFetchResult> fetchLatest({String? etag}) async =>
      const ReleaseFetchResult(notModified: true);

  @override
  Future<String> fetchChecksums(String url) async => '';

  @override
  void close() {}
}

class _Launcher extends LinkLauncher {
  const _Launcher();

  @override
  Future<bool> open(Uri uri) async => true;
}

void main() {
  testWidgets('update card shows the available version and actions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'settings.updateCheckMode': 'manual',
    });
    final coordinator = UpdateCoordinator(
      service: const _Source(),
      installer: const UnsupportedUpdateInstaller(),
      currentVersion: () => '0.9.6',
      onState: (_) {},
      onChecked: (_) {},
    );
    const release = ReleaseInfo(
      version: '0.10.0',
      tag: 'v0.10.0',
      notes: 'New features',
      assets: [
        ReleaseAsset(
          name: 'nowpill-0.10.0-universal.apk',
          url: 'https://github.com/o/app.apk',
          size: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          packageInfoProvider.overrideWithValue(
            AsyncData(
              PackageInfo(
                appName: 'NowPill',
                packageName: 'app.nowpill',
                version: '0.10.0',
                buildNumber: '15',
              ),
            ),
          ),
          updateCoordinatorProvider.overrideWithValue(coordinator),
          updateStateProvider.overrideWithValue(
            const UpdateState(status: UpdateStatus.available, release: release),
          ),
          linkLauncherProvider.overrideWithValue(const _Launcher()),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: M3ETheme(
            data: M3EThemeData.light(),
            child: const Scaffold(body: UpdateCard()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.text('Version 0.10.0 is available'), findsOneWidget);
    expect(find.byKey(const ValueKey('update-check-now')), findsOneWidget);
    expect(find.byKey(const ValueKey('update-download')), findsOneWidget);
  });
}
