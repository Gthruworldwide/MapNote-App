import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

import '../core/config/app_config.dart';

/// The kinds of events the local health monitor records.
enum HealthEventType {
  appLaunch,
  appResume,
  appPause,

  syncStarted,
  syncSucceeded,
  syncFailed,
  syncSkipped,

  placeSaved,
  placeDeleted,

  parseFailure,
  shortLinkFailure,

  uiLatency,

  agentRun,
  agentSkipped,
  agentFailure,

  /// A coarse, sanitized "something went wrong" report recorded through
  /// [AppObserverService]. The category lives in `data['category']`.
  serviceIssue,

  /// A harsh driving maneuver (hard braking / harsh acceleration) detected by
  /// the motion behavior analyzer. Carries only the maneuver kind, the peak
  /// acceleration magnitude and a duration in `data` — never a location.
  drivingManeuver,
}

/// A single timestamped health/lifecycle event.
@immutable
class HealthEvent {
  const HealthEvent({
    required this.type,
    required this.timestamp,
    this.message,
    this.durationMs,
    this.data = const <String, Object?>{},
  });

  final HealthEventType type;

  /// When the event happened, in UTC.
  final DateTime timestamp;

  final String? message;

  /// Optional duration for timing events (e.g. UI latency).
  final int? durationMs;

  /// Small, JSON-compatible payload (counts, flags, ...). Never contains PII.
  final Map<String, Object?> data;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'type': type.name,
    'timestamp': timestamp.toUtc().toIso8601String(),
    if (message != null) 'message': message,
    if (durationMs != null) 'durationMs': durationMs,
    if (data.isNotEmpty) 'data': data,
  };

  static HealthEvent? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final HealthEventType? type = _typeFromName(raw['type']);
    if (type == null) return null;
    final DateTime timestamp =
        DateTime.tryParse(raw['timestamp']?.toString() ?? '')?.toUtc() ??
        DateTime.now().toUtc();
    final Object? data = raw['data'];
    return HealthEvent(
      type: type,
      timestamp: timestamp,
      message: raw['message']?.toString(),
      durationMs: raw['durationMs'] is num
          ? (raw['durationMs'] as num).toInt()
          : null,
      data: data is Map
          ? Map<String, Object?>.from(data)
          : const <String, Object?>{},
    );
  }

  static HealthEventType? _typeFromName(Object? name) {
    for (final HealthEventType type in HealthEventType.values) {
      if (type.name == name) return type;
    }
    return null;
  }

  @override
  String toString() =>
      'HealthEvent(${type.name}, $timestamp'
      '${message == null ? '' : ', $message'})';
}

/// An aggregated view of recent health events, used by the recommendation
/// engine so it never has to walk the raw log itself.
@immutable
class HealthSummary {
  const HealthSummary({
    required this.totalEvents,
    required this.appLaunches,
    required this.appResumes,
    required this.syncSucceeded,
    required this.syncFailed,
    required this.syncSkipped,
    required this.parseFailures,
    required this.shortLinkFailures,
    required this.placeSaves,
    this.lastUiLatency,
    this.lastEventAt,
  });

  final int totalEvents;
  final int appLaunches;
  final int appResumes;
  final int syncSucceeded;
  final int syncFailed;
  final int syncSkipped;
  final int parseFailures;
  final int shortLinkFailures;
  final int placeSaves;
  final Duration? lastUiLatency;
  final DateTime? lastEventAt;

  static const HealthSummary empty = HealthSummary(
    totalEvents: 0,
    appLaunches: 0,
    appResumes: 0,
    syncSucceeded: 0,
    syncFailed: 0,
    syncSkipped: 0,
    parseFailures: 0,
    shortLinkFailures: 0,
    placeSaves: 0,
  );
}

/// A lightweight, privacy-safe local event and health logger.
///
/// Events are kept in memory for fast reads and mirrored to a bounded list in
/// the Hive settings box so they survive launches. Nothing here leaves the
/// device; the recommendation engine consumes only aggregate [HealthSummary]
/// numbers.
class AppHealthLogger {
  /// Pass [box] to persist events across launches, or `null` to keep the log
  /// purely in memory (e.g. tests, or when no store is available).
  AppHealthLogger(
    this._box, {
    this.capacity = 200,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Box<dynamic>? _box;

  /// Maximum number of events kept on device.
  final int capacity;
  final DateTime Function() _clock;

  final List<HealthEvent> _events = <HealthEvent>[];
  bool _loaded = false;

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    final Box<dynamic>? box = _box;
    if (box == null) return; // In-memory only.
    final Object? raw = box.get(AppConfig.healthLogKey);
    if (raw is List) {
      for (final Object? entry in raw) {
        final HealthEvent? event = HealthEvent.fromMap(entry);
        if (event != null) _events.add(event);
      }
      _trim();
    }
  }

  /// Records an event. Reads are synchronous; the Hive mirror write is fired and
  /// forgotten so logging never blocks the UI.
  void log(
    HealthEventType type, {
    String? message,
    Duration? duration,
    Map<String, Object?>? data,
  }) {
    _ensureLoaded();
    _events.add(
      HealthEvent(
        type: type,
        timestamp: _clock().toUtc(),
        message: message,
        durationMs: duration?.inMilliseconds,
        data: data ?? const <String, Object?>{},
      ),
    );
    _trim();
    _persist();
  }

  /// Convenience helper for a location string that could not be parsed.
  void logParseFailure({
    required String source,
    bool shortLink = false,
    String? message,
  }) {
    log(
      shortLink ? HealthEventType.shortLinkFailure : HealthEventType.parseFailure,
      message: message,
      data: <String, Object?>{'source': source},
    );
  }

  /// Convenience helper for UI latency (time to first frame / screen open).
  void logUiLatency(String screen, Duration duration) {
    log(
      HealthEventType.uiLatency,
      duration: duration,
      data: <String, Object?>{'screen': screen},
    );
  }

  /// The number of events of [type] within [within] of now.
  int count(HealthEventType type, {Duration within = const Duration(days: 7)}) {
    _ensureLoaded();
    final DateTime threshold = _clock().toUtc().subtract(within);
    int total = 0;
    for (final HealthEvent event in _events) {
      if (event.type == type && !event.timestamp.isBefore(threshold)) {
        total++;
      }
    }
    return total;
  }

  /// Recent events, newest first.
  List<HealthEvent> recent({int limit = 50}) {
    _ensureLoaded();
    final int start = _events.length > limit ? _events.length - limit : 0;
    return _events.sublist(start).reversed.toList(growable: false);
  }

  /// Aggregates events from the last [window] for the recommendation engine.
  HealthSummary summary({Duration window = const Duration(days: 7)}) {
    _ensureLoaded();
    final DateTime threshold = _clock().toUtc().subtract(window);

    int total = 0;
    int launches = 0;
    int resumes = 0;
    int syncOk = 0;
    int syncFailed = 0;
    int syncSkipped = 0;
    int parseFailures = 0;
    int shortLinkFailures = 0;
    int placeSaves = 0;
    Duration? lastLatency;
    DateTime? lastEventAt;

    for (final HealthEvent event in _events) {
      if (event.timestamp.isBefore(threshold)) continue;
      total++;
      if (lastEventAt == null || event.timestamp.isAfter(lastEventAt)) {
        lastEventAt = event.timestamp;
      }
      switch (event.type) {
        case HealthEventType.appLaunch:
          launches++;
        case HealthEventType.appResume:
          resumes++;
        case HealthEventType.syncSucceeded:
          syncOk++;
        case HealthEventType.syncFailed:
          syncFailed++;
        case HealthEventType.syncSkipped:
          syncSkipped++;
        case HealthEventType.parseFailure:
          parseFailures++;
        case HealthEventType.shortLinkFailure:
          shortLinkFailures++;
        case HealthEventType.placeSaved:
          placeSaves++;
        case HealthEventType.uiLatency:
          final int? ms = event.durationMs;
          if (ms != null && (lastLatency == null || ms > lastLatency.inMilliseconds)) {
            lastLatency = Duration(milliseconds: ms);
          }
        case HealthEventType.appPause:
        case HealthEventType.syncStarted:
        case HealthEventType.placeDeleted:
        case HealthEventType.agentRun:
        case HealthEventType.agentSkipped:
        case HealthEventType.agentFailure:
        case HealthEventType.serviceIssue:
        case HealthEventType.drivingManeuver:
          break;
      }
    }

    return HealthSummary(
      totalEvents: total,
      appLaunches: launches,
      appResumes: resumes,
      syncSucceeded: syncOk,
      syncFailed: syncFailed,
      syncSkipped: syncSkipped,
      parseFailures: parseFailures,
      shortLinkFailures: shortLinkFailures,
      placeSaves: placeSaves,
      lastUiLatency: lastLatency,
      lastEventAt: lastEventAt,
    );
  }

  void clear() {
    _ensureLoaded();
    _events.clear();
    _persist();
  }

  void _trim() {
    if (_events.length <= capacity) return;
    _events.removeRange(0, _events.length - capacity);
  }

  void _persist() {
    final Box<dynamic>? box = _box;
    if (box == null) return; // In-memory only; nothing to mirror.
    // Fire-and-forget: a dropped write only costs one event of history.
    box
        .put(
          AppConfig.healthLogKey,
          _events.map((HealthEvent e) => e.toMap()).toList(),
        )
        .catchError((Object error, StackTrace stackTrace) {
          if (kDebugMode) {
            debugPrint('MapNote health log persist failed: $error');
          }
        });
  }
}
