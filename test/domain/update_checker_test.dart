import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/update_checker.dart';

/// Pure release JSON parsing, version ordering and asset selection.
void main() {
  final payload = {
    'tag_name': 'v0.10.0',
    'body': 'New features',
    'assets': [
      {
        'name': 'nowpill-0.10.0-universal.apk',
        'browser_download_url': 'https://github.com/u/universal.apk',
        'size': 71,
      },
      {
        'name': 'nowpill-0.10.0-arm64-v8a.apk',
        'browser_download_url': 'https://github.com/u/arm64.apk',
        'size': 24,
      },
      {
        'name': 'nowpill-0.10.0-linux-x64.tar.gz',
        'browser_download_url': 'https://github.com/u/linux.tar.gz',
        'size': 12,
      },
      {
        'name': 'SHA256SUMS-android',
        'browser_download_url': 'https://github.com/u/sums',
        'size': 1,
      },
    ],
  };

  test('parses a release and strips the v prefix', () {
    final release = parseReleaseJson(jsonEncode(payload));
    expect(release.version, '0.10.0');
    expect(release.tag, 'v0.10.0');
    expect(release.notes, 'New features');
    expect(release.assets, hasLength(4));
    expect(release.assets.first.size, 71);
  });

  test('rejects malformed payloads', () {
    expect(() => parseReleaseJson('[]'), throwsA(isA<FormatException>()));
    expect(
      () => parseReleaseJson('{"assets":[]}'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => parseReleaseJson('{"tag_name":"v1","body":"x"}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('numeric version comparison handles double-digit minors', () {
    expect(compareVersions('0.10.0', '0.9.6'), 1);
    expect(isNewerVersion('0.10.1', '0.10.0+15'), isTrue);
    expect(isNewerVersion('0.10.0', '0.10.0'), isFalse);
    expect(isNewerVersion('0.9.6', '0.10.0'), isFalse);
  });

  test('selects split APK, universal fallback and Linux tarball', () {
    final release = parseReleaseJson(jsonEncode(payload));
    expect(
      selectAsset(release, UpdatePlatform.android, abi: 'arm64-v8a')?.name,
      'nowpill-0.10.0-arm64-v8a.apk',
    );
    expect(
      selectAsset(release, UpdatePlatform.android, abi: 'x86')?.name,
      'nowpill-0.10.0-universal.apk',
    );
    expect(
      selectAsset(release, UpdatePlatform.linux)?.name,
      'nowpill-0.10.0-linux-x64.tar.gz',
    );
    expect(selectAsset(release, UpdatePlatform.other), isNull);
  });

  test('parses SHA256SUMS lines', () {
    final sums = parseChecksums('''
${'a' * 64}  nowpill-0.10.0-arm64-v8a.apk
${'B' * 64} *nowpill-0.10.0-linux-x64.tar.gz
not a checksum
''');
    expect(sums['nowpill-0.10.0-arm64-v8a.apk'], 'a' * 64);
    expect(sums['nowpill-0.10.0-linux-x64.tar.gz'], 'b' * 64);
  });
}
