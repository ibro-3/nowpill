/// Pure GitHub Releases parsing, version comparison and asset selection.
/// No Flutter, HTTP or filesystem imports — this is unit-testable on its own.
library;

import 'dart:convert';

/// How often the app contacts GitHub for updates.
enum UpdateCheckMode { off, manual, startup, daily, weekly }

/// Platforms the updater knows how to handle.
enum UpdatePlatform { android, linux, other }

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;
  final String url;
  final int size;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.tag,
    required this.notes,
    required this.assets,
  });

  /// Tag with a leading `v` removed, e.g. `0.10.0`.
  final String version;
  final String tag;
  final String notes;
  final List<ReleaseAsset> assets;
}

/// Parses the JSON body of `GET /repos/ibro-3/nowpill/releases/latest`.
ReleaseInfo parseReleaseJson(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Release payload is not an object');
  }
  final tag = decoded['tag_name'];
  if (tag is! String || tag.isEmpty) {
    throw const FormatException('Release payload has no tag_name');
  }
  final rawAssets = decoded['assets'];
  if (rawAssets is! List) {
    throw const FormatException('Release payload has no assets list');
  }
  final assets = <ReleaseAsset>[];
  for (final item in rawAssets) {
    if (item is! Map<String, Object?>) continue;
    final name = item['name'];
    final url = item['browser_download_url'];
    if (name is! String || url is! String) continue;
    assets.add(
      ReleaseAsset(
        name: name,
        url: url,
        size: item['size'] is int ? item['size'] as int : 0,
      ),
    );
  }
  final body = decoded['body'];
  return ReleaseInfo(
    version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
    tag: tag,
    notes: body is String ? body : '',
    assets: assets,
  );
}

/// Numeric-only version comparison. A leading `v` and build metadata (`+15`)
/// are ignored; non-numeric prerelease suffixes are out of scope.
int compareVersions(String a, String b) {
  final left = _numbers(a);
  final right = _numbers(b);
  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l < r ? -1 : 1;
  }
  return 0;
}

List<int> _numbers(String version) => version
    .replaceFirst(RegExp(r'^[vV]'), '')
    .split('.')
    .map(
      (part) =>
          int.tryParse(RegExp(r'\d+').firstMatch(part)?.group(0) ?? '') ?? 0,
    )
    .toList();

bool isNewerVersion(String remote, String local) =>
    compareVersions(remote, local) > 0;

/// Picks the best downloadable asset for [platform].
///
/// Android prefers the ABI-specific split APK and falls back to the universal
/// one. Linux takes the x86-64 tarball. Everything else gets nothing — the UI
/// then offers the releases page instead.
ReleaseAsset? selectAsset(
  ReleaseInfo release,
  UpdatePlatform platform, {
  String? abi,
}) {
  switch (platform) {
    case UpdatePlatform.android:
      if (abi != null) {
        final split = release.assets.where((a) => a.name.endsWith('-$abi.apk'));
        if (split.isNotEmpty) return split.first;
      }
      for (final asset in release.assets) {
        if (asset.name.endsWith('-universal.apk')) return asset;
      }
      final apks = release.assets.where((a) => a.name.endsWith('.apk'));
      return apks.isEmpty ? null : apks.first;
    case UpdatePlatform.linux:
      final tarballs = release.assets.where(
        (a) => a.name.endsWith('-linux-x64.tar.gz'),
      );
      return tarballs.isEmpty ? null : tarballs.first;
    case UpdatePlatform.other:
      return null;
  }
}

/// Parses a `SHA256SUMS` file into filename → hex digest.
Map<String, String> parseChecksums(String raw) {
  final result = <String, String>{};
  final pattern = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(\S+)$', multiLine: true);
  for (final match in pattern.allMatches(raw)) {
    result[match.group(2)!] = match.group(1)!.toLowerCase();
  }
  return result;
}
