import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'widget_snapshot.dart';

/// Pushes [WidgetSnapshot]s to the native home-screen widgets.
///
/// * **Android** — a MethodChannel call stores the JSON in shared preferences
///   and triggers the AppWidget provider to re-render.
/// * **iOS** — writes to the App Group container and reloads WidgetKit
///   timelines (requires the widget extension target; see ios/NowPillWidget).
/// * **Other platforms** — no-op.
///
/// Every call is guarded: a missing platform handler (tests, desktop) never
/// throws, so data flows are unaffected.
class WidgetBridgeService {
  WidgetBridgeService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.nowpill/widget');

  final MethodChannel _channel;
  WidgetSnapshot? _last;

  /// Whether this platform has a home-screen widget implementation.
  bool get supported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Sends [snapshot] to the OS widget. Identical consecutive snapshots are
  /// skipped to avoid redundant widget refreshes. Returns true when the
  /// platform accepted the update.
  Future<bool> update(WidgetSnapshot snapshot) async {
    if (!supported) return false;
    if (snapshot == _last) return true;
    try {
      await _channel.invokeMethod<void>(
        'updateSnapshot',
        jsonEncode(snapshot.toJson()),
      );
      _last = snapshot;
      return true;
    } catch (_) {
      // No handler (widget not installed / tests): swallow.
      return false;
    }
  }
}
