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

  double _dayKm = 0;
  double _dayMaxKmh = 0;
  double _currentKmh = 0;
  DateTime _day = DailyGpsSummary.dayOf(DateTime.now());
  Position? _last;
  StreamSubscription<Position>? _subscription;
  bool _tracking = false;

  /// True while the position stream is attached.
  bool get isTracking => _tracking;

  /// Total distance recorded today (past sessions + this run), in km.
  double get totalDistanceKm => _dayKm;

  /// Highest speed recorded today, in km/h.
  double get maxSpeedKmh => _dayMaxKmh;

  /// Speed of the most recent accepted fix, in km/h.
  double get currentSpeedKmh => _currentKmh;

  /// Re-seeds today's tallies from the stored day, so an app restart never
  /// "loses" the morning's motion. Requires no platform channels.
  Future<void> resyncFromStore() async {
    final DateTime today = DailyGpsSummary.dayOf(DateTime.now());
    final DailyGpsSummary? stored = dailyStore.summaryFor(today);
    _day = today;
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
      source = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: minStepMeters,
        ),
      );
    }

    _subscription = source.listen(
      recordPosition,
      onError: (Object _) {
        // A single bad fix must not kill tracking.
      },
    );
    _tracking = true;
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
    await _subscription?.cancel();
    _subscription = null;
    if (!hasAnything) return;
    await _saveDay(_day);
  }

  /// Consumes one fix: filters noise, rolls over at midnight, and accumulates
  /// distance into the current day.
  void recordPosition(Position position) {
    // Only trust fixes with a real accuracy measurement that is good enough.
    if (!position.hasAccuracy || position.accuracy > maxAccuracyMeters) return;

    // Roll into a new calendar day when tracking ran past midnight.
    final DateTime positionDay = DailyGpsSummary.dayOf(position.timestamp);
    if (positionDay != _day) {
      unawaited(_saveDay(_day)); // Persist yesterday before switching.
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
      return;
    }

    final double stepKm = haversineKm(
      last.latitude,
      last.longitude,
      position.latitude,
      position.longitude,
    );
    if (stepKm * 1000 >= minStepMeters) {
      _dayKm += stepKm;
    }
    _dayMaxKmh = math.max(_dayMaxKmh, _currentKmh);
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