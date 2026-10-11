import 'dart:math' as math;

/// Great-circle distance between two coordinates, in kilometres (Haversine).
///
/// Shared by the GPS tracker and AutoMotion service so both motion features
/// measure distance identically.
double haversineKm(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const double earthRadiusKm = 6371.0;
  final double dLat = _toRadians(lat2 - lat1);
  final double dLon = _toRadians(lon2 - lon1);
  final double a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(lat1)) *
          math.cos(_toRadians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * earthRadiusKm * math.asin(math.min(1.0, math.sqrt(a)));
}

double _toRadians(double degrees) => degrees * math.pi / 180;