import '../../../../services/polyline_smoother.dart';
import '../../../../services/route_milestones.dart';
import '../../domain/entities/trip_stop.dart';
import '../../domain/services/place_link_suggester.dart';

/// Derives the day's [TripStop]s from a recorded route.
///
/// Reuses [detectMilestones] for the authoritative stop *selection* — the same
/// greedy dwell-clustering pass the AutoMotion timeline draws — and then
/// measures each stop's actual dwell by walking the timed fixes that fall
/// inside the stop radius. Pure, offline and allocation-light; it is a
/// derivation, never a stored record.
class TripStopDetector {
  const TripStopDetector({
    this.minDwell = const Duration(minutes: 5),
    this.radiusMeters = 60,
    this.maxStops = 10,
  });

  /// Minimum dwell for a cluster to count as a stop.
  final Duration minDwell;

  /// Radius defining "inside the same stop".
  final double radiusMeters;

  /// Maximum stops returned (evenly sampled over the day).
  final int maxStops;

  /// The day's qualifying stops, chronological. Empty when the path has no
  /// timestamps (nothing to dwell "for") or contains no long enough stop.
  List<TripStop> detect(List<RoutePoint> path) {
    final List<RouteMilestone> milestones = detectMilestones(
      path,
      minDwell: minDwell,
      radiusMeters: radiusMeters,
      maxStops: maxStops,
    );

    final List<RoutePoint> timed = <RoutePoint>[
      for (final RoutePoint point in path)
        if (point.at != null) point,
    ];

    final List<TripStop> stops = <TripStop>[];
    for (final RouteMilestone milestone in milestones) {
      if (milestone.kind != RouteMilestoneKind.stop) continue;
      stops.add(
        TripStop(
          latitude: milestone.latitude,
          longitude: milestone.longitude,
          arrivedAt: milestone.at,
          dwell:
              _measureDwell(timed, milestone.latitude, milestone.longitude) ??
              minDwell,
        ),
      );
    }
    return stops;
  }

  /// How long the timed fixes stayed within [radiusMeters] of the stop point.
  ///
  /// Returns `null` when no timed fix falls inside the radius (the cluster was
  /// built from untimed vertices), in which case the caller falls back to
  /// [minDwell].
  Duration? _measureDwell(
    List<RoutePoint> timed,
    double latitude,
    double longitude,
  ) {
    DateTime? first;
    DateTime? last;
    for (final RoutePoint point in timed) {
      final double distance = PlaceLinkSuggester.distanceMeters(
        latitude,
        longitude,
        point.latitude,
        point.longitude,
      );
      if (distance > radiusMeters) continue;
      first ??= point.at;
      last = point.at;
    }
    if (first == null || last == null) return null;

    final Duration dwell = last.difference(first);
    return dwell.isNegative ? Duration.zero : dwell;
  }
}
