import '../core/utils/geo_distance.dart';

/// Why a single GPS fix was refused, for coarse diagnostics only.
///
/// The enum never carries a coordinate, timestamp or raw provider value, so a
/// rejection can be counted in the local health log without leaking a place.
enum GpsSampleRejection {
  none,
  nonFiniteCoordinate,
  outOfRangeCoordinate,
  nonFiniteTime,
  backwardsTimestamp,
  nonFiniteMotion,
  impossibleJump,
}

/// Strict, pure validation for incoming GPS samples.
///
/// Both the daily GPS tracker and AutoMotion feed every fix through
/// [DailyTrackEngine.recordPosition], so one check here protects both paths
/// from NaN coordinates, clocks that move backwards and physically impossible
/// teleports (for example Cairo to New York in one second).
///
/// The validator is deliberately stateless: the caller supplies the previous
/// accepted fix. That makes it trivially testable and means restoring a trip
/// from Hive restores the validation baseline too.
class GpsSampleValidator {
  const GpsSampleValidator({
    this.maxPlausibleKmh = 160.0,
    this.minJumpMeters = 100.0,
    this.minElapsedForJumpCheck = const Duration(seconds: 1),
  });

  /// Highest speed considered physically possible for a road vehicle.
  ///
  /// 160 km/h is above any legal speed limit and leaves room for a fast train;
  /// a larger implied speed is a provider glitch, not travel.
  final double maxPlausibleKmh;

  /// Ignore sub-100 m apparent jumps: at short ranges ordinary GPS noise can
  /// imply an impossible instantaneous speed without any real movement.
  final double minJumpMeters;

  /// Only judge implied speed once the two fixes are at least this far apart
  /// in time. Below it the average is meaningless and ordinary receiver jitter
  /// would look supersonic. Matches `DailyTrackEngine.minSpeedSampleWindow`.
  final Duration minElapsedForJumpCheck;

  GpsSampleRejection validate({
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    required double? accuracyMeters,
    required double? speedMetersPerSecond,
    DateTime? previousTimestamp,
    double? previousLatitude,
    double? previousLongitude,
  }) {
    if (!latitude.isFinite || !longitude.isFinite) {
      return GpsSampleRejection.nonFiniteCoordinate;
    }
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      return GpsSampleRejection.outOfRangeCoordinate;
    }
    if (accuracyMeters != null &&
        (!accuracyMeters.isFinite || accuracyMeters < 0)) {
      return GpsSampleRejection.nonFiniteMotion;
    }
    if (speedMetersPerSecond != null &&
        (!speedMetersPerSecond.isFinite || speedMetersPerSecond < 0)) {
      return GpsSampleRejection.nonFiniteMotion;
    }

    previousTimestamp ??= _unsetTime;
    final int micros = timestamp.microsecondsSinceEpoch;
    final int previousMicros = previousTimestamp.microsecondsSinceEpoch;
    if (previousMicros >= 0 && micros < previousMicros) {
      return GpsSampleRejection.backwardsTimestamp;
    }

    if (previousLatitude != null &&
        previousLongitude != null &&
        previousMicros >= 0) {
      final double stepKm = haversineKm(
        previousLatitude,
        previousLongitude,
        latitude,
        longitude,
      );
      if (stepKm * 1000 >= minJumpMeters) {
        final Duration elapsed =
            Duration(microseconds: micros - previousMicros);
        if (elapsed >= minElapsedForJumpCheck) {
          final double elapsedHours = elapsed.inMicroseconds / 3600000000.0;
          if (stepKm / elapsedHours > maxPlausibleKmh) {
            return GpsSampleRejection.impossibleJump;
          }
        }
      }
    }
    return GpsSampleRejection.none;
  }

  /// A sentinel meaning "no previous fix": a timestamp before the Unix epoch
  /// can never be produced by a real provider, so it is safe as a baseline.
  static final DateTime _unsetTime = DateTime.fromMillisecondsSinceEpoch(-1);
}
