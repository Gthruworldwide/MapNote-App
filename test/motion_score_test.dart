import 'package:flutter_test/flutter_test.dart';
import 'package:routenote/src/features/motion_analytics/domain/entities/motion_event.dart';
import 'package:routenote/src/services/driving_event_locator.dart';
import 'package:routenote/src/services/motion_profiler.dart';
import 'package:routenote/src/services/motion_score.dart';
import 'package:routenote/src/services/polyline_smoother.dart';

/// Builds a maneuver at [at] with a peak of [peakMps2].
DrivingEvent _event(
  DrivingEventType type, {
  required DateTime at,
  double peakMps2 = 5,
}) => DrivingEvent(
  type: type,
  peakMps2: peakMps2,
  startedAt: at,
  duration: const Duration(seconds: 1),
);

/// A route vertex at [latitude]/[longitude] taken at [at].
RoutePoint _point(double latitude, double longitude, DateTime at) =>
    RoutePoint(latitude: latitude, longitude: longitude, at: at);

void main() {
  final DateTime t0 = DateTime(2026, 10, 21, 9);

  group('MotionScore', () {
    test('a trip with no maneuvers is clean and scores 100', () {
      final MotionScore score = MotionScore.from(
        const <DrivingEvent>[],
        distanceKm: 12,
      );

      expect(score.score, 100);
      expect(score.total, 0);
      expect(score.isClean, isTrue);
      expect(score.band, MotionScoreBand.excellent);
    });

    test('more maneuvers always score lower', () {
      final List<DrivingEvent> one = <DrivingEvent>[
        _event(DrivingEventType.harshBraking, at: t0),
      ];
      final List<DrivingEvent> many = <DrivingEvent>[
        for (int i = 0; i < 8; i++)
          _event(
            DrivingEventType.harshBraking,
            at: t0.add(Duration(seconds: i * 20)),
          ),
      ];

      final MotionScore few = MotionScore.from(one, distanceKm: 1);
      final MotionScore lots = MotionScore.from(many, distanceKm: 1);

      expect(lots.score, lessThan(few.score));
      expect(lots.total, 8);
    });

    test('the same maneuvers over a longer distance score higher', () {
      // Distance absorbs maneuvers: 6 hard brakes in 500 m is alarming, the
      // same 6 spread over 40 km is unremarkable.
      final List<DrivingEvent> events = <DrivingEvent>[
        for (int i = 0; i < 6; i++)
          _event(
            DrivingEventType.harshBraking,
            at: t0.add(Duration(seconds: i * 30)),
          ),
      ];

      final MotionScore short = MotionScore.from(events, distanceKm: 0.5);
      final MotionScore long = MotionScore.from(events, distanceKm: 40);

      expect(long.score, greaterThan(short.score));
    });

    test('the score never falls below the floor', () {
      // A punishing trip: dozens of brakes over almost no distance.
      final List<DrivingEvent> events = <DrivingEvent>[
        for (int i = 0; i < 60; i++)
          _event(
            DrivingEventType.harshBraking,
            at: t0.add(Duration(seconds: i * 5)),
          ),
      ];

      final MotionScore score = MotionScore.from(events, distanceKm: 0.05);

      expect(score.score, greaterThanOrEqualTo(5));
      expect(score.score, lessThanOrEqualTo(100));
      expect(score.band, MotionScoreBand.poor);
    });

    test('every maneuver kind is tallied, and never falls through', () {
      final List<DrivingEvent> events = <DrivingEvent>[
        _event(DrivingEventType.harshBraking, at: t0),
        _event(DrivingEventType.harshBraking, at: t0.add(const Duration(minutes: 1))),
        _event(DrivingEventType.sharpTurn, at: t0.add(const Duration(minutes: 2))),
        _event(DrivingEventType.speedBump, at: t0.add(const Duration(minutes: 3))),
        _event(DrivingEventType.pothole, at: t0.add(const Duration(minutes: 4))),
        _event(DrivingEventType.harshAcceleration, at: t0.add(const Duration(minutes: 5))),
      ];

      final MotionScore score = MotionScore.from(events, distanceKm: 5);

      expect(score.tallies[DrivingEventType.harshBraking], 2);
      expect(score.tallies[DrivingEventType.sharpTurn], 1);
      expect(score.tallies[DrivingEventType.speedBump], 1);
      expect(score.tallies[DrivingEventType.pothole], 1);
      expect(score.tallies[DrivingEventType.harshAcceleration], 1);
      // A stable row per kind, so the sheet renders a complete checklist.
      expect(
        score.tallies.keys,
        containsAll(DrivingEventType.values),
      );
      expect(score.total, 6);
    });

    test('a non-finite or negative distance is treated as the strictest case', () {
      final List<DrivingEvent> events = <DrivingEvent>[
        for (int i = 0; i < 5; i++)
          _event(DrivingEventType.harshBraking, at: t0.add(Duration(seconds: i * 30))),
      ];

      final MotionScore nan = MotionScore.from(events, distanceKm: double.nan);
      final MotionScore negative = MotionScore.from(events, distanceKm: -3);
      final MotionScore zero = MotionScore.from(events, distanceKm: 0);

      expect(nan.score, zero.score);
      expect(negative.score, zero.score);
    });

    test('band boundaries are monotonic', () {
      expect(MotionScore.from(_nBrakes(0), distanceKm: 1).band, MotionScoreBand.excellent);
      final double small = MotionScore.from(_nBrakes(1), distanceKm: 3).score.toDouble();
      final double heavy = MotionScore.from(_nBrakes(12), distanceKm: 1).score.toDouble();
      expect(small, greaterThan(heavy));
    });

    test('the motion-event taxonomy maps onto the same score', () {
      // `fromMotionEvents` is the bridge for callers holding the classifier's
      // own MotionEvent type; smoothDrive is a state and never tallied.
      final MotionScore score = MotionScore.fromMotionEvents(
        <MotionEvent>[
          MotionEvent(
            kind: MotionEventKind.hardBrake,
            confidence: 0.9,
            peakMps2: -5,
            startedAt: t0,
          ),
          MotionEvent(
            kind: MotionEventKind.smoothDrive,
            confidence: 0.5,
            peakMps2: 0,
            startedAt: t0,
          ),
        ],
        distanceKm: 1,
      );

      // Only the brake is tallied; the smooth window is a state, not a event.
      expect(score.total, 1);
      expect(score.tallies[DrivingEventType.harshBraking], 1);
    });
  });

  group('DrivingEventLocator', () {
    test('places each event on the vertex nearest its timestamp', () {
      final List<RoutePoint> route = <RoutePoint>[
        _point(30.000, 31.000, t0),
        _point(30.010, 31.010, t0.add(const Duration(seconds: 10))),
        _point(30.020, 31.020, t0.add(const Duration(seconds: 20))),
      ];
      final DrivingEvent event = _event(
        DrivingEventType.pothole,
        at: t0.add(const Duration(seconds: 11)),
      );

      final List<LocatedDrivingEvent> located = DrivingEventLocator.locate(
        events: <DrivingEvent>[event],
        route: route,
      );

      expect(located, hasLength(1));
      // 11 s is nearest the 10 s vertex, not the 20 s one.
      expect(located.single.point.latitude, 30.010);
      expect(located.single.event.type, DrivingEventType.pothole);
    });

    test('a maneuver far from any vertex is dropped, not misplaced', () {
      // A 5-minute route with an event timestamped an hour before it: pinning
      // it would put a marker where the driver certainly was not.
      final List<RoutePoint> route = <RoutePoint>[
        _point(30.000, 31.000, t0),
        _point(30.010, 31.010, t0.add(const Duration(seconds: 10))),
      ];
      final DrivingEvent event = _event(
        DrivingEventType.speedBump,
        at: t0.subtract(const Duration(hours: 1)),
      );

      expect(
        DrivingEventLocator.locate(
          events: <DrivingEvent>[event],
          route: route,
        ),
        isEmpty,
      );
    });

    test('vertices without a timestamp cannot host a marker', () {
      final List<RoutePoint> route = <RoutePoint>[
        const RoutePoint(latitude: 30.0, longitude: 31.0),
        const RoutePoint(latitude: 30.1, longitude: 31.1),
      ];
      final DrivingEvent event = _event(DrivingEventType.sharpTurn, at: t0);

      expect(
        DrivingEventLocator.locate(
          events: <DrivingEvent>[event],
          route: route,
        ),
        isEmpty,
      );
    });

    test('an empty event list or route yields nothing', () {
      expect(
        DrivingEventLocator.locate(
          events: const <DrivingEvent>[],
          route: <RoutePoint>[_point(30.0, 31.0, t0)],
        ),
        isEmpty,
      );
      expect(
        DrivingEventLocator.locate(
          events: <DrivingEvent>[_event(DrivingEventType.pothole, at: t0)],
          route: const <RoutePoint>[],
        ),
        isEmpty,
      );
    });

    test('one marker per event, in the events own order', () {
      final List<RoutePoint> route = <RoutePoint>[
        for (int i = 0; i < 6; i++)
          _point(30.0 + i * 0.001, 31.0, t0.add(Duration(seconds: i * 5))),
      ];
      final List<DrivingEvent> events = <DrivingEvent>[
        _event(DrivingEventType.pothole, at: t0.add(const Duration(seconds: 22))),
        _event(DrivingEventType.harshBraking, at: t0.add(const Duration(seconds: 2))),
      ];

      final List<LocatedDrivingEvent> located = DrivingEventLocator.locate(
        events: events,
        route: route,
      );

      expect(located, hasLength(2));
      expect(located[0].event.type, DrivingEventType.pothole);
      expect(located[1].event.type, DrivingEventType.harshBraking);
    });

    test('an event beyond the end of the route keeps the last vertex', () {
      final List<RoutePoint> route = <RoutePoint>[
        _point(30.000, 31.000, t0),
        _point(30.010, 31.010, t0.add(const Duration(seconds: 10))),
      ];
      final DrivingEvent event = _event(
        DrivingEventType.harshAcceleration,
        at: t0.add(const Duration(seconds: 25)),
      );

      final List<LocatedDrivingEvent> located = DrivingEventLocator.locate(
        events: <DrivingEvent>[event],
        route: route,
      );

      // 15 s past the last vertex, inside the 30 s placement window: it is
      // drawn at the closest evidence rather than dropped.
      expect(located, hasLength(1));
      expect(located.single.point.latitude, 30.010);
    });
  });
}

/// `n` hard brakes, one every 30 s.
List<DrivingEvent> _nBrakes(int n) => <DrivingEvent>[
  for (int i = 0; i < n; i++)
    DrivingEvent(
      type: DrivingEventType.harshBraking,
      peakMps2: -5,
      startedAt: DateTime(2026, 10, 21, 9).add(Duration(seconds: i * 30)),
      duration: const Duration(seconds: 1),
    ),
];
