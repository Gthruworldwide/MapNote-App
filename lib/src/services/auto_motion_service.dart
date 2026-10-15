import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../data/local/auto_motion_data_source.dart';
import 'daily_track_engine.dart';
import 'location_service.dart';
import 'motion_signal.dart';

export 'daily_track_engine.dart' show TrackStartFailure;

/// Phase-1 AutoMotion tracker: while enabled it records today's total
/// distance (km), the current speed and today's max speed (km/h), and stores
/// one daily summary (keyed `YYYY-MM-DD`) in the `auto_motion_box` Hive box.
///
/// All measurement logic is shared with the GPS tracker through
/// [DailyTrackEngine]; this façade keeps AutoMotion's own storage box and
/// settings switch so the two features retain independent lifecycles.
class AutoMotionService {
  AutoMotionService({
    required this.dailyStore,
    MotionSignal? motion,
    Duration flushEvery = persistInterval,
  }) : _engine = DailyTrackEngine(
          store: dailyStore,
          motion: motion,
          flushEvery: flushEvery,
        );

  /// Persistence for daily metrics.
  final AutoMotionDataSource dailyStore;

  final DailyTrackEngine _engine;

  /// While tracking, the day's metrics are flushed on this cadence
  /// (see [DailyTrackEngine.persistInterval]).
  static const Duration persistInterval = DailyTrackEngine.persistInterval;

  TrackStartFailure _failure = TrackStartFailure.none;

  /// Reason the most recent [start] call failed, or [TrackStartFailure.none]
  /// when tracking is live / the last start succeeded.
  TrackStartFailure get failure => _failure;

  /// True while the position stream is attached.
  bool get isTracking => _engine.isTracking;

  /// Total distance recorded today (past sessions + this run), in km.
  double get totalDistanceKm => _engine.totalDistanceKm;

  /// Highest speed recorded today, in km/h.
  double get maxSpeedKmh => _engine.maxSpeedKmh;

  /// Speed of the most recent accepted fix, in km/h.
  double get currentSpeedKmh => _engine.currentSpeedKmh;

  /// Emits after every accepted fix, and after the midnight rollover, so
  /// Settings / Home readouts repaint immediately instead of only when the
  /// toggle is flipped. Never errors and buffers nothing while unlistened.
  Stream<void> get changes => _engine.changes;

  /// Re-seeds today's tallies from the stored day, so an app restart never
  /// "loses" the morning's motion. Requires no platform channels.
  Future<void> resyncFromStore() => _engine.resyncFromStore();

  /// Starts listening for GPS fixes.
  ///
  /// [positions] overrides the geolocator stream (tests); otherwise permissions
  /// are checked through [locations] first. Returns whether the stream is live,
  /// and records the typed reason on [failure] when it is not.
  Future<bool> start({
    LocationService? locations,
    Stream<Position>? positions,
  }) async {
    if (_engine.isTracking) return true;
    await _engine.resyncFromStore();

    final Stream<Position> source;
    if (positions != null) {
      source = positions;
      _failure = TrackStartFailure.none;
    } else {
      final LocationService loc = locations ?? const LocationService();
      final TrackStartFailure failure = await _engine.resolveStartFailure(loc);
      if (failure != TrackStartFailure.none) {
        _failure = failure;
        return false;
      }
      _failure = TrackStartFailure.none;
      // High accuracy, one fix per 10 m of movement; the wrapper re-opens the
      // platform stream if it errors or closes mid-session.
      source = loc.trackingPositionStream(
        onError: (Object _, StackTrace _) {
          // Reported by the reconnector; a single hiccup must not kill tracking.
        },
      );
    }

    await _engine.attach(source);
    return true;
  }

  /// Stops tracking and persists the day's metrics to Hive (flushed).
  ///
  /// Tallies stay in memory afterwards so the dashboard card does not drop to
  /// zero; the next [start] re-seeds them from the store.
  Future<void> stop() => _engine.detach();

  /// Consumes one fix (see [DailyTrackEngine.recordPosition]).
  void recordPosition(Position position) => _engine.recordPosition(position);
}
