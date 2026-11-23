import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _kDeviceId = 'sync.deviceId';

String _bootDeviceId = 'local';

/// Set once at startup (before the database opens) so tombstones written by
/// any DAO carry the real device identity. Tests keep the `local` default.
void setBootDeviceId(String id) => _bootDeviceId = id;

/// The device identity for this app run.
String get bootDeviceId => _bootDeviceId;

/// The persisted per-device identity used in sync envelope file names and
/// tombstones. Generated once, kept forever (renaming it would orphan the
/// device's previous envelope file in the sync folder).
Future<String> loadOrCreateDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_kDeviceId);
  if (existing != null && existing.isNotEmpty) return existing;
  // Short id keeps file names readable; v4 randomness avoids collisions.
  final id = const Uuid().v4().substring(0, 8);
  await prefs.setString(_kDeviceId, id);
  return id;
}
