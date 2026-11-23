import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../db/app_database.dart';
import '../db/connection_native.dart';
import '../sync/device_identity.dart';
import 'widget_action_handler.dart';

/// Handles a home-screen widget check-in tapped while the app is closed
/// (Android). The Kotlin `WidgetActionReceiver` starts a headless
/// FlutterEngine at this entry point and sends the payload over the
/// `app.nowpill/widget_action` channel; we open the same database file the
/// app uses, apply the check-in through the repository (sync-stamped), and
/// return the fresh snapshot JSON so Kotlin can re-render every widget
/// instance (the headless engine has no widget-bridge handler). Then the
/// engine is destroyed.
///
/// Must be a top-level function annotated `vm:entry-point` so the AOT
/// compiler keeps it. Registered from Kotlin via DartExecutor.executeDartEntrypoint.
@pragma('vm:entry-point')
void widgetActionMainImpl() {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.nowpill/widget_action');
  channel.setMethodCallHandler((call) async {
    if (call.method != 'apply') return null;
    final payload = call.arguments as String?;
    final json = await _handle(payload);
    // Returning the snapshot lets Kotlin persist + refresh widgets in one
    // step; the receiver destroys this engine when the call completes.
    return json;
  });
}

/// Applies the action and returns the fresh snapshot JSON (null on failure
/// or unknown payload).
Future<String?> _handle(String? payload) async {
  final parsed = parseWidgetActionPayload(payload);
  if (parsed == null) return null;
  AppDatabase? db;
  try {
    // Match the main isolate's device identity so any tombstones written
    // here carry the same id (a check-in writes none, but keep it consistent).
    final deviceId = await loadOrCreateDeviceId();
    setBootDeviceId(deviceId);
    final path = await resolveDatabasePath();
    db = AppDatabase.withExecutor(
      NativeDatabase(File(path)),
      deviceId: deviceId,
    );
    final snapshot = await applyWidgetCheckIn(db, parsed.habitId);
    return snapshot == null ? null : jsonEncode(snapshot.toJson());
  } catch (_) {
    // Guarded: a failed action must never crash the background isolate.
    return null;
  } finally {
    await db?.close();
  }
}
