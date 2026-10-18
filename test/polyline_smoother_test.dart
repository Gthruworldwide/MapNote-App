import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:routenote/src/services/gap_recovery_service.dart';
import 'package:routenote/src/services/polyline_smoother.dart';

/// Distance between two vertices in metres — reuses the trackers' canonical
/// great-circle implementation so the tests measure exactly like production.
double _metersBetween(RoutePoint a, RoutePoint b) =>
    GapRecoveryService.haversineKm(
          a.latitude,
          a.longitude,
          b.latitude,
          b.longitude,
        ) *
        1000;

/// How far a point sits north/south of the horizontal line through [lineLat],
/// in metres (positive = north of the line).
double _crossTrackNorthM(RoutePoint point, double lineLat) =>
    (point.latitude - lineLat) *
    (math.pi / 180) *
    PolylineSmoother.earthRadiusKm *
    1000;

void main() {
  group('PolylineSmoother degenerate inputs', () {
    test('an empty track smooths to an empty track', () {
      expect(const PolylineSmoother().smooth(const <RoutePoint>[]), isEmpty);
    });

    test('a single fix is returned untouched', () {
      const RoutePoint only = RoutePoint(latitude: 30.0, longitude: 31.0);
      expect(
        const PolylineSmoother().smooth(const <RoutePoint>[only]),
        const <RoutePoint>[only],
      );
    });

    test('invalid vertices are dropped, not filtered', () {
      const RoutePoint a = RoutePoint(latitude: 30.0, longitude: 31.0);
      const RoutePoint b = RoutePoint(latitude: 30.001, longitude: 31.001);
      const RoutePoint outOfRange = RoutePoint(latitude: 91, longitude: 31.0);
      const RoutePoint notFinite = RoutePoint(
        latitude: double.nan,
        longitude: 31.0,
      );
      final List<RoutePoint> smoothed = const PolylineSmoother().smooth(
        const <RoutePoint>[a, outOfRange, notFinite, b],
      );
      expect(smoothed, const <RoutePoint>[a, b]);
    });

    test('two fixes come back exactly when endpoints are anchored', () {
      const RoutePoint a = RoutePoint(latitude: 30.0, longitude: 31.0);
      const RoutePoint b = RoutePoint(latitude: 30.001, longitude: 31.001);
      expect(
        const PolylineSmoother().smooth(const <RoutePoint>[a, b]),
        const <RoutePoint>[a, b],
      );
    });
  });

  group('PolylineSmoother jitter removal', () {
    test('cross-track jitter along a straight path is suppressed', () {
      // True path: straight east along lat 30.0, 0.001° per 5 s (~96 m at
      // ~19 m/s). Cross-track noise alternates ±0.00009° (~±10 m) — the
      // classic high-frequency GPS wobble a stored route must not show.
      final List<RoutePoint> raw = <RoutePoint>[
        for (int i = 0; i < 40; i++)
          RoutePoint(
            latitude: 30.0 + (i.isEven ? 0.00009 : -0.00009),
            longitude: 31.0 + i * 0.001,
            at: DateTime.utc(2026, 1, 1).add(Duration(seconds: 5 * i)),
          ),
      ];
      final List<RoutePoint> smoothed = const PolylineSmoother().smooth(raw);

      double inputSumSquares = 0;
      double outputSumSquares = 0;
      for (int i = 0; i < raw.length; i++) {
        final double input = _crossTrackNorthM(raw[i], 30.0);
        final double output = _crossTrackNorthM(smoothed[i], 30.0);
        inputSumSquares += input * input;
        outputSumSquares += output * output;
        // Invariant: smoothing never moves a vertex beyond its hard cap.
        expect(_metersBetween(smoothed[i], raw[i]), lessThanOrEqualTo(30.5));
      }
      final double inputRmsM = math.sqrt(inputSumSquares / raw.length);
      final double outputRmsM = math.sqrt(outputSumSquares / raw.length);
      expect(inputRmsM, greaterThan(9.5), reason: 'raw wobble is ~10 m');
      expect(
        outputRmsM,
        lessThan(0.6 * inputRmsM),
        reason: 'the smoothed trace keeps well under half the jitter',
      );
    });

    test('a noise-free straight track is left essentially alone', () {
      final List<RoutePoint> raw = <RoutePoint>[
        for (int i = 0; i < 10; i++)
          RoutePoint(
            latitude: 30.0,
            longitude: 31.0 + i * 0.001,
            at: DateTime.utc(2026, 1, 1).add(Duration(seconds: 5 * i)),
          ),
      ];
      final List<RoutePoint> smoothed = const PolylineSmoother().smooth(raw);
      for (int i = 1; i < raw.length - 1; i++) {
        expect(
          _crossTrackNorthM(smoothed[i], 30.0).abs(),
          lessThan(0.01),
          reason: 'vertex $i must stay on the line',
        );
        expect(_metersBetween(smoothed[i], raw[i]), lessThan(30.5));
      }
    });

    test('a sharp 90° corner survives within the correction cap', () {
      // East for ~965 m, then north for ~1000 m: the corner vertex must not
      // be rounded away beyond the clamp.
      final List<RoutePoint> raw = <RoutePoint>[
        for (int i = 0; i <= 10; i++)
          RoutePoint(
            latitude: 30.0,
            longitude: 31.0 + i * 0.001,
            at: DateTime.utc(2026, 1, 1).add(Duration(seconds: 5 * i)),
          ),
        for (int i = 1; i <= 10; i++)
          RoutePoint(
            latitude: 30.0 + i * 0.001,
            longitude: 31.01,
            at: DateTime.utc(2026, 1, 1)
                .add(Duration(seconds: 5 * (10 + i))),
          ),
      ];
      final List<RoutePoint> smoothed = const PolylineSmoother().smooth(raw);
      final RoutePoint corner = smoothed[10];
      expect(_metersBetween(corner, raw[10]), lessThanOrEqualTo(30.5));
      // The filter lags the turn slightly toward its inside — proof the
      // clamp, not a wild model, is what bounds the vertex.
      expect(corner.latitude, lessThanOrEqualTo(raw[10].latitude));
      for (int i = 0; i < raw.length; i++) {
        expect(_metersBetween(smoothed[i], raw[i]), lessThanOrEqualTo(30.5));
      }
    });

    test('a single bogus fix is pulled toward the path, never past the cap', () {
      final List<RoutePoint> raw = <RoutePoint>[
        for (int i = 0; i < 10; i++)
          RoutePoint(
            latitude: i == 5 ? 30.0009 : 30.0, // ~100 m north spike
            longitude: 31.0 + i * 0.001,
            at: DateTime.utc(2026, 1, 1).add(Duration(seconds: 5 * i)),
          ),
      ];
      final List<RoutePoint> smoothed = const PolylineSmoother().smooth(raw);
      final double rawOffset = _crossTrackNorthM(raw[5], 30.0);
      final double smoothedOffset = _crossTrackNorthM(smoothed[5], 30.0);
      expect(smoothedOffset, lessThan(rawOffset));
      expect(rawOffset - smoothedOffset, lessThanOrEqualTo(30.5));
      expect(_metersBetween(smoothed[5], raw[5]), lessThanOrEqualTo(30.5));
    });
  });

  group('PolylineSmoother gap handling', () {
    test('a tracking hole re-seeds instead of smearing across it', () {
      final DateTime start = DateTime.utc(2026, 1, 1);
      final List<RoutePoint> raw = <RoutePoint>[
        // Cluster A: parked at the origin, light jitter.
        for (int i = 0; i < 5; i++)
          RoutePoint(
            latitude: 30.0 + (i.isEven ? 0.00005 : -0.00005),
            longitude: 31.0,
            at: start.add(Duration(seconds: 5 * i)),
          ),
        // Cluster B: 1.1 km north, after a ten-minute hole.
        for (int i = 0; i < 5; i++)
          RoutePoint(
            latitude: 30.01 + (i.isEven ? 0.00005 : -0.00005),
            longitude: 31.0,
            at: start
                .add(Duration(seconds: 5 * i))
                .add(const Duration(minutes: 10)),
          ),
      ];
      final List<RoutePoint> smoothed = const PolylineSmoother().smooth(raw);
      // The first post-gap fix is re-seeded, hence returned exactly.
      expect(smoothed[5], raw[5]);
      // Every cluster-B vertex stays with cluster B — nothing is dragged
      // toward cluster A by the stale velocity model.
      for (int i = 5; i < 10; i++) {
        expect(_metersBetween(smoothed[i], raw[i]), lessThanOrEqualTo(30.5));
        expect(smoothed[i].latitude, greaterThan(30.005));
      }
    });
  });

  group('PolylineSmoother robustness', () {
    test('missing timestamps fall back to the assumed interval', () {
      final List<RoutePoint> raw = <RoutePoint>[
        for (int i = 0; i < 6; i++)
          RoutePoint(
            latitude: 30.0 + (i.isEven ? 0.00006 : -0.00006),
            longitude: 31.0 + i * 0.001,
          ),
      ];
      final List<RoutePoint> smoothed = const PolylineSmoother().smooth(raw);
      expect(smoothed.length, raw.length);
      expect(smoothed.first, raw.first);
      expect(smoothed.last, raw.last);
      for (int i = 0; i < raw.length; i++) {
        expect(_metersBetween(smoothed[i], raw[i]), lessThanOrEqualTo(30.5));
      }
    });

    test('a backwards clock jump is clamped, not modelled', () {
      final DateTime start = DateTime.utc(2026, 1, 1);
      final List<RoutePoint> raw = <RoutePoint>[
        RoutePoint(latitude: 30.0, longitude: 31.0, at: start),
        RoutePoint(
          latitude: 30.0001,
          longitude: 31.001,
          at: start.add(const Duration(seconds: 5)),
        ),
        RoutePoint(
          latitude: 30.0002,
          longitude: 31.002,
          at: start.add(const Duration(seconds: 3)), // clock jumped back
        ),
        RoutePoint(
          latitude: 30.0003,
          longitude: 31.003,
          at: start.add(const Duration(seconds: 8)),
        ),
      ];
      final List<RoutePoint> smoothed = const PolylineSmoother().smooth(raw);
      expect(smoothed.length, raw.length);
      for (int i = 0; i < raw.length; i++) {
        expect(_metersBetween(smoothed[i], raw[i]), lessThanOrEqualTo(30.5));
      }
    });

    test('the input list is never mutated', () {
      final List<RoutePoint> raw = <RoutePoint>[
        for (int i = 0; i < 5; i++)
          RoutePoint(
            latitude: 30.0 + (i.isEven ? 0.00008 : -0.00008),
            longitude: 31.0 + i * 0.001,
            at: DateTime.utc(2026, 1, 1).add(Duration(seconds: 5 * i)),
          ),
      ];
      final List<RoutePoint> copy = List<RoutePoint>.of(raw);
      const PolylineSmoother().smooth(raw);
      expect(raw, copy);
    });
  });
}
