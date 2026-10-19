import 'dart:math' as math;

import 'polyline_smoother.dart';

/// The role a milestone plays in the day's route narrative.
///
/// The kind doubles as the fallback label when reverse geocoding cannot name
/// the coordinate (offline, no geocoder, rural fix), so the timeline always
/// has something meaningful to show.
enum RouteMilestoneKind {
  /// The first timed fix of the route — where and when the day started.
  tripStart,

  /// A sustained stop: the device loitered inside [detectMilestones]' radius
  /// for at least [detectMilestones]' minimum dwell time.
  stop,

  /// The last timed fix of the route — where and when tracking last saw the
  /// device.
  tripEnd,
}

/// One significant point on a recorded route: a coordinate anchored to the
/// exact time the device was there.
///
/// Milestones are derived (never stored): they are recomputed from the day's
/// smoothed path whenever the dashboard needs them, so adding this type adds
/// no Hive schema and no migration risk.
class RouteMilestone {
  const RouteMilestone({
    required this.kind,
    required this.at,
    required this.latitude,
    required this.longitude,
  });

  /// Whether this is the trip start, a mid-route stop, or the trip end.
  final RouteMilestoneKind kind;

  /// When the device arrived here (first fix of the dwell cluster for stops).
  final DateTime at;

  final double latitude;
  final double longitude;

  /// Quantised coordinate key (~110 m at mid latitudes) used as the stable
  /// identity for this place when caching reverse-geocoded names. Three
  /// decimals keep a growing dwell cluster in the same bucket while still
  /// separating stops a street apart.
  String get coordinateKey =>
      '${latitude.toStringAsFixed(3)},${longitude.toStringAsFixed(3)}';

  @override
  bool operator ==(Object other) =>
      other is RouteMilestone &&
      other.kind == kind &&
      other.at == at &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(kind, at, latitude, longitude);

  @override
  String toString() =>
      'RouteMilestone($kind, $at, $latitude, $longitude)';
}

/// Detects the day's [RouteMilestone]s along a recorded route.
///
/// The algorithm is a single greedy pass over the timed points:
///
///  * The first and last timed fixes always become [RouteMilestoneKind.tripStart]
///    and [RouteMilestoneKind.tripEnd] — the timeline's anchors.
///  * The interior is clustered by proximity: a point joins the running cluster
///    when it lies within [radiusMeters] of the cluster's centroid. When it
///    does not, the cluster is flushed and a new one begins.
///  * A flushed cluster becomes a [RouteMilestoneKind.stop] only when the
///    device loitered inside it for at least [minDwell] — so traffic lights
///    and moving queues never show up, while a 30-minute visit does. The stop
///    is dropped when it contains the first or last fix (that dwell is already
///    narrated by trip start / trip end).
///  * At most [maxStops] stops survive, sampled evenly so a long day keeps its
///    beginning, middle and end rather than only its first ten stops.
///
/// Distances use an equirectangular (planar) approximation, which is accurate
/// to well under a percent at the sub-kilometre scale this runs at and keeps
/// the function pure — no trig tables, no platform channels, trivially unit
/// testable. The result is chronological by construction.
///
/// A route with no timestamps (a Hive record written by an older build, for
/// example) yields an empty list: without times there is no timeline to draw.
List<RouteMilestone> detectMilestones(
  List<RoutePoint> path, {
  Duration minDwell = const Duration(minutes: 5),
  double radiusMeters = 60,
  int maxStops = 10,
}) {
  final List<RoutePoint> timed = <RoutePoint>[
    for (final RoutePoint point in path)
      if (point.at != null) point,
  ];
  if (timed.isEmpty) return const <RouteMilestone>[];

  final RouteMilestone start = RouteMilestone(
    kind: RouteMilestoneKind.tripStart,
    at: timed.first.at!,
    latitude: timed.first.latitude,
    longitude: timed.first.longitude,
  );
  // A single timed fix narrates the whole day — start and end would be the
  // same place at the same instant, so only the start survives.
  if (timed.length == 1) return <RouteMilestone>[start];

  final RouteMilestone end = RouteMilestone(
    kind: RouteMilestoneKind.tripEnd,
    at: timed.last.at!,
    latitude: timed.last.latitude,
    longitude: timed.last.longitude,
  );

  final List<RouteMilestone> stops = <RouteMilestone>[];
  int clusterStart = 0;
  double centroidLat = timed.first.latitude;
  double centroidLon = timed.first.longitude;

  void flushCluster(int endIndex) {
    final int firstIndex = clusterStart;
    final DateTime firstAt = timed[firstIndex].at!;
    final DateTime lastAt = timed[endIndex].at!;
    if (lastAt.difference(firstAt) < minDwell) return;
    // The departure / arrival dwell is already narrated by trip start / end.
    if (firstIndex == 0) return;
    if (endIndex == timed.length - 1) return;
    stops.add(
      RouteMilestone(
        kind: RouteMilestoneKind.stop,
        at: firstAt,
        latitude: centroidLat,
        longitude: centroidLon,
      ),
    );
  }

  for (int i = 1; i < timed.length; i++) {
    final RoutePoint point = timed[i];
    if (_planarDistanceMeters(
          centroidLat,
          centroidLon,
          point.latitude,
          point.longitude,
        ) <=
        radiusMeters) {
      // Running mean keeps the representative point centred as jitter lands
      // on either side of the cluster.
      final int count = i - clusterStart + 1;
      centroidLat += (point.latitude - centroidLat) / count;
      centroidLon += (point.longitude - centroidLon) / count;
      continue;
    }
    flushCluster(i - 1);
    clusterStart = i;
    centroidLat = point.latitude;
    centroidLon = point.longitude;
  }
  flushCluster(timed.length - 1);

  final List<RouteMilestone> capped = _sampleEvenly(stops, maxStops);
  return <RouteMilestone>[start, ...capped, end];
}

/// Keeps at most [limit] entries, evenly spaced across the original list so a
/// capped timeline still spans the whole day.
List<RouteMilestone> _sampleEvenly(List<RouteMilestone> items, int limit) {
  if (items.length <= limit) return items;
  return <RouteMilestone>[
    for (int i = 0; i < limit; i++)
      items[(i * items.length / limit).floor()],
  ];
}

/// Equirectangular distance in metres between two WGS-84 coordinates.
///
/// Accurate enough at cluster scale (< 1 km) and allocation-free.
double _planarDistanceMeters(
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
