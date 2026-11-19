import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/services/gps_sample_validator.dart';

void main() {
  const GpsSampleValidator validator = GpsSampleValidator();
  final DateTime t0 = DateTime.utc(2026, 11, 19, 12);

  GpsSampleRejection validateAt({
    required double lat,
    required double lon,
    required DateTime at,
    double? accuracy,
    double? speed,
    DateTime? previousAt,
    double? previousLat,
    double? previousLon,
  }) {
    return validator.validate(
      latitude: lat,
      longitude: lon,
      timestamp: at,
      accuracyMeters: accuracy,
      speedMetersPerSecond: speed,
      previousTimestamp: previousAt,
      previousLatitude: previousLat,
      previousLongitude: previousLon,
    );
  }

  group('strict GPS sample integrity', () {
    test('a well-formed first fix is accepted', () {
      expect(
        validateAt(lat: 30.0444, lon: 31.2357, at: t0, accuracy: 5),
        GpsSampleRejection.none,
      );
    });

    test('NaN and infinite coordinates are rejected', () {
      expect(
        validateAt(lat: double.nan, lon: 31, at: t0),
        GpsSampleRejection.nonFiniteCoordinate,
      );
      expect(
        validateAt(lat: 30, lon: double.infinity, at: t0),
        GpsSampleRejection.nonFiniteCoordinate,
      );
    });

    test('out-of-range coordinates are rejected', () {
      expect(
        validateAt(lat: 91, lon: 31, at: t0),
        GpsSampleRejection.outOfRangeCoordinate,
      );
      expect(
        validateAt(lat: 30, lon: -181, at: t0),
        GpsSampleRejection.outOfRangeCoordinate,
      );
    });

    test('non-finite accuracy or speed is rejected', () {
      expect(
        validateAt(lat: 30, lon: 31, at: t0, accuracy: double.nan),
        GpsSampleRejection.nonFiniteMotion,
      );
      expect(
        validateAt(lat: 30, lon: 31, at: t0, speed: double.infinity),
        GpsSampleRejection.nonFiniteMotion,
      );
      expect(
        validateAt(lat: 30, lon: 31, at: t0, speed: -1),
        GpsSampleRejection.nonFiniteMotion,
      );
    });

    test('a backwards timestamp is rejected', () {
      final DateTime next = t0.add(const Duration(seconds: 1));
      expect(
        validateAt(
          lat: 30,
          lon: 31,
          at: t0.subtract(const Duration(seconds: 1)),
          previousAt: t0,
        ),
        GpsSampleRejection.backwardsTimestamp,
      );
      expect(
        validateAt(lat: 30, lon: 31, at: next, previousAt: t0),
        GpsSampleRejection.none,
      );
    });

    test('an equal timestamp is tolerated (frozen clocks in tests)', () {
      // Widget tests run under FakeAsync, where DateTime.now() is frozen; a
      // repeated timestamp is harmless because the jump check skips zero
      // elapsed time and _countsAsTravel ignores sub-second windows.
      expect(
        validateAt(lat: 30, lon: 31, at: t0, previousAt: t0),
        GpsSampleRejection.none,
      );
    });

    test('an impossible Cairo -> New York jump in one second is rejected', () {
      // Cairo ~ (30.0444, 31.2357), New York ~ (40.7128, -74.0060).
      expect(
        validateAt(
          lat: 40.7128,
          lon: -74.0060,
          at: t0.add(const Duration(seconds: 1)),
          previousAt: t0,
          previousLat: 30.0444,
          previousLon: 31.2357,
        ),
        GpsSampleRejection.impossibleJump,
      );
    });

    test('ordinary driving over the same span is accepted', () {
      // ~1.4 km between two fixes a minute apart: ~84 km/h.
      expect(
        validateAt(
          lat: 30.0568,
          lon: 31.2357,
          at: t0.add(const Duration(minutes: 1)),
          previousAt: t0,
          previousLat: 30.0444,
          previousLon: 31.2357,
        ),
        GpsSampleRejection.none,
      );
    });

    test('an intercontinental jump is rejected even across a long gap', () {
      // ~9000 km over two hours is still ~4500 km/h — impossible on the
      // ground, so it is a provider glitch, not travel.
      expect(
        validateAt(
          lat: 40.7128,
          lon: -74.0060,
          at: t0.add(const Duration(hours: 2)),
          previousAt: t0,
          previousLat: 30.0444,
          previousLon: 31.2357,
        ),
        GpsSampleRejection.impossibleJump,
      );
    });

    test('a small move across a long gap is accepted', () {
      // Distance alone is not the criterion — implied speed is. ~1 km over
      // two hours is well within any plausible walking pace.
      expect(
        validateAt(
          lat: 30.0534,
          lon: 31.2357,
          at: t0.add(const Duration(hours: 2)),
          previousAt: t0,
          previousLat: 30.0444,
          previousLon: 31.2357,
        ),
        GpsSampleRejection.none,
      );
    });
  });
}
