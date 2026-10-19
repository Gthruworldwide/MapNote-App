import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/features/saved_places/data/datasources/trip_stop_detector.dart';
import 'package:routenote/src/features/saved_places/domain/entities/trip_stop.dart';
import 'package:routenote/src/services/polyline_smoother.dart';

/// Builds a route that travels to a fixed point, dwells there for [dwell], then
/// moves on — the shape of a real "stopped somewhere" segment.
List<RoutePoint> _pathWithDwell({
  required DateTime base,
  required Duration dwell,
  int samples = 7,
}) {
  final Duration step = Duration(
    microseconds: dwell.inMicroseconds ~/ (samples - 1),
  );
  return <RoutePoint>[
    RoutePoint(latitude: 30.0, longitude: 31.0, at: base),
    for (int i = 0; i < samples; i++)
      RoutePoint(latitude: 30.05, longitude: 31.05, at: base.add(step * i)),
    RoutePoint(
      latitude: 30.1,
      longitude: 31.1,
      at: base.add(dwell + const Duration(minutes: 5)),
    ),
  ];
}

void main() {
  const TripStopDetector detector = TripStopDetector();

  test('derives a stop with its measured dwell', () {
    final List<TripStop> stops = detector.detect(
      _pathWithDwell(
        base: DateTime.utc(2026, 10, 19, 8),
        dwell: const Duration(minutes: 12),
      ),
    );

    expect(stops, hasLength(1));
    expect(stops.single.dwell, const Duration(minutes: 12));
    expect(stops.single.latitude, closeTo(30.05, 1e-9));
    expect(stops.single.longitude, closeTo(31.05, 1e-9));
    expect(
      stops.single.arrivedAt.isBefore(DateTime.utc(2026, 10, 19, 8, 1)),
      isTrue,
    );
  });

  test('drops clusters that dwell for less than the threshold', () {
    final List<TripStop> stops = detector.detect(
      _pathWithDwell(
        base: DateTime.utc(2026, 10, 19, 8),
        dwell: const Duration(minutes: 4),
        samples: 5,
      ),
    );

    expect(stops, isEmpty);
  });

  test('returns nothing for an untimed path', () {
    final List<TripStop> stops = detector.detect(const <RoutePoint>[
      RoutePoint(latitude: 30.05, longitude: 31.05),
      RoutePoint(latitude: 30.05, longitude: 31.051),
    ]);

    expect(stops, isEmpty);
  });

  test('honours a custom minDwell', () {
    final List<TripStop> stops = const TripStopDetector(
      minDwell: Duration(minutes: 2),
    ).detect(
      _pathWithDwell(
        base: DateTime.utc(2026, 10, 19, 8),
        dwell: const Duration(minutes: 3),
        samples: 4,
      ),
    );

    expect(stops, hasLength(1));
    expect(stops.single.dwell, const Duration(minutes: 3));
  });

  test('returns an empty list for a path with a single point', () {
    expect(
      detector.detect(<RoutePoint>[
        RoutePoint(latitude: 30.05, longitude: 31.05, at: DateTime.utc(2026)),
      ]),
      isEmpty,
    );
  });
}
