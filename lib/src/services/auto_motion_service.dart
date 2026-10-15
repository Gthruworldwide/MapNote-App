import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../core/utils/geo_distance.dart';
import '../data/local/auto_motion_data_source.dart';
import '../data/models/daily_gps_summary.dart';
import 'location_service.dart';
import 'motion_signal.dart';

/// Why the last [AutoMotionService.start] call could not begin tracking.
///
/// Surfaced to the UI so a refused start is never silent: the AutoMotion card
/// can tell the user whether GPS is off, permission was denied, permission is
/// permanently blocked, or the platform channel failed.
enum AutoMotionStartFailure {
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

/// Phase-1 AutoMotion tracker: while enabled it records today's total
/// distance (km), the current speed and today's max speed (km/h), and stores
/// one daily summary (keyed `YYYY-MM-DD`) in the `auto_motion_box` Hive box.
///
/// The logic mirrors [GpsTrackerService] (same Haversine measurement and noise
/// filtering) but keeps a fully independent lifecycle, storage box and
/// settings switch, so the two features can evolve separately.
class AutoMotionService {
  AutoMotionService({
    required this.dailyStore,
    MotionSignal? motion,
    this.flushEvery = persistInterval,
  }) : _motion = motion ?? const NoMotionSignal();

  /// Persistence for daily metrics.
  final AutoMotionDataSource dailyStore;

  /// Movement evidence for the dead-reckoning gap bridge (see
  /// [MotionSignal]); the no-op default keeps unit tests channel-free.
  final MotionSignal _motion;

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

  /// Reason the most recent [start] call failed, if it did.
  AutoMotionStartFailure _failure = AutoMotionStartFailure.none;

  /// Reason the most recent [start] call failed, or
  /// [AutoMotionStartFailure.none] when tracking is live / succeeded.
  AutoMotionStartFailure get failure => _failure;

  /// Fires after every accepted fix (and at the midnight rollover) so widgets
  /// can repaint today's numbers immediately instead of waiting for a toggle.
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Backs up the local-midnight reset when no fix happens to cross it.
  Timer? _midnightTimer;

  /// Periodic disk flush while tracking (crash resilience).
  Timer? _persistTimer;

  /// How often the periodic flush runs; defaults to [persistInterval] and is
  /// overridable so tests need not wait 10 s.
  final Duration flushEvery;

  /// True while the position stream is attached.
  bool get isTracking => _tracking;

  /// Total distance recorded today (past sessions + this run), in km.
  double get totalDistanceKm => _dayKm;

  /// Highest speed recorded today, in km/h.
  double get maxSpeedKmh => _dayMaxKmh;

  /// Speed of the most recent accepted fix, in km/h.
  double get currentSpeedKmh => _currentKmh;

  /// Emits after every accepted fix, and after the midnight rollover, so
  /// Settings / Home readouts repaint immediately instead of only when the
  /// toggle is flipped. Never errors and buffers nothing while unlistened.
  Stream<void> get changes => _changes.stream;

  /// Re-seeds today's tallies from the stored day, so an app restart never
  /// "loses" the morning's motion. Requires no platform channels.
  ///
  /// Also performs the lazy midnight reset: counters are zeroed whenever the
  /// calendar day has moved on, even if no fix arrived to trigger a rollover.
  Future<void> resyncFromStore() async {
    final DateTime today = DailyGpsSummary.dayOf(DateTime.now());
    if (today != _day) {
      await _rolloverTo(today);
      return;
    }
    final DailyGpsSummary? stored = dailyStore.summaryFor(today);
    _dayKm = stored?.totalKm ?? 0;
    _dayMaxKmh = stored?.maxSpeedKmh ?? 0;
    _restoreLastPoint(stored);
  }

  /// Starts listening for GPS fixes.
  ///
  /// [positions] overrides the geolocator stream (tests); otherwise permissions
  /// are checked through [locations] first. Returns whether the stream is live.
  Future<bool> start({
    LocationService? locations,
    Stream<Position>? positions,
  }) async {
    if (_tracking) return true;
    await resyncFromStore();

    final Stream<Position> source;
    if (positions != null) {
      source = positions;
      _failure = AutoMotionStartFailure.none;
    } else {
      final LocationService loc = locations ?? const LocationService();
      try {
        if (!await loc.isServiceEnabled()) {
          _failure = AutoMotionStartFailure.locationServiceDisabled;
          return false;
        }
        LocationPermission permission = await loc.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await loc.requestPermission();
        }
        if (permission == LocationPermission.denied) {
          _failure = AutoMotionStartFailure.permissionDenied;
          return false;
        }
        if (permission == LocationPermission.deniedForever) {
          _failure = AutoMotionStartFailure.permissionDeniedForever;
          return false;
        }
      } catch (_) {
        // Platform channel unavailable (tests / unsupported platform).
        _failure = AutoMotionStartFailure.platformError;
        return false;
      }
      _failure = AutoMotionStartFailure.none;
      // High accuracy, one fix per 10 m of movement; the wrapper re-opens the
      // platform stream if it errors or closes mid-session.
      source = loc.trackingPositionStream(
        onError: (Object _, StackTrace _) {
          // Reported by the reconnector; a single hiccup must not kill tracking.
        },
      );
    }

    _subscription = source.listen(recordPosition);
    _tracking = true;
    try {
      await _motion.start();
    } catch (_) {
      // Movement sensing is best-effort: plain fix-to-fix tracking continues.
    }
    _scheduleMidnightRollover();
    _startPersistTimer();
    return true;
  }

  /// Stops tracking and persists the day's metrics to Hive (flushed).
  ///
  /// Tallies stay in memory afterwards so the dashboard card does not drop to
  /// zero; the next [start] re-seeds them from the store.
  Future<void> stop() async {
    final bool hasAnything =
        _tracking || _dirty || _dayKm > 0 || _dayMaxKmh > 0;
    _tracking = false;
    _cancelTimers();
    await _subscription?.cancel();
    _subscription = null;
    await _motion.stop();
    _notify();
    if (!hasAnything) return;
    await _saveDay(_day);
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

    // Roll into a new calendar day when tracking ran past midnight.
    final DateTime positionDay = DailyGpsSummary.dayOf(position.timestamp);
    if (positionDay != _day) {
      unawaited(_persistSafely()); // Persist yesterday before switching.
      _day = positionDay;
      final DailyGpsSummary? stored = dailyStore.summaryFor(_day);
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

    if (lastAt != null) {
      final Duration gap = position.timestamp.difference(lastAt).abs();
      final double stepKm = haversineKm(
        lastLat,
        lastLon,
        position.latitude,
        position.longitude,
      );
      if (stepKm * 1000 >= minStepMeters &&
          _countsAsTravel(stepKm, gap, lastAt)) {
        _dayKm += stepKm;
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
    final DailyGpsSummary? stored = dailyStore.summaryFor(newDay);
    _dayKm = stored?.totalKm ?? 0;
    _dayMaxKmh = stored?.maxSpeedKmh ?? 0;
    _restoreLastPoint(stored);
    _currentKmh = 0;
  }

  Future<void> _saveDay(DateTime day) {
    final DateTime? lastAt = _lastAt;
    return dailyStore.save(
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
}