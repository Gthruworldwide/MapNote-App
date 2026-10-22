import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../core/motion/stationary_idle_detector.dart';
import '../data/local/gps_daily_data_source.dart';
import 'daily_track_engine.dart';
import 'dead_reckoning_service.dart';
import 'fused_location_service.dart';
import 'gap_recovery_service.dart';
import 'location_hub.dart';
import 'location_service.dart';
import 'motion_signal.dart';
import 'sampling_target.dart';

/// Phase-1 GPS tracker: measures today's total distance (km), current and
/// maximum speed (km/h) while the app is open, and saves one
/// [DailyGpsSummary] per day into Hive.
///
/// All measurement logic (Haversine accumulation, noise/speed filtering,
/// midnight rollover, periodic persistence) lives in the shared
/// [DailyTrackEngine]. This façade owns only the GPS-specific storage box and
/// surfaces the typed [TrackStartFailure] the Settings tile reports.
///
/// ## One OS location handle
///
/// When a [LocationHub] is wired in (the production path) the live feed comes
/// from the hub, so this tracker and every other consumer — the Qibla compass
/// included — share **one** `FusedLocationProvider` client instead of each
/// registering their own. The tracker remains the refcount: it acquires the
/// hub while it records and releases it when it stops or pauses, which is what
/// drops the app's client count to zero during `IdleStandby`.
class GpsTrackerService implements SamplingTarget {
  GpsTrackerService({
    required this.dailyStore,
    MotionSignal? motion,
    GapRecoveryService? gapRecovery,
    DistanceEstimator? deadReckoning,
    StationaryIdleDetector? stationaryDetector,
    this._fused,
    this._hub,
    Duration flushEvery = persistInterval,
  }) : _engine = DailyTrackEngine(
          store: dailyStore,
          motion: motion,
          gapRecovery: gapRecovery,
          deadReckoning: deadReckoning,
          stationaryDetector: stationaryDetector ?? StationaryIdleDetector(),
          flushEvery: flushEvery,
        );

  /// Persistence for daily summaries.
  final GpsDailyDataSource dailyStore;

  /// The idle detector that judges "this device has not moved" (shared with
  /// the AutoMotion tracker, so the two can never disagree).
  StationaryIdleDetector get stationaryDetector => _engine.stationaryDetector!;

  final DailyTrackEngine _engine;

  /// Fused high ⇄ network fallback for the live platform stream; `null` in
  /// unit tests that inject streams, where the plain settings apply.
  final FusedLocationService? _fused;

  /// The app-wide single location client (see [LocationHub]); `null` in unit
  /// tests that drive injected streams directly.
  final LocationHub? _hub;

  /// Whether this tracker currently holds a hub registration, so a release is
  /// never sent for an interest that was never acquired.
  bool _hubHeld = false;

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

  /// Adaptive-sampling overrides for the live stream (see [applySampling]):
  /// `null` means "use the fixed 5 s / 10 m baseline", and `false` means
  /// "no transport-speed exception to the background accuracy cap".
  Duration? _sampleInterval;
  LocationAccuracy? _sampleAccuracy;
  int? _sampleDistanceFilter;
  bool _transportSpeed = false;

  /// Whether the adaptive profile has closed the platform stream (see
  /// [applySampling]'s `paused`). The session stays live — tallies, the last
  /// fix and the outage window all survive — but nothing is subscribed, so the
  /// receiver can enter hardware sleep.
  bool _streamPaused = false;

  /// While tracking, the day's metrics are flushed on this cadence
  /// (see [DailyTrackEngine.persistInterval]).
  static const Duration persistInterval = DailyTrackEngine.persistInterval;

  /// The fixed baseline request interval when no adaptive profile is active.
  static const Duration defaultInterval = Duration(seconds: 5);

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
  ///
  /// The hub registration is released here, so a stopped tracker holds no OS
  /// location client at all.
  Future<void> stop() async {
    await _releaseHub();
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

  /// Applies an adaptive-sampling profile (see `AdaptiveSamplingNotifier` and
  /// `AdaptiveEngineOrchestrator.profiles`): the minimum request interval, the
  /// accuracy tier, the movement filter and whether the stream should be closed
  /// outright, for how the device is moving and how much battery is left.
  /// Without a profile the fixed 5 s / 10 m baselines apply.
  ///
  /// [paused] is the orchestrator's `idleStandby` verdict: the session stays
  /// live (distance, max speed, the last accepted fix and the outage window all
  /// survive) but the platform subscription is **cancelled**, so the fused
  /// provider lets the GNSS receiver sleep. Merely asking less often would not
  /// achieve that — an open stream at any cadence is what the OS reports to the
  /// user as a background-location warning. The activity gate re-opens the
  /// stream as soon as the device genuinely moves.
  ///
  /// A [LocationAccuracy.lowest] profile is the *stationary* tier — effectively
  /// paused sampling that the accelerometer classifier can wake again — and
  /// always wins, because a profile may lower accuracy but never raise it
  /// above what the power mode allows (see [_effectiveAccuracy]). The one
  /// exception is [transportSpeed]: a vehicle-speed profile keeps GPS-grade
  /// accuracy even while backgrounded, because at 30 m/s a balanced-power
  /// fix would bend the recorded path into chords. Idempotent: an unchanged
  /// profile never re-opens the stream.
  @override
  Future<void> applySampling({
    Duration? interval,
    LocationAccuracy? accuracy,
    int? distanceFilter,
    bool transportSpeed = false,
    bool paused = false,
  }) async {
    if (interval == _sampleInterval &&
        accuracy == _sampleAccuracy &&
        distanceFilter == _sampleDistanceFilter &&
        transportSpeed == _transportSpeed &&
        paused == _streamPaused) {
      return;
    }
    _sampleInterval = interval;
    _sampleAccuracy = accuracy;
    _sampleDistanceFilter = distanceFilter;
    _transportSpeed = transportSpeed;
    _streamPaused = paused;
    final LocationService? locations = _activeLocations;
    if (locations == null) return;
    // Same durability rule as [setPowerMode]: measured distance reaches disk
    // before the request cadence changes under the OS.
    await _engine.flush();
    // A paused profile detaches the stream entirely (see [_streamPaused]); a
    // detached engine is still "tracking", so resuming re-opens it without
    // restarting the session. With a hub wired in this *releases the OS
    // handle*, which is what takes the app's client count to zero while idle.
    if (!_engine.isTracking) return;
    if (paused) {
      await _releaseHub();
      await _engine.reopen(const Stream<Position>.empty());
      return;
    }
    await _engine.reopen(_openFixes(locations));
  }

  /// Opens the platform position stream for the current power mode. When a
  /// [FusedLocationService] is wired in (the production wiring), the session
  /// also falls back to the low-power network tier whenever the high-accuracy
  /// receiver goes silent, and is promoted back when the OS reports GPS usable
  /// again — see [FusedLocationService].
  Stream<Position> _openFixes(LocationService locations) {
    void onError(Object _, StackTrace _) => noteOutage();
    final LocationHub? hub = _hub;
    if (hub != null) {
      // One shared OS client for the whole app. The hub serves the strongest
      // tier any consumer wants and re-opens its single handle when that
      // changes, so this tracker never registers a second one.
      _hubHeld = true;
      return hub.acquire(
        this,
        accuracy: _effectiveAccuracy,
        // The *effective* interval, not the profile's: a `null` interval would
        // collapse to the plugin's 5 s default inside the shared hub, which is
        // exactly the background poll the background tier exists to prevent.
        interval: _effectiveInterval,
        distanceFilter: _effectiveDistanceFilter,
      );
    }
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
        intervalDuration: _effectiveInterval,
        distanceFilter: _effectiveDistanceFilter,
      ),
      onError: onError,
      serviceStatus: _activeStatus,
    );
  }

  /// Drops this tracker's [LocationHub] registration if it holds one.
  ///
  /// This is what strands no client behind: without it, a paused or stopped
  /// tracker would keep the app registered on `FusedLocationProvider` even
  /// though nothing is listening to the fixes.
  Future<void> _releaseHub() async {
    final LocationHub? hub = _hub;
    if (hub == null || !_hubHeld) return;
    _hubHeld = false;
    await hub.release(this);
  }

  /// Stream settings for the current power mode (see [setPowerMode]) and
  /// adaptive sampling profile (see [applySampling]). Without a profile this
  /// is exactly the two fixed baselines: 5 s / 10 m at best accuracy while
  /// visible, at the balanced-power tier while backgrounded.
  LocationSettings get _streamSettings => LocationService.trackingSettingsFor(
        accuracy: _effectiveAccuracy,
        intervalDuration: _effectiveInterval,
        distanceFilter: _effectiveDistanceFilter,
      );

  /// The request cadence the live stream runs with: the sampling profile's
  /// interval when the engine has dictated one, otherwise the fixed
  /// foreground baseline — or, once MapNote is backgrounded, the *background*
  /// tier (15 s), which asks the receiver far less often.
  Duration get _effectiveInterval => _sampleInterval ??
      (_backgrounded
          ? LocationService.backgroundTrackingInterval
          : defaultInterval);

  /// The movement filter the live stream runs with: the sampling profile's
  /// tier (the stationary tier's 50 m swallows jitter outright), or the
  /// fixed 10 m baseline while no profile is active — or, once MapNote is
  /// backgrounded, the background tier's 15 m, which ignores the
  /// micro-movement that would otherwise wake the receiver.
  int get _effectiveDistanceFilter => _sampleDistanceFilter ??
      (_backgrounded
          ? LocationService.backgroundTrackingDistanceFilterMeters
          : LocationService.trackingDistanceFilterMeters);

  /// The accuracy the live stream asks for: the sampling profile's tier,
  /// capped at [LocationAccuracy.medium] — geolocator's name for Android's
  /// `PRIORITY_BALANCED_POWER_ACCURACY`, the balanced-power tier — while
  /// backgrounded, so the receiver's duty cycle (and the battery) drops with
  /// the screen. The one exception is [transportSpeed]: a vehicle-speed
  /// profile keeps GPS-grade accuracy even in the background, where a coarse
  /// fix would bend the recorded path into chords.
  LocationAccuracy get _effectiveAccuracy {
    final LocationAccuracy sampled = _sampleAccuracy ?? LocationAccuracy.high;
    if (!_backgrounded) return sampled;
    // The enum is ordered by precision, so a tier at or below `medium` is
    // already within the background budget.
    if (sampled.index <= LocationAccuracy.medium.index) return sampled;
    return _transportSpeed ? LocationAccuracy.high : LocationAccuracy.medium;
  }

  /// The fallback tier is one notch below the visible tier: Wi-Fi/cell fixes
  /// while on screen, coarse-only once backgrounded (both cost a fraction of
  /// a GPS lock).
  LocationAccuracy get _fallbackAccuracy =>
      _backgrounded ? LocationAccuracy.low : LocationAccuracy.medium;

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
