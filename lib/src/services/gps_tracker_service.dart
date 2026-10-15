import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../data/local/gps_daily_data_source.dart';
import 'daily_track_engine.dart';
import 'location_service.dart';
import 'motion_signal.dart';

/// Phase-1 GPS tracker: measures today's total distance (km), current and
/// maximum speed (km/h) while the app is open, and saves one
/// [DailyGpsSummary] per day into Hive.
///
/// All measurement logic (Haversine accumulation, noise/speed filtering,
/// midnight rollover, periodic persistence) lives in the shared
/// [DailyTrackEngine]. This façade owns only the GPS-specific storage box and
/// surfaces the typed [TrackStartFailure] the Settings tile reports.
class GpsTrackerService {
  GpsTrackerService({
    required this.dailyStore,
    MotionSignal? motion,
    Duration flushEvery = persistInterval,
  }) : _engine = DailyTrackEngine(
          store: dailyStore,
          motion: motion,
          flushEvery: flushEvery,
        );

  /// Persistence for daily summaries.
  final GpsDailyDataSource dailyStore;

  final DailyTrackEngine _engine;

  /// While tracking, the day's metrics are flushed on this cadence
  /// (see [DailyTrackEngine.persistInterval]).
  static const Duration persistInterval = DailyTrackEngine.persistInterval;

  TrackStartFailure _failure = TrackStartFailure.none;

  /// Reason the most recent [start] call could not begin tracking, or
  /// [TrackStartFailure.none] when tracking is live / the last start succeeded.
  TrackStartFailure get failure => _failure;

  /// True while the position stream is attached.
  bool get isTracking => _engine.isTracking;

  /// Total distance travelled today (past sessions + this run), in km.
  double get totalDistanceKm => _engine.totalDistanceKm;

  /// Highest speed measured today, in km/h.
  double get maxSpeedKmh => _engine.maxSpeedKmh;

  /// Speed of the most recent accepted fix, in km/h.
  double get currentSpeedKmh => _engine.currentSpeedKmh;

  /// Emits after every accepted fix, and after the midnight rollover, so
  /// Settings readouts repaint immediately instead of only on a toggle.
  Stream<void> get changes => _engine.changes;

  /// Re-seeds today's tallies from the day's persisted summary, so a restart
  /// or app foreground never "loses" the morning's tracking. Safe to call at
  /// any time; requires no platform channels.
  Future<void> resyncFromStore() => _engine.resyncFromStore();

  /// Starts listening for GPS fixes.
  ///
  /// [positions] overrides the geolocator stream (tests); otherwise
  /// permissions are checked through [locations] first. Returns whether the
  /// stream is now live, and records the typed reason on [failure] when it is
  /// not.
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

  /// Stops tracking and persists the day's summary to Hive (flushed).
  ///
  /// Tallies are kept in memory afterwards so the Settings tile does not drop
  /// to zero; the next [start] re-seeds them from the store.
  Future<void> stop() => _engine.detach();

  /// Consumes one fix (see [DailyTrackEngine.recordPosition]).
  void recordPosition(Position position) => _engine.recordPosition(position);

  /// Great-circle distance between two coordinates, in kilometres (Haversine).
  static double distanceKmBetween(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) =>
      DailyTrackEngine.distanceKmBetween(lat1, lon1, lat2, lon2);
}
