import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../core/utils/geo_distance.dart';
import '../data/local/auto_motion_data_source.dart';
import '../data/models/daily_gps_summary.dart';
import 'location_service.dart';

/// Phase-1 AutoMotion tracker: while enabled it records today's total
/// distance (km), the current speed and today's max speed (km/h), and stores
/// one daily summary (keyed `YYYY-MM-DD`) in the `auto_motion_box` Hive box.
///
/// The logic mirrors [GpsTrackerService] (same Haversine measurement and noise
/// filtering) but keeps a fully independent lifecycle, storage box and
/// settings switch, so the two features can evolve separately.
class AutoMotionService {
  AutoMotionService({required this.dailyStore});

  /// Persistence for daily metrics.
  final AutoMotionDataSource dailyStore;

  /// Fixes that moved less than this many metres are GPS jitter, not travel.
  static const int minStepMeters = 3;

  /// Fixes worse than this horizontal accuracy (metres) are dropped.
  static const double maxAccuracyMeters = 35;

  /// Fixes further apart than this in time belong to separate trips: the gap
  /// is a parked phone or a killed app, not travel, so the jump between the
  /// two fixes must never be counted as distance.
  static const Duration maxFixGap = Duration(minutes: 30);

  double _dayKm = 0;
  double _dayMaxKmh = 0;
  double _currentKmh = 0;
  DateTime _day = DailyGpsSummary.dayOf(DateTime.now());
  Position? _last;
  StreamSubscription<Position>? _subscription;
  bool _tracking = false;

  /// Fires after every accepted fix (and at the midnight rollover) so widgets
  /// can repaint today's numbers immediately instead of waiting for a toggle.
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Backs up the local-midnight reset when no fix happens to cross it.
  Timer? _midnightTimer;

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
    } else {
      final LocationService loc = locations ?? const LocationService();
      try {
        if (!await loc.isServiceEnabled()) return false;
        final LocationPermission permission = await loc.checkPermission();
        if (permission == LocationPermission.denied) {
          final LocationPermission next = await loc.requestPermission();
          if (next == LocationPermission.denied ||
              next == LocationPermission.deniedForever) {
            return false;
          }
        } else if (permission == LocationPermission.deniedForever) {
          return false;
        }
      } catch (_) {
        // Platform channel unavailable (tests / unsupported platform).
        return false;
      }
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
    _scheduleMidnightRollover();
    return true;
  }

  /// Stops tracking and persists the day's metrics to Hive (flushed).
  ///
  /// Tallies stay in memory afterwards so the dashboard card does not drop to
  /// zero; the next [start] re-seeds them from the store.
  Future<void> stop() async {
    final bool hasAnything =
        _tracking || _last != null || _dayKm > 0 || _dayMaxKmh > 0;
    _tracking = false;
    _midnightTimer?.cancel();
    _midnightTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    _notify();
    if (!hasAnything) return;
    await _saveDay(_day);
  }

  /// Consumes one fix: filters noise, rolls over at midnight, and accumulates
  /// distance into the current day.
  ///
  /// Each accepted fix is written to local storage straight away (best effort)
  /// and announced on [changes], so a crash loses at most one fix and the UI
  /// never shows stale numbers.
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
    }

    _currentKmh = position.hasSpeed
        ? math.max(0, position.speed * 3.6)
        : 0;

    final Position? last = _last;
    _last = position;
    if (last == null) {
      // First fix of this run: nothing to accumulate distance against, but the
      // speed still counts towards the day's maximum.
      _dayMaxKmh = math.max(_dayMaxKmh, _currentKmh);
      unawaited(_persistSafely());
      _notify();
      return;
    }

    // A long silence (device parked, OS suspended us, app restored from the
    // background) is not travel: keep the speed but drop the jump.
    final bool withinTrip =
        position.timestamp.difference(last.timestamp).abs() <= maxFixGap;
    if (withinTrip) {
      final double stepKm = haversineKm(
        last.latitude,
        last.longitude,
        position.latitude,
        position.longitude,
      );
      if (stepKm * 1000 >= minStepMeters) {
        _dayKm += stepKm;
      }
    }
    _dayMaxKmh = math.max(_dayMaxKmh, _currentKmh);
    unawaited(_persistSafely());
    _notify();
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
        _tracking || _last != null || _dayKm > 0 || _dayMaxKmh > 0;
    if (hasLiveSession) {
      await _persistSafely(); // Best effort: never breaks the rollover.
    }
    _day = newDay;
    final DailyGpsSummary? stored = dailyStore.summaryFor(newDay);
    _dayKm = stored?.totalKm ?? 0;
    _dayMaxKmh = stored?.maxSpeedKmh ?? 0;
    _currentKmh = 0;
  }

  Future<void> _saveDay(DateTime day) {
    return dailyStore.save(
      DailyGpsSummary(
        date: day,
        totalKm: _dayKm,
        maxSpeedKmh: _dayMaxKmh,
      ),
    );
  }
}