import 'dart:math' as math;

import '../../../../data/models/place.dart';
import '../entities/place_link_suggestion.dart';
import '../entities/trip_stop.dart';

/// Pure rule engine that proposes links between the day's trip stops and the
/// user's saved places.
///
/// It is deterministic and side-effect free: the same stops and places always
/// produce the same suggestions, so it is trivially unit-testable and can run
/// on every accepted fix without touching storage or the network. It never
/// names a place in a log or analytics event — it only returns value objects
/// the UI renders locally.
class PlaceLinkSuggester {
  const PlaceLinkSuggester({
    this.maxLinkDistanceMeters = 150,
    this.minDwell = const Duration(minutes: 5),
    this.maxSuggestions = 3,
  });

  /// A stop within this distance of a saved place is considered that place.
  final double maxLinkDistanceMeters;

  /// Stops shorter than this are traffic lights and queues, not places.
  final Duration minDwell;

  /// Most suggestions to return; extra stops are dropped.
  final int maxSuggestions;

  /// Proposes the most recent qualifying stops as links, newest first.
  ///
  /// Stops that dwelled for less than [minDwell] are ignored (they are the
  /// same "keep moving" threshold the milestone detector uses). Each remaining
  /// stop links to its nearest saved place when one is within
  /// [maxLinkDistanceMeters]; otherwise it is proposed as a new place.
  List<PlaceLinkSuggestion> suggest({
    required List<TripStop> stops,
    required List<Place> places,
  }) {
    final List<TripStop> dwelling = <TripStop>[
      for (final TripStop stop in stops)
        if (stop.dwell >= minDwell) stop,
    ]..sort((TripStop a, TripStop b) => b.arrivedAt.compareTo(a.arrivedAt));

    final List<PlaceLinkSuggestion> suggestions = <PlaceLinkSuggestion>[];
    for (final TripStop stop in dwelling) {
      Place? nearest;
      double nearestDistance = double.infinity;
      for (final Place place in places) {
        final double distance = distanceMeters(
          stop.latitude,
          stop.longitude,
          place.latitude,
          place.longitude,
        );
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearest = place;
        }
      }

      if (nearest != null && nearestDistance <= maxLinkDistanceMeters) {
        suggestions.add(
          PlaceLinkSuggestion(
            kind: PlaceLinkSuggestionKind.linkToExisting,
            stop: stop,
            place: nearest,
            distanceMeters: nearestDistance,
          ),
        );
      } else {
        suggestions.add(
          PlaceLinkSuggestion(
            kind: PlaceLinkSuggestionKind.saveAsNew,
            stop: stop,
            distanceMeters: 0,
          ),
        );
      }

      if (suggestions.length >= maxSuggestions) break;
    }
    return suggestions;
  }

  /// Equirectangular distance in metres between two WGS-84 coordinates.
  ///
  /// The same planar approximation the milestone detector uses: accurate to
  /// well under a percent below a kilometre, allocation-free, no platform
  /// channels.
  static double distanceMeters(
    double latA,
    double lonA,
    double latB,
    double lonB,
  ) {
    const double earthRadiusM = 6371000;
    final double meanLat = (latA + latB) / 2 * math.pi / 180;
    final double northM = (latB - latA) * math.pi / 180 * earthRadiusM;
    final double eastM =
        (lonB - lonA) * math.pi / 180 * earthRadiusM * math.cos(meanLat);
    return math.sqrt(northM * northM + eastM * eastM);
  }
}
