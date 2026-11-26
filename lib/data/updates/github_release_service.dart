import 'dart:convert';
import 'dart:io';

import '../../domain/update_checker.dart';

const String kReleasesApi =
    'https://api.github.com/repos/ibro-3/nowpill/releases/latest';

class UpdateHttpException implements Exception {
  const UpdateHttpException(this.statusCode);
  final int statusCode;
  @override
  String toString() => 'UpdateHttpException: HTTP $statusCode';
}

class UpdateRateLimitException implements Exception {
  const UpdateRateLimitException();
  @override
  String toString() => 'UpdateRateLimitException: GitHub rate limit reached';
}

class ReleaseFetchResult {
  const ReleaseFetchResult({this.release, this.etag, this.notModified = false});

  final ReleaseInfo? release;
  final String? etag;
  final bool notModified;
}

/// Source of release metadata and checksum files. Abstracted so coordinator
/// tests never touch the network.
abstract class ReleaseSource {
  Future<ReleaseFetchResult> fetchLatest({String? etag});
  Future<String> fetchChecksums(String url);
  void close();
}

/// Fetches release metadata and checksum files from GitHub.
///
/// An injected [HttpClient] keeps this testable without real network calls.
/// GitHub's unauthenticated API is rate-limited, so callers must cache the
/// returned ETag and send it on the next check.
class GithubReleaseService implements ReleaseSource {
  GithubReleaseService({
    HttpClient? client,
    this._userAgent = 'NowPill-Updater',
    this._latestUrl = kReleasesApi,
  }) : _client = client ?? HttpClient();

  final HttpClient _client;
  final String _userAgent;
  final String _latestUrl;

  Future<HttpClientResponse> _get(Uri url, {String? etag}) async {
    final request = await _client.getUrl(url);
    request.headers
      ..set('User-Agent', _userAgent)
      ..set('Accept', 'application/vnd.github+json');
    if (etag != null) request.headers.set('If-None-Match', etag);
    return request.close().timeout(const Duration(seconds: 15));
  }

  @override
  Future<ReleaseFetchResult> fetchLatest({String? etag}) async {
    final response = await _get(Uri.parse(_latestUrl), etag: etag);
    if (response.statusCode == 304) {
      await response.drain<void>();
      return const ReleaseFetchResult(notModified: true);
    }
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode == 403) {
      throw const UpdateRateLimitException();
    }
    if (response.statusCode != 200) {
      throw UpdateHttpException(response.statusCode);
    }
    return ReleaseFetchResult(
      release: parseReleaseJson(body),
      etag: response.headers.value('etag'),
    );
  }

  /// Downloads a `SHA256SUMS*` asset so the chosen artifact can be verified.
  @override
  Future<String> fetchChecksums(String url) async {
    final response = await _get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw UpdateHttpException(response.statusCode);
    }
    return utf8.decoder.bind(response).join();
  }

  @override
  void close() => _client.close(force: true);
}
