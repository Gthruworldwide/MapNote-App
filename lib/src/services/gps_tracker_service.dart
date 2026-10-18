import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../data/local/gps_daily_data_source.dart';
import 'daily_track_engine.dart';
import 'dead_reckoning_service.dart';
import 'fused_location_service.dart';
import 'gap_recovery_service.dart';
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
    GapRecoveryService? gapRecovery,
    DistanceEstimator? deadReckoning,
    this._fused,
    Duration flushEvery = persistInterval,
  }) : _engine = DailyTrackEngine(
          store: dailyStore,
          motion: motion,
          gapRecovery: gapRecovery,
          deadReckoning: deadReckoning,
          flushEvery: flushEvery,
        );

  /// Persistence for daily summaries.
  final GpsDailyDataSource dailyStore;

  final DailyTrackEngine _engine;

  /// Fused high ⇄ network fallback for the live platform stream; `null` in
  /// unit tests that inject streams, where the plain settings apply.
  final FusedLocationService? _fused;

  /// The [LocationService] the live platform stream was opened with — `null`
  /// when a test injected the stream, which [setPowerMode] then leaves alone.
  LocationService? _activeLocations;

  /// The OS provider-status feed the live session was opened with, so a
  /// power-mode re-open hands the same "GPS off/on" evidence to the fused
  /// fallback.
  Stream<ServiceStatus>? _activeStatus;

  /// Accuracy mode of the live stream: true once MapNote has been backgrounded
  /// during this session (starts false — tracking begins with the app visible).
  bool _backgrounded = false;

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
    final Stream<ServiceStatus>? providerStatus;
    if (positions != null) {
      source = positions;
      providerStatus = null;
      _activeLocations = null;
      _activeStatus = null;
      _failure = TrackStartFailure.none;
    } else {
      final LocationService loc = locations ?? const LocationService();
      final TrackStartFailure failure = await _engine.resolveStartFailure(loc);
      if (failure != TrackStartFailure.none) {
        _failure = failure;
        return false;
      }
      _failure = TrackStartFailure.none;
      // The OS provider's own off/on report: this is what arms gap recovery
      // when GPS is switched off mid-trip and fixes resume afterwards, and
      // what promotes the fused fallback back to the high-accuracy tier.
      providerStatus = loc.serviceStatusStream();
      _activeLocations = loc;
      _activeStatus = providerStatus;
      source = _openFixes(loc);
    }

    await _engine.attach(source, serviceStatus: providerStatus);
    return true;
  }

  /// Stops tracking and persists the day's summary to Hive (flushed).
  ///
  /// Tallies are kept in memory afterwards so the Settings tile does not drop
  /// to zero; the next [start] re-seeds them from the store.
  Future<void> stop() async {
    await _engine.detach();
    _activeStatus = null;
  }

  /// Records that GPS is (or has just been) unavailable — the OS provider was
  /// switched off or the platform stream failed — so the next accepted fix
  /// recovers whatever distance was skipped in between (gap recovery, see
  /// [DailyTrackEngine.noteOutage]). Wired automatically from the stream's
  /// error hook and the provider-status feed; exposed for callers and tests
  /// that observe an outage directly.
  void noteOutage() => _engine.noteOutage();

  /// Switches the live stream to the accuracy the app's visibility calls for:
  /// best available while MapNote is on screen, [LocationAccuracy.medium] —
  /// Android's `PRIORITY_BALANCED_POWER_ACCURACY`, the balanced-power tier —
  /// while it is backgrounded, so the receiver's duty cycle (and the battery)
  /// drops with the screen.
  ///
  /// Today's distance is flushed to Hive *before* the stream is re-opened and
  /// the new stream continues from the last accepted fix, so no background
  /// position state is dropped. Idempotent; a no-op when nothing is tracking
  /// or when a test injected the position stream.
  Future<void> setPowerMode({required bool backgrounded}) async {
    if (backgrounded == _backgrounded) return;
    _backgrounded = backgrounded;
    // Durability first: what is already measured must be on disk before the OS
    // gets a chance to throttle or kill the backgrounded app.
    await _engine.flush();
    final LocationService? locations = _activeLocations;
    if (!_engine.isTracking || locations == null) return;
    await _engine.reopen(_openFixes(locations));
  }

  /// Opens the platform position stream for the current power mode. When a
  /// [FusedLocationService] is wired in (the production wiring), the session
  /// also falls back to the low-power network tier whenever the high-accuracy
  /// receiver goes silent, and is promoted back when the OS reports GPS usable
  /// again — see [FusedLocationService].
  Stream<Position> _openFixes(LocationService locations) {
    void onError(Object _, StackTrace _) => noteOutage();
    final FusedLocationService? fused = _fused;
    if (fused == null) {
      return locations.trackingPositionStream(
        settings: _streamSettings,
        onError: onError,
      );
    }
    return fused.track(
      highSettings: _streamSettings,
      networkSettings: LocationService.trackingSettingsFor(
        accuracy:
            _backgrounded ? LocationAccuracy.low : LocationAccuracy.medium,
      ),
      onError: onError,
      serviceStatus: _activeStatus,
    );
  }

  /// Stream settings for the current power mode (see [setPowerMode]).
  LocationSettings get _streamSettings => _backgrounded
      ? LocationService.backgroundTrackingLocationSettings
      : LocationService.trackingLocationSettings;

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
