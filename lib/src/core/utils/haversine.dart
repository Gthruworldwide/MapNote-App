import 'dart:math' as math;

import '../../data/models/place.dart';

/// Utility class for calculating distances between geographic coordinates
/// using the Haversine formula. 100% offline, no APIs.
class Haversine {
  /// Earth's radius in kilometers.
  static const double _earthRadiusKm = 6371.0;

  /// Calculates the distance between two coordinates in kilometers
  /// using the Haversine formula.
  static double distanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusKm * c;
  }

  /// Converts degrees to radians.
  static double _toRadians(double degrees) {
    return degrees * (math.pi / 180.0);
  }

  /// Returns the top [limit] nearest stations to [currentPlace] from [allPlaces].
  ///
  /// Filters out [currentPlace] itself and returns only default stations
  /// (isDefault == true), sorted by distance ascending.
  static List<Place> getNearestStations(
    Place currentPlace,
    List<Place> allPlaces, {
    int limit = 3,
  }) {
    final List<({Place place, double distance})> candidates = [];

    for (final Place place in allPlaces) {
      // Skip the current place itself
      if (place.id == currentPlace.id) continue;
      // Only consider default stations
      if (place.isDefault != true) continue;

      final double distance = distanceKm(
        currentPlace.latitude,
        currentPlace.longitude,
        place.latitude,
        place.longitude,
      );

      candidates.add((place: place, distance: distance));
    }

    // Sort by distance ascending
    candidates.sort((a, b) => a.distance.compareTo(b.distance));

    // Return top limit nearest
    return candidates
        .take(limit)
        .map((c) => c.place)
        .toList(growable: false);
  }
}