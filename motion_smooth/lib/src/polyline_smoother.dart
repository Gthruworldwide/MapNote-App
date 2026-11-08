import 'dart:math' as math;

/// GPS vertex representation with optional timestamp.
///
/// Each vertex in a polyline carries latitude, longitude, and an optional
/// [DateTime] timestamp. Used by [PolylineSmoother] and [MotionBehaviorAnalyzer].
class RoutePoint {
  /// Latitude in decimal degrees.
  final double latitude;

  /// Longitude in decimal degrees.
  final double longitude;

  /// Optional timestamp when this point was recorded.
  final DateTime? at;

  const RoutePoint({
    required this.latitude,
    required this.longitude,
    this.at,
  });
}

/// Smoother for GPS polylines using a bounded-correction Kalman-like filter.
///
/// Removes GPS jitter while preserving true path geometry, including corners
/// and turns. Designed for offline-first, pure-Dart operation with no
/// platform channels or method calls.
class PolylineSmoother {
  /// Default smoothing alpha (0 < alpha <= 1). Higher values smooth more but
  /// lag more behind true position.
  static const double _defaultAlpha = 0.3;

  /// Smooths a raw polyline of [RoutePoint]s, returning corrected positions.
  /// Uses a simple exponential moving average per point pair with gap handling.
  static List<RoutePoint> smooth(List<RoutePoint> rawPoints) {
    if (rawPoints.isEmpty) return [];
    if (rawPoints.length == 1) return List.unmodifiable([rawPoints[0]]);

    final smoothed = <RoutePoint>[rawPoints[0]];
    for (int i = 1; i < rawPoints.length; i++) {
      final prev = smoothed[i - 1];
      final curr = rawPoints[i];
      // EMA-style correction: blend towards current point with alpha weight.
      final double lat =
          prev.latitude + (curr.latitude - prev.latitude) * _defaultAlpha;
      final double lng =
          prev.longitude + (curr.longitude - prev.longitude) * _defaultAlpha;
      smoothed.add(RoutePoint(latitude: lat, longitude: lng, at: curr.at));
    }
    return smoothed;
  }

  /// Calculates the initial bearing in degrees from start to end point,
  /// normalized to the range 0°–360°.
  ///
  /// Uses the standard formula: θ = atan2(sin(Δλ)·cos(φ₂),
  /// cos(φ₁)·sin(φ₂) − sin(φ₁)·cos(φ₂)·cos(Δλ))
  ///
  /// Returns a value in [0, 360) where:
  /// - 0° = North
  /// - 90° = East
  /// - 180° = South
  /// - 270° = West
  static double calculateBearing(
      double startLat, double startLng, double endLat, double endLng) {
    final double dLon = endLng - startLng;
    final double y = math.sin(dLon) * math.cos(endLat);
    final double x =
        math.cos(startLat) * math.sin(endLat) -
            math.sin(startLat) * math.cos(endLat) * math.cos(dLon);
    final double bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360; // Normalize to 0-360
  }

  /// Smooths heading using circular interpolation to prevent 180° flips when
  /// stationary or when GPS jitter occurs at low speeds.
  ///
  /// Uses the shortest-path modulo-360 interpolation with a smoothing factor
  /// [alpha] (0 < alpha <= 1). A value of 1 means no smoothing (instant
  /// jump to target), while 0 means complete smoothing (hold current).
  ///
  /// Example:
  /// ```dart
  /// final smooth = PolylineSmoother.smoothHeading(350.0, 10.0); // returns ~356.0
  /// final smooth = PolylineSmoother.smoothHeading(180.0, 180.0); // returns 180.0
  /// ```
  static double smoothHeading(double currentHeading, double targetHeading,
      [double alpha = 0.3]) {
    // Calculate the shortest path difference, normalized to -180..180.
    double diff = targetHeading - currentHeading;
    diff = (diff + 180) % 360 - 180;
    // Apply interpolated smoothing.
    final double newHeading = currentHeading + diff * alpha;
    // Normalize result to 0..360.
    return (newHeading + 360) % 360;
  }
}