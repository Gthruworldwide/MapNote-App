import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../data/local/auto_motion_data_source.dart';
import 'daily_track_engine.dart';
import 'dead_reckoning_service.dart';
import 'fused_location_service.dart';
import 'gap_recovery_service.dart';
import 'location_service.dart';
import 'motion_profiler.dart';
import 'motion_signal.dart';
import 'polyline_smoother.dart';

export 'daily_track_engine.dart' show TrackStartFailure;

/// Phase-1 AutoMotion tracker: while enabled it records today's total
/// distance (km), the current speed, today's max speed (km/h) and the day's
/// recorded route, and stores one daily summary (keyed `YYYY-MM-DD`) in the
/// `auto_motion_box` Hive box.
///
/// All measurement logic is shared with the GPS tracker through
/// [DailyTrackEngine]; this façade keeps AutoMotion's own storage box and
/// settings switch so the two features retain independent lifecycles.
class AutoMotionService {
  AutoMotionService({
    required this.dailyStore,
    MotionSignal? motion,
    GapRecoveryService? gapRecovery,
    DistanceEstimator? deadReckoning,
    PolylineSmoother? smoother,
    MotionBehaviorAnalyzer? behavior,
    this._fused,
    Duration flushEvery = persistInterval,
  }) : _engine = DailyTrackEngine(
          store: dailyStore,
          motion: motion,
          gapRecovery: gapRecovery,
          deadReckoning: deadReckoning,
          smoother: smoother,
          behavior: behavior,
          flushEvery: flushEvery,
        );

  /// Persistence for daily metrics.
  final AutoMotionDataSource dailyStore;

  final DailyTrackEngine _engine;

  /// Fused high ⇄ network fallback for the live platform stream; `null` in
  /// unit tests that inject streams, where the plain settings apply.
  final FusedLocationService? _fused;

  /// The [LocationService] the live platform stream was opened with — `null`
  /// when a test injected the stream, which [setPowerMode] then leaves alone.
  LocationService? _activeLocations;

  /// The OS provider-status feed the live session was opened with, so a
  /// power-mode or sampling re-open hands the same "GPS off/on" evidence to
  /// the fused fallback.
  Stream<ServiceStatus>? _activeStatus;

  /// Accuracy mode of the live stream: true once MapNote has been backgrounded
  /// during this session (starts false — tracking begins with the app visible).
  bool _backgrounded = false;

  /// Adaptive-sampling overrides for the live stream (see [applySampling]):
  /// `null` means "use the fixed 5 s / high-accuracy baseline".
  Duration? _sampleInterval;
  LocationAccuracy? _sampleAccuracy;

  /// While tracking, the day's metrics are flushed on this cadence
  /// (see [DailyTrackEngine.persistInterval]).
  static const Duration persistInterval = DailyTrackEngine.persistInterval;

  /// The fixed baseline request interval when no adaptive profile is active.
  static const Duration defaultInterval = Duration(seconds: 5);

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

  /// Raw accepted fixes recorded for the current day (unmodifiable snapshot).
  List<RoutePoint> get dayPath => _engine.dayPath;

  /// Today's route with GPS jitter smoothed away — what the dashboard draws
  /// and what [resyncFromStore]/the periodic flush persist to trip history.
  List<RoutePoint> get smoothedPath => _engine.smoothedPath;

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

  /// Stops tracking and persists the day's metrics to Hive (flushed).
  ///
  /// Tallies stay in memory afterwards so the dashboard card does not drop to
  /// zero; the next [start] re-seeds them from the store.
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

  /// Applies an adaptive-sampling profile (see `AdaptiveSamplingNotifier`):
  /// the minimum request interval and accuracy tier for how the device is
  /// moving and how much battery is left.
  ///
  /// A [LocationAccuracy.lowest] profile is the *stationary* tier — effectively
  /// paused sampling that the accelerometer classifier can wake again — and
  /// always wins, because a profile may lower accuracy but never raise it
  /// above what the power mode allows (see [_effectiveAccuracy]). Idempotent:
  /// an unchanged profile never re-opens the stream.
  Future<void> applySampling({
    Duration? interval,
    LocationAccuracy? accuracy,
  }) async {
    if (interval == _sampleInterval && accuracy == _sampleAccuracy) return;
    _sampleInterval = interval;
    _sampleAccuracy = accuracy;
    final LocationService? locations = _activeLocations;
    if (!_engine.isTracking || locations == null) return;
    // Same durability rule as [setPowerMode]: measured distance reaches disk
    // before the request cadence changes under the OS.
    await _engine.flush();
    await _engine.reopen(_openFixes(locations));
  }

  /// Opens the platform position stream for the current power mode and
  /// sampling profile. When a [FusedLocationService] is wired in (the
  /// production wiring), the session also falls back to the low-power network
  /// tier whenever the high-accuracy receiver goes silent, and is promoted
  /// back when the OS reports GPS usable again — see [FusedLocationService].
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
        accuracy: _fallbackAccuracy,
        intervalDuration: _sampleInterval ?? defaultInterval,
      ),
      onError: onError,
      serviceStatus: _activeStatus,
    );
  }

  /// Stream settings for the current power mode (see [setPowerMode]) and
  /// adaptive sampling profile (see [applySampling]).
  LocationSettings get _streamSettings => LocationService.trackingSettingsFor(
        accuracy: _effectiveAccuracy,
        intervalDuration: _sampleInterval ?? defaultInterval,
      );

  /// The accuracy the live stream asks for: the sampling profile's tier,
  /// capped at [LocationAccuracy.medium] while backgrounded. A profile may
  /// therefore lower accuracy (stationary → [LocationAccuracy.lowest]) but
  /// never spend more power than the visibility allows.
  LocationAccuracy get _effectiveAccuracy {
    final LocationAccuracy sampled = _sampleAccuracy ?? LocationAccuracy.high;
    if (!_backgrounded) return sampled;
    // The enum is ordered by precision, so a tier at or below `medium` is
    // already within the background budget.
    return sampled.index <= LocationAccuracy.medium.index
        ? sampled
        : LocationAccuracy.medium;
  }

  /// The fallback tier is one notch below the visible tier: Wi-Fi/cell fixes
  /// while on screen, coarse-only once backgrounded (both cost a fraction of
  /// a GPS lock).
  LocationAccuracy get _fallbackAccuracy =>
      _backgrounded ? LocationAccuracy.low : LocationAccuracy.medium;

  /// Consumes one fix (see [DailyTrackEngine.recordPosition]).
  void recordPosition(Position position) => _engine.recordPosition(position);
}
