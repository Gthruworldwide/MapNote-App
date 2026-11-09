import 'dart:math' as math;

/// A simple immutable pair of doubles, used as a replacement for math.Pair
/// which is not available in Dart 3.x.
final class _Pair<T1, T2> {
  final T1 first;
  final T2 second;
  const _Pair(this.first, this.second);
}

/// Planar Equirectangular Projection utilities for local tangent plane calculations.
///
/// Provides coordinate conversion between WGS-84 lat/lng and local East-North-Up (ENU)
/// projected coordinates, with bounding checks and distance estimation.
///
/// The equirectangular projection maps latitude $\phi$ and longitude $\lambda$ to
/// a 2D plane using:
/// $$x = \lambda - \lambda_0$$$$y = \phi - \phi_0$$
/// where $x$ is easting (km) and $y$ is northing (km), with 1 degree latitude
/// approximating 111.32 km and 1 degree longitude at latitude $\phi$ approximating
/// $111.32 \times \cos(\phi)$ km.
///
/// This projection preserves direction but distorts distance and area, making it
/// suitable for local tangent plane operations within ~100 km radius.
final class GeoMath {
  /// Earth's mean radius in kilometres.
  static const double earthRadiusKm = 6371.0;

  /// Degrees per metre in the north-south direction (approx constant).
  static const double degreesPerMetreNS = 1.0 / 111139.0;

  /// Degrees per metre in the east-west direction at the equator.
  static const double degreesPerMetreEWEquator = 1.0 / 111139.0;

  /// Creates a [GeoMath] instance for local projections centered at the given point.
  /// The projection origin is configured per-method call; this constructor is optional.
  const GeoMath();

  /// Converts WGS-84 latitude/longitude to local East-North-Up (ENU) projected coordinates.
  ///
  /// The output [easting] is in metres positive East of the central meridian,
  /// and [northing] is in metres positive North of the central parallel.
  ///
  /// - [lat]: Latitude in decimal degrees.
  /// - [lng]: Longitude in decimal degrees.
  /// - [centerLat]: Reference latitude for the projection (the projection origin).
  /// - [centerLng]: Reference longitude for the projection origin.
  ///
  /// Returns a [_Pair] of (easting, northing) in metres.
  ///
  /// The equirectangular approximation used:
  /// $$ \Delta\text{lat} = \text{lat} - \text{centerLat} $$
  /// $$ \Delta\text{lng} = \text{lng} - \text{centerLng} $$
  /// $$ \text{easting} = \Delta\text{lng} \times 111139.0 \times \cos(\text{centerLat}) \times \frac{\pi}{180} $$
  /// $$ \text{northing} = \Delta\text{lat} \times 111139.0 $$
  ///
  /// Error grows quadratically with distance from the center point. For typical
  /// GPS tracking use cases within 20 km radius, position error is typically < 10 m.
  /// For distances > 100 km, consider a proper conformal projection.
  _Pair<double, double> latLngToLocalXY(
      double lat, double lng, double centerLat, double centerLng) {
    final double dLat = lat - centerLat;
    final double dLng = lng - centerLng;
    // metres per degree at center latitude for east-west component
    const double metresPerDegLngAtEquator = 111139.0;
    final double metresPerDegLng =
        metresPerDegLngAtEquator * math.cos(centerLat * math.pi / 180.0);
    final double easting = dLng * metresPerDegLng * (180.0 / math.pi);
    final double northing = dLat * 111139.0 * (180.0 / math.pi);
    return _Pair<double, double>(easting, northing);
  }

  /// Converts local East-North-Up (ENU) projected coordinates back to WGS-84 lat/lng.
  ///
  /// The input [easting] is in metres positive East, and [northing] is in metres
  /// positive North relative to the projection origin.
  ///
  /// - [easting]: Offset in metres East of central meridian.
  /// - [northing]: Offset in metres North of central parallel.
  /// - [centerLat]: Reference latitude where projection originates.
  /// - [centerLng]: Reference longitude where projection originates.
  ///
  /// Returns a [_Pair] of (latitude, longitude) in decimal degrees.
  ///
  /// Inverse of [latLngToLocalXY], using:
  /// $$ \Delta\text{lat} = \text{northing} / 111139.0 \times (180.0 / \pi) $$
  /// $$ \Delta\text{lng} = \text{easting} / (111139.0 \times \cos(\text{centerLat}) \times (180.0 / \pi)) $$
  /// $$ \text{lat} = \text{centerLat} + \Delta\text{lat} $$
  /// $$ \text{lng} = \text{centerLng} + \Delta\text{lng} $$
  ///
  /// Accuracy is identical to [latLngToLocalXY] - suitable for local (< 20 km)
  /// operations. May drift for distances > 100 km from the projection origin.
  _Pair<double, double> localXYToLatLng(
      double easting, double northing, double centerLat, double centerLng) {
    final double dLat = northing / 111139.0 * (180.0 / math.pi);
    final double dLng = easting /
        (111139.0 * math.cos(centerLat * math.pi / 180.0) * (180.0 / math.pi));
    return _Pair<double, double>(centerLat + dLat, centerLng + dLng);
  }

  /// Calculates the planar (equirectangular) distance in metres between two
  /// local projected points.
  ///
  /// Uses Pythagorean theorem on the ENU metres:
  /// $$ d = \sqrt{(\Delta x)^2 + (\Delta y)^2} $$
  double planarDistanceMeters(
      double easting1, double northing1, double easting2, double northing2) {
    final double dx = easting2 - easting1;
    final double dy = northing2 - northing1;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Calculates the approximate geodesic distance in metres between two WGS-84
  /// coordinates using the equirectangular approximation.
  ///
  /// $$ d = R \times \sqrt{(\Delta\phi)^2 + (\cos\bar\phi \times \Delta\lambda)^2} $$
  /// where $R = 6371$ km, $\Delta\phi$ and $\Delta\lambda$ are in radians,
  /// and $\bar\phi$ is the mean latitude.
  ///
  /// Useful as a quick bounding check; for precise geodesy, use the Haversine formula.
  double geodesicDistanceMeters(
      double lat1, double lng1, double lat2, double lng2) {
    final double dLat = (lat2 - lat1) * math.pi / 180.0;
    final double dLng = (lng2 - lng1) * math.pi / 180.0;
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c * 1000.0; // metres
  }

  /// Returns the approximate degrees-per-metre convergence factor at the given latitude.
  /// This is the ratio of eastward metres-per-degree to northward metres-per-degree.
  double convergenceFactor(double latitude) {
    // At the equator (0°), convergence = cos(0) = 1
    // At 60°, convergence = cos(60°) = 0.5
    // At 90° (pole), convergence = cos(90°) = 0
    return math.cos(latitude * math.pi / 180.0);
  }
}
