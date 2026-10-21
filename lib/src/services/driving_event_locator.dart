import 'motion_profiler.dart';
import 'polyline_smoother.dart';

/// One maneuver pinned to the place on the route where it happened.
///
/// This is the **only** place a maneuver and a coordinate meet, and the pairing
/// is deliberately transient: it is built in memory from the live route, handed
/// to the map for rendering, and dropped when the trip ends. It is never
/// persisted, never written to the health log, and never leaves the device.
///
/// [DrivingEvent] itself stays location-free (AGENT_SKILLS.md §5) — the
/// coordinate here belongs to the *route vertex*, matched by timestamp, not to
/// the event.
class LocatedDrivingEvent {
  const LocatedDrivingEvent({required this.event, required this.point});

  /// The maneuver, unchanged and still carrying no location of its own.
  final DrivingEvent event;

  /// The route vertex the maneuver is drawn at.
  final RoutePoint point;

  /// How far in time the maneuver sat from the vertex chosen for it. Small
  /// values mean a precise placement; a large value means the route had a gap
  /// (a tunnel, a fix outage) and the marker is the closest evidence available.
  Duration timeOffsetFrom(DateTime at) => at.difference(event.startedAt).abs();
}

/// Pairs each maneuver with its route position by timestamp.
///
/// Pure and deterministic. The route is assumed to be in recording order, which
/// is how `AutoMotionService.smoothedPath` produces it.
class DrivingEventLocator {
  const DrivingEventLocator._();

  /// How far a maneuver may sit from the nearest route vertex and still be
  /// placed. Beyond this the route clearly had a hole around the maneuver, and
  /// pinning it would put a marker where the driver certainly was not.
  static const Duration maxPlacementGap = Duration(seconds: 30);

  /// Places [events] on [route].
  ///
  /// Vertices without a timestamp cannot be matched and are skipped as
  /// candidates. Events earlier or later than the whole route keep the first /
  /// last placed vertex (the closest evidence), and are dropped when even that
  /// is further away than [maxPlacementGap]. The result is returned in the
  /// events' own order.
  static List<LocatedDrivingEvent> locate({
    required List<DrivingEvent> events,
    required List<RoutePoint> route,
  }) {
    if (events.isEmpty) return const <LocatedDrivingEvent>[];
    final List<RoutePoint> timed = <RoutePoint>[
      for (final RoutePoint point in route)
        if (point.at != null) point,
    ];
    if (timed.isEmpty) return const <LocatedDrivingEvent>[];

    final List<LocatedDrivingEvent> located = <LocatedDrivingEvent>[];
    for (final DrivingEvent event in events) {
      final RoutePoint? nearest = _nearestVertex(timed, event.startedAt);
      if (nearest == null) continue;
      final DateTime at = nearest.at!;
      final Duration gap = at.difference(event.startedAt).abs();
      if (gap > maxPlacementGap) continue;
      located.add(LocatedDrivingEvent(event: event, point: nearest));
    }
    return located;
  }

  /// The vertex whose timestamp is closest to [at].
  ///
  /// A linear scan is the right tool here: the route is walked in order and
  /// both the event list and the route are small (a day's fixes), so the
  /// bookkeeping a binary search would need is not worth the complexity.
  static RoutePoint? _nearestVertex(List<RoutePoint> timed, DateTime at) {
    RoutePoint? best;
    Duration? bestGap;
    for (final RoutePoint point in timed) {
      final DateTime pointAt = point.at!;
      final Duration gap = pointAt.difference(at).abs();
      if (bestGap == null || gap < bestGap) {
        best = point;
        bestGap = gap;
      }
    }
    return best;
  }
}
