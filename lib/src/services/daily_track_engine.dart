import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../core/utils/geo_distance.dart';
import '../data/local/daily_track_store.dart';
import '../data/models/daily_gps_summary.dart';
import 'dead_reckoning_service.dart';
import 'gap_recovery_service.dart';
import 'location_service.dart';
import 'motion_signal.dart';

/// Why the most recent `start()` on a daily tracker could not begin tracking.
///
/// Surfaced to the UI so a refused start is never silent: the daily-GPS tile
/// and the AutoMotion card both tell the user whether GPS is off, permission
/// was denied, permission is permanently blocked, or the platform channel
/// failed.
enum TrackStartFailure {
  /// Tracking is live, or the last start succeeded.
  none,

  /// The OS location service (GPS) is switched off.
  locationServiceDisabled,

  /// The runtime location permission was refused this time.
  permissionDenied,

  /// The runtime location permission is permanently blocked.
  permissionDeniedForever,

  /// The platform location channel raised (plugin unavailable / not ready).
  platformError,
}

/// The measurement core shared by [GpsTrackerService] and [AutoMotionService].
///
/// Owns the Haversine distance accumulation, the accuracy / jitter / speed
/// noise filters, the motion-signal gap bridge, the GPS-outage gap-recovery
/// pass, the local-midnight rollover and the periodic crash-resilience flush.
/// The two trackers differ only in their storage box, their settings switch
/// and the way their lifecycle is surfaced, so each wraps one engine with its
/// own [DailyTrackStore] and keeps a fully independent lifecycle.
class DailyTrackEngine {
  DailyTrackEngine({
    required this.store,
    MotionSignal? motion,
    GapRecoveryService? gapRecovery,
    DistanceEstimator? deadReckoning,
    this.flushEvery = persistInterval,
  })  : _motion = motion ?? const NoMotionSignal(),
        _gapRecovery = gapRecovery ?? const GapRecoveryService(),
        _deadReckoning = deadReckoning ?? const NoopDistanceEstimator();

  /// Where each day's summary is persisted (one Hive box per tracker).
  final DailyTrackStore store;

  /// Movement evidence for the dead-reckoning gap bridge (see [MotionSignal]);
  /// the no-op default keeps unit tests channel-free.
  final MotionSignal _motion;

  /// The gap-recovery rule: judges whether a skipped A→B crossing is
  /// plausible travel and may rejoin today's total (see [GapRecoveryService]).
  final GapRecoveryService _gapRecovery;

  /// Inertial witness for outage windows the Haversine crossing cannot vouch
  /// for (a refused first-fix-back, or a session that ends mid-outage). The
  /// no-op default keeps unit tests channel-free.
  final DistanceEstimator _deadReckoning;

  /// How often the periodic flush runs. Defaults to [persistInterval]; tests
  /// pass a short value so the cadence can be observed without waiting 10 s.
  final Duration flushEvery;

  /// Fixes that moved less than this many metres are GPS jitter, not travel.
  static const int minStepMeters = 3;

  /// Fixes worse than this horizontal accuracy (metres) are dropped.
  static const double maxAccuracyMeters = 35;

  /// Fixes further apart than this in time belong to separate trips: the gap
  /// is a parked phone or a killed app, not travel, so the jump between the
  /// two fixes must never be counted as distance.
  static const Duration maxFixGap = Duration(minutes: 30);

  /// A longer outage may still be travel (a tunnel, a long underground
  /// stretch), but it is only bridged up to this limit **and** only when the
  /// motion signal proves the device kept moving through the blackout.
  static const Duration maxBridgedGap = Duration(hours: 2);

  /// Speeds above this (km/h) are GPS glitches, not travel: neither a reported
  /// Doppler speed nor a step that implies such a speed may poison the day's
  /// metrics.
  static const double maxPlausibleSpeedKmh = 180;

  /// The stricter ceiling for the **gap-recovery** pass lives in
  /// [GapRecoveryService.maxPlausibleSpeedKmh]: the straight line between the
  /// last fix before a GPS outage and the first fix after it is only added
  /// back to today's distance when dividing it by the elapsed time suggests a
  /// plausible drive. A bigger implied speed means the jump is a location
  /// error (or travel that plausibly did *not* happen in the gap), never
  /// recovered distance.

  /// A step is only judged by its implied speed when the fix interval is long
  /// enough for that average to mean anything; below this (sub-second samples)
  /// the receiver's own speed report is the only meaningful guard.
  static const Duration minSpeedSampleWindow = Duration(seconds: 1);

  /// While tracking, the day's metrics are flushed to disk on this cadence even
  /// when no fix arrives, so a crash or a battery pull loses seconds at most.
  static const Duration persistInterval = Duration(seconds: 10);

  double _dayKm = 0;
  double _dayMaxKmh = 0;
  double _currentKmh = 0;
  DateTime _day = DailyGpsSummary.dayOf(DateTime.now());

  /// Last accepted fix, kept as primitives so it can be persisted and restored
  /// (see `DailyGpsSummary.lastLatitude`).
  double _lastLat = 0;
  double _lastLon = 0;
  DateTime? _lastAt;

  /// True once this run accepted at least one fix (i.e. there is something
  /// worth writing back).
  bool _dirty = false;

  StreamSubscription<Position>? _subscription;
  bool _tracking = false;

  /// True while the platform has reported the location pipeline down (the OS
  /// provider switched off, or the position stream failed). Cleared by the
  /// first *accepted* fix — the "GPS is back" moment the gap-recovery pass
  /// judges — and by [detach].
  bool _outage = false;

  /// The OS provider-status subscription opened by [attach]; cancelled on
  /// [detach] so a stopped tracker can never arm a recovery window.
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;

  /// Fires after every accepted fix (and at the midnight rollover) so consumers
  /// repaint today's numbers immediately instead of only on a toggle.
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Backs up the local-midnight reset when no fix happens to cross it.
  Timer? _midnightTimer;

  /// Periodic disk flush while tracking (crash resilience).
  Timer? _persistTimer;

  /// True while the position stream is attached.
  bool get isTracking => _tracking;

  /// Total distance recorded today (past sessions + this run), in km.
  double get totalDistanceKm => _dayKm;

  /// Highest speed recorded today, in km/h.
  double get maxSpeedKmh => _dayMaxKmh;

  /// Speed of the most recent accepted fix, in km/h.
  double get currentSpeedKmh => _currentKmh;

  /// Emits after every accepted fix, and after the midnight rollover, so
  /// readouts repaint immediately instead of only when the toggle is flipped.
  Stream<void> get changes => _changes.stream;

  /// Re-seeds today's tallies from the day's persisted summary, so a restart
  /// or app foreground never "loses" the morning's tracking. Safe to call at
  /// any time; requires no platform channels.
  ///
  /// Also performs the lazy midnight reset: counters are zeroed whenever the
  /// calendar day has moved on, even if no fix arrived to trigger a rollover.
  Future<void> resyncFromStore() async {
    final DateTime today = DailyGpsSummary.dayOf(DateTime.now());
    if (today != _day) {
      await _rolloverTo(today);
      return;
    }
    final DailyGpsSummary? stored = store.summaryFor(today);
    _dayKm = stored?.totalKm ?? 0;
    _dayMaxKmh = stored?.maxSpeedKmh ?? 0;
    _restoreLastPoint(stored);
  }

  /// Resolves the runtime location permission for [locations].
  ///
  /// Returns the typed reason tracking cannot start (GPS off, permission
  /// denied / permanently denied, or a platform channel error), or
  /// [TrackStartFailure.none] when tracking may proceed. Never throws.
  Future<TrackStartFailure> resolveStartFailure(LocationService locations) async {
    try {
      if (!await locations.isServiceEnabled()) {
        return TrackStartFailure.locationServiceDisabled;
      }
      LocationPermission permission = await locations.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await locations.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return TrackStartFailure.permissionDenied;
      }
      if (permission == LocationPermission.deniedForever) {
        return TrackStartFailure.permissionDeniedForever;
      }
      return TrackStartFailure.none;
    } catch (_) {
      // Platform channel unavailable (tests / unsupported platform).
      return TrackStartFailure.platformError;
    }
  }

  /// Records that the location pipeline has been observed down — the OS
  /// provider was switched off (see the service-status listener in [attach])
  /// or the platform stream failed — so everything skipped in between is
  /// judged by the gap-recovery pass when fixes come back instead of being
  /// written off as a dead silence. Idempotent; cleared by the next accepted
  /// fix and by [detach].
  void noteOutage() => _outage = true;

  /// Attaches [source], joins the OS provider-status feed (when given), the
  /// motion signal and arms the rollover and persistence timers. Callers must
  /// resolve location access beforehand.
  ///
  /// [serviceStatus] is the tracker's "GPS switched off/on" feed: a
  /// [ServiceStatus.disabled] event arms gap recovery (see [noteOutage]) so
  /// the distance skipped while the provider was off is measured — not
  /// silently dropped — when fixes resume.
  Future<void> attach(
    Stream<Position> source, {
    Stream<ServiceStatus>? serviceStatus,
  }) async {
    _subscription = source.listen(recordPosition);
    _tracking = true;
    _listenForProviderOutages(serviceStatus);
    try {
      await _motion.start();
    } catch (_) {
      // Movement sensing is best-effort: plain fix-to-fix tracking continues.
    }
    _scheduleMidnightRollover();
    _startPersistTimer();
  }

  /// Opens the provider-status listener that arms gap recovery. Failures are
  /// swallowed: without a usable status feed the tracker simply keeps the
  /// conservative plain-fix rules and the motion-signal bridge, and stream
  /// failures still arm the same window through the caller's `onError` hook.
  void _listenForProviderOutages(Stream<ServiceStatus>? serviceStatus) {
    unawaited(_serviceStatusSubscription?.cancel());
    _serviceStatusSubscription = null;
    if (serviceStatus == null) return;
    _serviceStatusSubscription = serviceStatus.listen(
      (ServiceStatus status) {
        if (status == ServiceStatus.disabled) noteOutage();
      },
      onError: (Object _, StackTrace _) {
        // No status feed (tests, or a platform without one): the ordinary
        // bridging rules above remain in force.
      },
    );
  }

  /// Detaches the stream, releases the motion signal and persists the day.
  ///
  /// Tallies are kept in memory afterwards so readouts do not drop to zero; the
  /// next [attach] re-seeds them from the store.
  Future<void> detach() async {
    final bool hasAnything =
        _tracking || _dirty || _dayKm > 0 || _dayMaxKmh > 0;
    _tracking = false;
    _cancelTimers();
    await _subscription?.cancel();
    _subscription = null;
    unawaited(_serviceStatusSubscription?.cancel());
    _serviceStatusSubscription = null;
    // A stopped session's outage window never carries over: the next session
    // may start days later, and its first fix must follow the ordinary rules.
    // Before closing it, the inertial estimator gets one last chance to vouch
    // for the span — no fix will ever come to judge this window, and dead
    // reckoning is the only witness left (a GPS-off drive that never came back
    // would otherwise be written off entirely).
    final DateTime? openOutageFrom = _outage ? _lastAt : null;
    _outage = false;
    if (openOutageFrom != null) {
      _applyInertialOutage(openOutageFrom, DateTime.now());
    }
    await _motion.stop();
    _notify();
    if (!hasAnything) return;
    await _saveDay(_day);
  }

  /// Re-points the live subscription at [source] without touching anything
  /// else — used when the power mode changes and the platform stream has to be
  /// re-opened at a different accuracy (see
  /// `LocationService.backgroundTrackingLocationSettings`). Today's tallies,
  /// the last accepted fix, the outage window and the timers all survive, so a
  /// foreground ↔ background switch mid-trip loses no state.
  Future<void> reopen(Stream<Position> source) async {
    final StreamSubscription<Position>? previous = _subscription;
    _subscription = null;
    if (previous != null) {
      try {
        await previous.cancel();
      } catch (_) {
        // A failing teardown must not block the replacement stream.
      }
    }
    // Detached while the old stream was being cancelled: stay detached rather
    // than resurrecting a subscription nobody will ever stop again.
    if (!_tracking) return;
    _subscription = source.listen(recordPosition);
  }

  /// Writes today's metrics to disk right now — no-op when nothing was
  /// recorded since the last write — so a battery-optimisation kill immediately
  /// after the app is backgrounded cannot drop an accepted position.
  Future<void> flush() async {
    if (!_dirty) return;
    await _persistSafely();
  }

  /// Consumes one fix: filters noise, rolls over at midnight, and accumulates
  /// distance into the current day.
  ///
  /// Each accepted fix is written to local storage straight away (best effort)
  /// and announced on [changes], so a crash loses at most one fix and the UI
  /// never shows stale numbers. While tracking, a periodic flush also runs
  /// (see [persistInterval]) so a long outage cannot stall persistence.
  void recordPosition(Position position) {
    // Only trust fixes with a real accuracy measurement that is good enough.
    if (!position.hasAccuracy || position.accuracy > maxAccuracyMeters) return;

    // Roll into a new calendar day when the tracking ran past midnight.
    final DateTime positionDay = DailyGpsSummary.dayOf(position.timestamp);
    if (positionDay != _day) {
      unawaited(_persistSafely()); // Persist yesterday before switching.
      _day = positionDay;
      final DailyGpsSummary? stored = store.summaryFor(_day);
      _dayKm = stored?.totalKm ?? 0;
      _dayMaxKmh = stored?.maxSpeedKmh ?? 0;
      _restoreLastPoint(stored);
    }

    // Doppler speed, with impossible spikes (a GPS glitch reports hundreds of
    // km/h in a stationary car) ignored rather than trusted.
    final double reportedKmh =
        position.hasSpeed ? math.max(0, position.speed * 3.6) : 0;
    final bool speedPlausible = reportedKmh <= maxPlausibleSpeedKmh;
    if (speedPlausible) {
      _currentKmh = reportedKmh;
    }
    // Every fix also fuses its speed as movement evidence for the bridge.
    if (position.hasSpeed) {
      _motion.observeSpeed(position.speed);
    }

    final DateTime? lastAt = _lastAt;
    final double lastLat = _lastLat;
    final double lastLon = _lastLon;
    _lastAt = position.timestamp;
    _lastLat = position.latitude;
    _lastLon = position.longitude;
    _dirty = true;

    // An accepted fix is the end of the outage, so judge the skipped span
    // while the window is still known. A fix that the accuracy gate already
    // rejected never gets here — a poor-quality "first fix back" keeps the
    // window open for the next, usable one.
    final bool afterOutage = _outage;
    _outage = false;

    if (lastAt != null) {
      final Duration gap = position.timestamp.difference(lastAt).abs();
      final double stepKm = haversineKm(
        lastLat,
        lastLon,
        position.latitude,
        position.longitude,
      );
      // Across an outage the gap *is* the measurement: the Haversine span
      // between the last known position and the new one is recovered only
      // when it implies a plausible drive (see [GapRecoveryService]), and the
      // inertial estimate may vouch for the window when the crossing itself
      // is refused. Every other step follows the ordinary fix-to-fix rules.
      final double countedKm = afterOutage
          ? _outageRecoveryKm(stepKm, gap, lastAt, position.timestamp)
          : (stepKm * 1000 >= minStepMeters &&
                  _countsAsTravel(stepKm, gap, lastAt))
              ? stepKm
              : 0.0;
      if (countedKm > 0) {
        _dayKm += countedKm;
      }
    }

    if (speedPlausible) {
      _dayMaxKmh = math.max(_dayMaxKmh, _currentKmh);
    }
    unawaited(_persistSafely());
    _notify();
  }

  /// Whether the geometric step between the last accepted fix and this one is
  /// travel that belongs in today's total.
  ///
  /// Steps that span a *known* outage never reach this — they are judged only
  /// by [_recoversGap]. For everything else:
  ///
  /// * A physically impossible step (one implying a speed above
  ///   [maxPlausibleSpeedKmh]) is a GPS jump, never travel.
  /// * A gap within [maxFixGap] is normal sampling — the fix-to-fix distance
  ///   already bridges short tunnel outages, because the session is never
  ///   paused or reset while the stream is silent.
  /// * A longer gap is a real outage and is bridged only up to [maxBridgedGap]
  ///   and only when the motion signal saw the device moving after [since].
  bool _countsAsTravel(double stepKm, Duration gap, DateTime since) {
    if (gap >= minSpeedSampleWindow) {
      final double impliedKmh = stepKm / (gap.inMilliseconds / 3600000.0);
      if (!impliedKmh.isFinite || impliedKmh > maxPlausibleSpeedKmh) {
        return false;
      }
    }
    if (gap <= maxFixGap) return true;
    if (gap > maxBridgedGap) return false;
    final DateTime? motionAt = _motion.lastMotionAt;
    return motionAt != null && motionAt.isAfter(since);
  }

  /// How much distance an **outage** span ([noteOutage]) adds back to the
  /// day's total. The geometric crossing is judged by [GapRecoveryService]
  /// (implied average speed ≤ its ceiling); when that refuses — a bad first
  /// fix back, or an out-and-back through a tunnel whose endpoints nearly
  /// coincide — the inertial estimate for the same window is judged by the
  /// same rule and, if plausible, is what gets appended. Both witnesses must
  /// clear the speed gate; neither clearing it means the span is written off.
  double _outageRecoveryKm(
    double stepKm,
    Duration gap,
    DateTime from,
    DateTime to,
  ) {
    final GapVerdict crossing = _gapRecovery.judge(gap: gap, crossingKm: stepKm);
    if (crossing.recovered && stepKm * 1000 >= minStepMeters) {
      return crossing.recoveredKm;
    }
    final GapVerdict inertial = _gapRecovery.judge(
      gap: gap,
      crossingKm: _deadReckoning.displacementKmBetween(from, to),
    );
    return inertial.recoveredKm;
  }

  /// Appends the inertial estimate of an outage window that will never see a
  /// resuming fix (the session ended while the outage was still open). Judged
  /// by the same plausible-speed rule as every other recovery, and marked
  /// dirty so the final persist picks it up.
  void _applyInertialOutage(DateTime from, DateTime to) {
    final GapVerdict verdict = _gapRecovery.judge(
      gap: to.difference(from),
      crossingKm: _deadReckoning.displacementKmBetween(from, to),
    );
    if (verdict.recoveredKm <= 0) return;
    _dayKm += verdict.recoveredKm;
    _dirty = true;
  }

  /// Re-seeds the last accepted fix from [stored] so a restarted service can
  /// resume an in-progress trip instead of starting the next fix from scratch.
  /// A live fix always wins.
  void _restoreLastPoint(DailyGpsSummary? stored) {
    if (_lastAt != null) return;
    final double? lat = stored?.lastLatitude;
    final double? lon = stored?.lastLongitude;
    final DateTime? at = stored?.lastFixAt;
    if (lat == null || lon == null || at == null) return;
    _lastLat = lat;
    _lastLon = lon;
    _lastAt = at;
  }

  /// Never throws: a failed write must not take down the position listener.
  Future<void> _persistSafely() async {
    try {
      await _saveDay(_day);
    } catch (_) {
      // Storage unavailable (closed box / full disk); the next fix retries.
    }
  }

  /// Announces a metric change to `changes` listeners.
  void _notify() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }

  /// Resets the counters at local midnight even when no fix crosses it
  /// (stationary phone ⇒ the filtered stream stays silent all night).
  void _scheduleMidnightRollover() {
    _midnightTimer?.cancel();
    final DateTime now = DailyGpsSummary.dayOf(DateTime.now());
    final DateTime nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(
      nextMidnight.difference(DateTime.now()),
      () {
        unawaited(_midnightRollover());
      },
    );
  }

  /// Flushes the day's metrics on a fixed cadence while tracking, so an app
  /// kill (or a battery pull) between fixes loses seconds of travel at most.
  void _startPersistTimer() {
    _persistTimer?.cancel();
    _persistTimer = Timer.periodic(flushEvery, (_) {
      if (!_dirty) return;
      unawaited(_persistSafely());
    });
  }

  void _cancelTimers() {
    _midnightTimer?.cancel();
    _midnightTimer = null;
    _persistTimer?.cancel();
    _persistTimer = null;
  }

  /// Finalises the finished day and zeroes the counters for the new one.
  Future<void> _midnightRollover() async {
    final DateTime today = DailyGpsSummary.dayOf(DateTime.now());
    if (today != _day) {
      await _rolloverTo(today);
    }
    if (_tracking) {
      _scheduleMidnightRollover(); // Arm the following midnight.
    }
    _notify();
  }

  /// Switches the running totals to [newDay], flushing the finished day first
  /// when this run measured something (never overwrites a stored day with a
  /// fresh service's zeroes).
  Future<void> _rolloverTo(DateTime newDay) async {
    final bool hasLiveSession =
        _tracking || _dirty || _dayKm > 0 || _dayMaxKmh > 0;
    if (hasLiveSession) {
      await _persistSafely(); // Best effort: never breaks the rollover.
    }
    _day = newDay;
    final DailyGpsSummary? stored = store.summaryFor(newDay);
    _dayKm = stored?.totalKm ?? 0;
    _dayMaxKmh = stored?.maxSpeedKmh ?? 0;
    _restoreLastPoint(stored);
    _currentKmh = 0;
  }

  Future<void> _saveDay(DateTime day) {
    final DateTime? lastAt = _lastAt;
    return store.save(
      DailyGpsSummary(
        date: day,
        totalKm: _dayKm,
        maxSpeedKmh: _dayMaxKmh,
        lastLatitude: lastAt == null ? null : _lastLat,
        lastLongitude: lastAt == null ? null : _lastLon,
        lastFixAt: lastAt,
      ),
    );
  }

  /// Great-circle distance between two coordinates, in kilometres (Haversine).
  static double distanceKmBetween(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) =>
      haversineKm(lat1, lon1, lat2, lon2);
}
