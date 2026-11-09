import 'dart:math' as math;

/// Circular angle mathematics for bearing calculation and heading interpolation.
///
/// Provides robust 0°–360° bearing computation, circular interpolation to prevent
/// 180° flips, and signed angular difference for motion analysis.
///
/// All functions operate exclusively on floating-point degrees in the
/// range [0, 360). Results are always normalized modulo 360.
final class CircularMath {
  /// Normalizes any angle in degrees to the range [0, 360).
  static double normalize(double angle) => (angle % 360 + 360) % 360;

  /// Calculates the initial bearing in degrees from [lat1, lon1] to [lat2, lon2],
  /// normalized to the range [0, 360).
  ///
  /// Uses the standard spherical formula:
  /// $$ \theta = \text{atan2}(\sin\Delta\lambda \times \cos\phi_2,\;
  /// \cos\phi_1 \times \sin\phi_2 - \sin\phi_1 \times \cos\phi_2 \times \cos\Delta\lambda) $$
  ///
  /// - [lat1], [lon1]: Starting point in decimal degrees.
  /// - [lat2], [lon2]: Ending point in decimal degrees.
  ///
  /// Returns a value in [0, 360) where:
  /// - 0° = North
  /// - 90° = East
  /// - 180° = South
  /// - 270° = West
  static double calculateBearing(
      double lat1, double lon1, double lat2, double lon2) {
    final double dLon = lon2 - lon1;
    final double y = math.sin(dLon) * math.cos(lat2);
    final double x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final double bearing = math.atan2(y, x) * 180 / math.pi;
    return normalize(bearing);
  }

  /// Calculates the shortest-path signed angular difference in degrees from
  /// [deg1] to [deg2], range [-180, 180].
  ///
  /// A positive value indicates [deg2] is clockwise from [deg1];
  /// negative indicates counter-clockwise.
  ///
  /// Uses modulo-360 arithmetic:
  /// $$ \Delta = (\text{deg2} - \text{deg1} + 180) \bmod 360 - 180 $$
  static double angularDifference(double deg1, double deg2) {
    final double diff = (deg2 - deg1 + 180) % 360 - 180;
    return diff;
  }

  /// Smooths [currentHeading] toward [targetHeading] using circular
  /// interpolation with smoothing factor [alpha].
  ///
  /// Prevents 180° cross-direction flips when the target crosses the 0°/360°
  /// rollover boundary. The shortest angular path is always chosen.
  ///
  /// - [currentHeading]: Current bearing in degrees [0, 360).
  /// - [targetHeading]: Target bearing in degrees [0, 360).
  /// - [alpha]: Smoothing factor in (0, 1]. Higher values track faster but
  ///   may overshoot; lower values are smoother but lag.
  ///
  /// Returns the smoothed heading in [0, 360).
  ///
  /// Algorithm:
  /// 1. Compute shortest-path difference $\delta$ using the [-180, 180] range.
  /// 2. Apply interpolation: $new = current + \alpha \times \delta$
  /// 3. Normalize result to [0, 360).
  static double smoothHeading(double currentHeading, double targetHeading,
      {required double alpha}) {
    // Normalize both to [0, 360)
    final double c = normalize(currentHeading);
    final double t = normalize(targetHeading);
    // Compute shortest-path difference in [-180, 180]
    double diff = t - c;
    if (diff > 180) diff -= 360;
    if (diff <= -180) diff += 360;
    // Apply alpha smoothing
    final double newHeading = c + alpha * diff;
    return normalize(newHeading);
  }
}
