import 'dart:async';
import 'dart:convert';

import '../../domain/sync_merge.dart';
import '../export/export_service.dart';
import 'sync_folder.dart';

/// Outcome of one sync cycle, for the Settings status row.
enum SyncStatus { idle, syncing, ok, folderUnavailable, failed }

/// Immutable status snapshot the Settings UI renders.
class SyncState {
  const SyncState({
    this.status = SyncStatus.idle,
    this.lastSyncAt,
    this.lastError,
    this.lastStats,
  });

  final SyncStatus status;
  final DateTime? lastSyncAt;
  final String? lastError;
  final SyncMergeStats? lastStats;

  SyncState copyWith({
    SyncStatus? status,
    DateTime? lastSyncAt,
    String? lastError,
    SyncMergeStats? lastStats,
    bool clearError = false,
  }) {
    return SyncState(
      status: status ?? this.status,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
      lastStats: lastStats ?? this.lastStats,
    );
  }
}

/// Keeps the local database and the sync folder converged.
///
/// Mirrors the reminder/widget coordinator pattern: watches the data streams,
/// debounces, then runs a sync cycle:
///  1. Collect the local envelope and read every other device's file.
///  2. Merge (pure engine) and apply locally when the merge changed our state.
///  3. Write our own file when its content differs from the merged state.
///
/// Each device only writes its own file, so the transport never sees
/// concurrent writes. A periodic poll picks up remote changes while the app
/// is open; app resume and the manual "Sync now" button trigger cycles too.
class SyncCoordinator {
  SyncCoordinator({
    required this._export,
    required this._deviceId,
    this._folder,
    this._pollInterval = const Duration(seconds: 30),
    DateTime Function()? clock,
    this._onStateChanged,
  }) : _clock = clock ?? DateTime.now;

  final ExportService _export;
  final String _deviceId;
  final Duration _pollInterval;
  final DateTime Function() _clock;
  final void Function(SyncState)? _onStateChanged;

  SyncFolder? _folder;
  SyncState _state = const SyncState();
  Timer? _debounce;
  Timer? _poll;
  bool _started = false;
  bool _cycleRunning = false;
  bool _cycleQueued = false;
  String? _lastWrittenContent;

  String get _ownFileName => syncFileNameFor(_deviceId);

  SyncState get state => _state;
  bool get enabled => _folder != null;

  /// Points the coordinator at a folder (null disables sync) and restarts.
  void setFolder(SyncFolder? folder) {
    _folder = folder;
    _lastWrittenContent = null;
    if (folder == null) {
      _stopTimers();
      _setState(const SyncState());
    } else if (_started) {
      _startTimers();
      scheduleSync();
    }
  }

  /// Starts watching. Idempotent; safe to call with sync disabled.
  void start() {
    if (_started) return;
    _started = true;
    if (_folder != null) {
      _startTimers();
      scheduleSync();
    }
  }

  void _startTimers() {
    _stopTimers();
    _poll = Timer.periodic(_pollInterval, (_) => syncNow());
  }

  void _stopTimers() {
    _debounce?.cancel();
    _debounce = null;
    _poll?.cancel();
    _poll = null;
  }

  /// Called by data-stream listeners (via the provider wiring) and app resume.
  void scheduleSync() {
    if (_folder == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), syncNow);
  }

  /// Runs one sync cycle. Re-entrant calls queue a single follow-up cycle so a
  /// change made during a cycle is never lost.
  Future<void> syncNow() async {
    final folder = _folder;
    if (folder == null) return;
    if (_cycleRunning) {
      _cycleQueued = true;
      return;
    }
    _cycleRunning = true;
    _setState(_state.copyWith(status: SyncStatus.syncing, clearError: true));
    try {
      if (!await folder.isAccessible()) {
        _setState(
          _state.copyWith(
            status: SyncStatus.folderUnavailable,
            lastError: 'folder-unavailable',
          ),
        );
        return;
      }

      final localJson = await _export.collect();
      final localEnvelope = localJson.toJson();
      final remotes = await folder.readOthers(_ownFileName);

      final envelopes = <Map<String, Object?>>[localEnvelope];
      for (final remote in remotes) {
        final parsed = parseSyncEnvelope(remote.content);
        if (parsed != null) envelopes.add(parsed);
      }

      final merged = mergeEnvelopes(
        envelopes: envelopes,
        deviceId: _deviceId,
        now: _clock(),
      );

      // Apply locally only when the merged rows differ from ours (applying
      // unconditionally would re-trigger the data streams every cycle).
      if (!_sameData(localEnvelope, merged.envelope)) {
        await _export.applyMerged(merged.envelope);
      }

      // Publish our file only when the data changed (exportedAt moves every
      // cycle; comparing it would rewrite the file forever).
      final dataKey = _canonicalData(merged.envelope['data']);
      if (dataKey != _lastWrittenContent) {
        await folder.write(_ownFileName, _encodeEnvelope(merged.envelope));
        _lastWrittenContent = dataKey;
      }

      _setState(
        _state.copyWith(
          status: SyncStatus.ok,
          lastSyncAt: _clock(),
          lastStats: merged.stats,
          clearError: true,
        ),
      );
    } catch (e) {
      _setState(_state.copyWith(status: SyncStatus.failed, lastError: '$e'));
    } finally {
      _cycleRunning = false;
      if (_cycleQueued) {
        _cycleQueued = false;
        scheduleSync();
      }
    }
  }

  /// Row-content equality ignoring envelope metadata (exportedAt/deviceId)
  /// and row ordering.
  bool _sameData(Map<String, Object?> a, Map<String, Object?> b) {
    final dataA = a['data'] as Map<String, Object?>? ?? const {};
    final dataB = b['data'] as Map<String, Object?>? ?? const {};
    for (final table in [
      ...kSyncParentTables,
      ...kSyncChildTables,
      'tombstones',
    ]) {
      if (_canonicalRows(dataA[table]) != _canonicalRows(dataB[table])) {
        return false;
      }
    }
    return true;
  }

  String _canonicalRows(Object? rows) {
    if (rows is! List) return '[]';
    final encoded = rows.map((r) {
      if (r is Map<String, Object?>) {
        final copy = Map<String, Object?>.from(r)..remove('id');
        return jsonEncode(copy);
      }
      return jsonEncode(r);
    }).toList()..sort();
    return encoded.join('\n');
  }

  /// Stable key over every table's rows (order-independent).
  String _canonicalData(Object? data) {
    if (data is! Map<String, Object?>) return '';
    final tables = data.keys.toList()..sort();
    return tables.map((t) => '$t:${_canonicalRows(data[t])}').join('\n');
  }

  String _encodeEnvelope(Map<String, Object?> envelope) =>
      const JsonEncoder.withIndent('  ').convert(envelope);

  void _setState(SyncState next) {
    _state = next;
    _onStateChanged?.call(next);
  }

  /// Stops timers. The provider wiring cancels the data subscriptions.
  Future<void> dispose() async {
    _stopTimers();
    _started = false;
  }
}
