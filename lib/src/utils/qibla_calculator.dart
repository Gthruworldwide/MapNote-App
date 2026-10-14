import 'dart:math' as math;

/// Pure Dart helper to compute Qibla bearing relative to True North (0°..360°).
///
/// Uses standard spherical trigonometry initial-bearing formula given the device's
/// current GPS latitude/longitude and the fixed Ka'bah (Mecca) coordinates:
///   Latitude: 21.422487° N
///   Longitude: 39.826206° E
///
/// The returned angle is measured clockwise from True North, i.e. 0° = North,
/// 90° = East, 180° = South, 270° = West.
class QiblaCalculator {
  /// Fixed Ka'bah (Mecca) coordinates.
  static const double meccaLat = 21.422487;
  static const double meccaLon = 39.826206;

  /// Earth's radius in kilometres (used only for conceptual completeness;
  /// the bearing formula is radius-invariant).
  static const double earthRadiusKm = 6371.0;

  /// Calculates the Qibla bearing from the given GPS position to Mecca.
  ///
  /// Returns an angle in degrees [0, 360) measured clockwise from True North.
  /// Returns `null` if the input latitudes are out of valid range [-90, 90].
  static double? bearingFrom(double lat, double lon) {
    if (lat < -90 || lat > 90 || meccaLat < -90 || meccaLat > 90) return null;

    final lat1 = _toRadians(lat);
    final lon1 = _toRadians(lon);
    final lat2 = _toRadians(meccaLat);
    final lon2 = _toRadians(meccaLon);

    final deltaLon = lon2 - lon1;

    final y = math.sin(deltaLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLon);

    final initialBearing = math.atan2(y, x);
    final bearingDeg = (_toDegrees(initialBearing) + 360) % 360;

    return bearingDeg;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  static double _toDegrees(double radians) => radians * 180 / math.pi;
}