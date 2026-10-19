import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/services/polyline_smoother.dart';
import 'package:routenote/src/services/route_milestones.dart';

/// A timed route vertex at [lat]/[lon].
RoutePoint _p(double lat, double lon, DateTime at) =>
    RoutePoint(latitude: lat, longitude: lon, at: at);

void main() {
  // Everything is deterministic: fixed coordinates in Greater Cairo, fixed
  // clock, 0.01 deg of latitude (~1.1 km) between stops.
  final DateTime t0 = DateTime(2026, 10, 19, 8);

  group('detectMilestones', () {
    test('an empty path yields no milestones', () {
      expect(detectMilestones(const <RoutePoint>[]), isEmpty);
    });

    test('a path without timestamps yields no timeline', () {
      // A record written by an older build: coordinates, but no `at`.
      final List<RoutePoint> untimed = <RoutePoint>[
        const RoutePoint(latitude: 30.0, longitude: 31.0),
        const RoutePoint(latitude: 30.01, longitude: 31.0),
      ];
      expect(detectMilestones(untimed), isEmpty);
    });

    test('a single timed fix is just the trip start', () {
      final List<RouteMilestone> milestones = detectMilestones(<RoutePoint>[
        _p(30.0, 31.0, t0),
      ]);
      expect(milestones, hasLength(1));
      expect(milestones.single.kind, RouteMilestoneKind.tripStart);
      expect(milestones.single.at, t0);
      expect(milestones.single.latitude, 30.0);
    });

    test('a moving trip yields exactly start and end with exact times', () {
      final List<RouteMilestone> milestones = detectMilestones(<RoutePoint>[
        _p(30.0000, 31.0, t0),
        _p(30.0100, 31.0, t0.add(const Duration(minutes: 1))),
        _p(30.0200, 31.0, t0.add(const Duration(minutes: 2))),
      ]);
      expect(milestones, hasLength(2));
      expect(milestones.first.kind, RouteMilestoneKind.tripStart);
      expect(milestones.first.at, t0);
      expect(milestones.last.kind, RouteMilestoneKind.tripEnd);
      expect(milestones.last.at, t0.add(const Duration(minutes: 2)));
      expect(milestones.last.latitude, 30.02);
    });

    test('a sustained stop becomes a milestone at its arrival time', () {
      final List<RouteMilestone> milestones = detectMilestones(<RoutePoint>[
        _p(30.0000, 31.0, t0),
        // Arrival away from the origin…
        _p(30.0100, 31.0, t0.add(const Duration(minutes: 1))),
        // …jittering inside the 60 m cluster radius…
        _p(30.0102, 31.0, t0.add(const Duration(minutes: 2))),
        _p(30.0098, 31.0, t0.add(const Duration(minutes: 3))),
        // …for five minutes before moving on.
        _p(30.0101, 31.0, t0.add(const Duration(minutes: 6))),
        _p(30.0300, 31.0, t0.add(const Duration(minutes: 7))),
      ]);
      expect(milestones, hasLength(3));

      final RouteMilestone stop = milestones[1];
      expect(stop.kind, RouteMilestoneKind.stop);
      // The milestone time is the ARRIVAL, not the departure.
      expect(stop.at, t0.add(const Duration(minutes: 1)));
      // The coordinate is the jitter-averaged centroid of the cluster.
      expect(stop.latitude, closeTo(30.0100, 0.001));
      expect(stop.longitude, 31.0);

      expect(milestones.first.kind, RouteMilestoneKind.tripStart);
      expect(milestones.last.kind, RouteMilestoneKind.tripEnd);
      expect(milestones.last.at, t0.add(const Duration(minutes: 7)));
    });

    test('a stop shorter than the dwell threshold is ignored', () {
      final List<RouteMilestone> milestones = detectMilestones(<RoutePoint>[
        _p(30.0000, 31.0, t0),
        _p(30.0100, 31.0, t0.add(const Duration(minutes: 1))),
        _p(30.0101, 31.0, t0.add(const Duration(minutes: 2))),
        _p(30.0100, 31.0, t0.add(const Duration(minutes: 3))),
        _p(30.0300, 31.0, t0.add(const Duration(minutes: 4))),
      ]);
      expect(
        milestones.map((RouteMilestone m) => m.kind),
        <RouteMilestoneKind>[
          RouteMilestoneKind.tripStart,
          RouteMilestoneKind.tripEnd,
        ],
      );
    });

    test('a stop too far away starts a new cluster instead of joining', () {
      // 0.02 deg of latitude (~2.2 km) between fixes: the "cluster" never
      // forms, so no stop is emitted no matter the elapsed time.
      final List<RouteMilestone> milestones = detectMilestones(<RoutePoint>[
        _p(30.0000, 31.0, t0),
        _p(30.0100, 31.0, t0.add(const Duration(minutes: 10))),
        _p(30.0300, 31.0, t0.add(const Duration(minutes: 20))),
        _p(30.0500, 31.0, t0.add(const Duration(minutes: 30))),
      ]);
      expect(milestones, hasLength(2));
    });

    test('the departure dwell merges into the trip start', () {
      final List<RouteMilestone> milestones = detectMilestones(<RoutePoint>[
        _p(30.0000, 31.0, t0),
        _p(30.0002, 31.0, t0.add(const Duration(minutes: 1))),
        _p(30.0001, 31.0, t0.add(const Duration(minutes: 6))),
        _p(30.0200, 31.0, t0.add(const Duration(minutes: 7))),
      ]);
      expect(
        milestones.map((RouteMilestone m) => m.kind),
        <RouteMilestoneKind>[
          RouteMilestoneKind.tripStart,
          RouteMilestoneKind.tripEnd,
        ],
      );
      // The start narrates the departure place and its FIRST fix.
      expect(milestones.first.at, t0);
      expect(milestones.first.latitude, 30.0);
    });

    test('the arrival dwell merges into the trip end', () {
      final List<RouteMilestone> milestones = detectMilestones(<RoutePoint>[
        _p(30.0000, 31.0, t0),
        _p(30.0200, 31.0, t0.add(const Duration(minutes: 1))),
        _p(30.0201, 31.0, t0.add(const Duration(minutes: 2))),
        _p(30.0200, 31.0, t0.add(const Duration(minutes: 8))),
      ]);
      expect(milestones, hasLength(2));
      // The end narrates where the device actually stopped — the LAST fix,
      // not the cluster centroid.
      expect(milestones.last.kind, RouteMilestoneKind.tripEnd);
      expect(milestones.last.at, t0.add(const Duration(minutes: 8)));
      expect(milestones.last.latitude, 30.02);
    });

    test('at most maxStops stops survive, sampled evenly and chronologically',
        () {
      // Origin dwell (merged into start) + [stopCount] dwell stops, each one
      // kilometre further north, then a final hop that ends the day.
      final List<RoutePoint> busyDay = <RoutePoint>[];
      DateTime t = t0;
      for (int k = 0; k < 6; k++) {
        busyDay.add(_p(30.0, 31.0, t));
        t = t.add(const Duration(minutes: 1));
      }
      const int stopCount = 15;
      for (int i = 0; i < stopCount; i++) {
        final double lat = 30.01 + i * 0.01;
        for (int k = 0; k < 6; k++) {
          busyDay.add(_p(lat, 31.0, t));
          t = t.add(const Duration(minutes: 1));
        }
      }
      busyDay.add(_p(31.0, 32.0, t));

      final List<RouteMilestone> milestones = detectMilestones(busyDay);
      // start + 10 capped stops + end.
      expect(milestones, hasLength(12));
      expect(milestones.first.kind, RouteMilestoneKind.tripStart);
      expect(milestones.last.kind, RouteMilestoneKind.tripEnd);

      final List<RouteMilestone> stops = milestones
          .where((RouteMilestone m) => m.kind == RouteMilestoneKind.stop)
          .toList();
      expect(stops, hasLength(10));
      // Even sampling keeps the earliest stop and stays strictly
      // chronological afterwards.
      expect(stops.first.latitude, closeTo(30.01, 0.0001));
      for (int i = 1; i < stops.length; i++) {
        expect(stops[i].latitude, greaterThan(stops[i - 1].latitude));
        expect(stops[i].at.isAfter(stops[i - 1].at), isTrue);
      }
      // And the whole timeline never goes backwards in time.
      for (int i = 1; i < milestones.length; i++) {
        expect(milestones[i].at.isAfter(milestones[i - 1].at), isTrue);
      }
    });
  });

  group('RouteMilestone.coordinateKey', () {
    test('quantises to a ~110 m bucket so one place has one name slot', () {
      final RouteMilestone a = RouteMilestone(
        kind: RouteMilestoneKind.stop,
        at: t0,
        latitude: 30.01234,
        longitude: 31.04567,
      );
      final RouteMilestone b = RouteMilestone(
        kind: RouteMilestoneKind.stop,
        at: t0,
        latitude: 30.01210,
        longitude: 31.04590,
      );
      expect(a.coordinateKey, '30.012,31.046');
      expect(a.coordinateKey, b.coordinateKey);

      final RouteMilestone far = RouteMilestone(
        kind: RouteMilestoneKind.stop,
        at: t0,
        latitude: 30.01300,
        longitude: 31.04590,
      );
      expect(far.coordinateKey, isNot(a.coordinateKey));
    });

    test('equality compares every field', () {
      final RouteMilestone a = RouteMilestone(
        kind: RouteMilestoneKind.stop,
        at: t0,
        latitude: 30,
        longitude: 31,
      );
      final RouteMilestone same = RouteMilestone(
        kind: RouteMilestoneKind.stop,
        at: t0,
        latitude: 30,
        longitude: 31,
      );
      final RouteMilestone otherKind = RouteMilestone(
        kind: RouteMilestoneKind.tripEnd,
        at: t0,
        latitude: 30,
        longitude: 31,
      );
      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a, isNot(otherKind));
    });
  });
}
