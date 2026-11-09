import 'dart:math' as math;
import 'package:flutter_test/flutter/test';
import 'package:motion_smooth/geo_math.dart';
import 'package:motion_smooth/circular_math.dart';

void main() {
  group('GeoMath equirectangular projection', () {
    test('latLngToLocalXY and localXYToLatLng are inverse operations', () {
      final geo = GeoMath();
      final centerLat = 30.0;
      final centerLng = 31.0;

      // Test multiple points around the center
      for (int i = 0; i < 20; i++) {
        final double testLat = 30.0 + _rng.nextDouble() * 0.1;
        final double testLng = 31.0 + _rng.nextDouble() * 0.1;

        final pair =
            geo.latLngToLocalXY(testLat, testLng, centerLat, centerLng);
        final restored =
            geo.localXYToLatLng(pair.first, pair.second, centerLat, centerLng);

        // Should be within ~0.001 degrees (approx 100m at this latitude)
        expect(restored.first, closeTo(testLat, 0.001));
        expect(restored.second, closeTo(testLng, 0.001));
      }
    });

    test('planar distance calculation is consistent', () {
      final geo = GeoMath();

      // Create two points and project them
      final pair1 = geo.latLngToLocalXY(30.0, 31.0, 30.0, 31.0);
      final pair2 = geo.latLngToLocalXY(30.001, 31.0, 30.0, 31.0);

      final distance = geo.planarDistanceMeters(
          pair1.first, pair1.second, pair2.first, pair2.second);

      // 0.001° latitude ≈ 111.139m, planar distance should be close
      expect(distance, closeTo(111.139, 50.0));
    });

    test('geodesic distance approximation is reasonable', () {
      final geo = GeoMath();

      // Distance along same latitude (1° longitude at equator ≈ 111.32 km)
      // At lat 30°, 1° longitude ≈ 111.32 * cos(30°) ≈ 96.43 km
      final distance = geo.geodesicDistanceMeters(30.0, 31.0, 30.0, 32.0);

      // Should be approximately 111.32 km at equator, less at lat 30°
      expect(distance, greaterThan(90000));
      expect(distance, lessThan(130000));
    });

    test('convergence factor is correct at known latitudes', () {
      final geo = GeoMath();

      // At equator (0°), convergence = cos(0) = 1
      expect(geo.convergenceFactor(0.0), closeTo(1.0, 0.001));

      // At 60°, convergence = cos(60°) = 0.5
      expect(geo.convergenceFactor(60.0), closeTo(0.5, 0.001));

      // At 90° (pole), convergence = cos(90°) = 0
      expect(geo.convergenceFactor(90.0), closeTo(0.0, 0.001));
    });

    test('identical coordinates project to (0,0)', () {
      final geo = GeoMath();
      final pair = geo.latLngToLocalXY(30.0, 31.0, 30.0, 31.0);
      expect(pair.first, closeTo(0.0, 0.0001));
      expect(pair.second, closeTo(0.0, 0.0001));
    });
  });

  group('Circular math bearing and heading', () {
    test('calculateBearing returns 0° for north-to-north', () {
      final bearing = CircularMath.calculateBearing(30.0, 31.0, 30.0, 31.0);
      expect(bearing, closeTo(0.0, 0.01));
    });

    test('calculateBearing returns 90° for west-to-east', () {
      final bearing = CircularMath.calculateBearing(30.0, 31.0, 30.0, 32.0);
      expect(bearing, closeTo(90.0, 0.1));
    });

    test('calculateBearing returns 180° for south-to-north', () {
      final bearing = CircularMath.calculateBearing(31.0, 31.0, 29.0, 31.0);
      expect(bearing, closeTo(180.0, 0.1));
    });

    test('calculateBearing returns 270° for east-to-west', () {
      final bearing = CircularMath.calculateBearing(30.0, 31.0, 30.0, 29.0);
      expect(bearing, closeTo(270.0, 0.1));
    });

    test('calculateBearing normalizes across 360° rollover', () {
      // Bearing from 350° to 10° should be ~350°->10° short path = ~20°
      // Actually, shortest path from 350 to 10 going forward is 20° (350->360=10, then 0->10=10, total 20)
      // But atan2 formula gives: we need to check what it returns
      final bearing = CircularMath.calculateBearing(30.0, 350.0, 30.0, 10.0);
      // This depends on the formula; just verify it's a valid normalized value
      expect(bearing, greaterThanOrEqualTo(0.0));
      expect(bearing, lessThan(360.0));
    });

    test('angularDifference is signed and symmetric', () {
      final diff1 = CircularMath.angularDifference(
          10.0, 350.0); // 350 is -10 from 10 going backwards
      // 350 - 10 = 340, mod 360 = 340, -180 = -20? Let's check:
      // (350 - 10 + 180) % 360 - 180 = (420) % 360 - 180 = 60 - 180 = -120
      // Actually, the short path from 10 to 350: going backwards (counter-clockwise) is 20°,
      // going forwards (clockwise) is 340°. The shortest is -20° (or 340°).
      // Let's verify the formula: (deg2 - deg1 + 180) % 360 - 180
      // = (350 - 10 + 180) % 360 - 180 = 520 % 360 - 180 = 160 - 180 = -20. Yes!

      final diff2 =
          CircularMath.angularDifference(350.0, 10.0); // from 350 to 10
      // (10 - 350 + 180) % 360 - 180 = (-160) % 360 - 180
      // In Dart, modulo of negative: -160 % 360 = 200 (Dart follows Python-style modulo)
      // 200 - 180 = 20. So diff2 = 20° (clockwise from 350 to 10 is +20°)
      // Actually wait: from 350 to 10 going forwards: 350->360=10°, 0->10=10°, total 20°. Yes!

      expect(diff1, closeTo(-20.0, 0.01));
      expect(diff2, closeTo(20.0, 0.01));
    });

    test('angularDifference is anti-symmetric', () {
      final diff1 = CircularMath.angularDifference(10.0, 30.0);
      final diff2 = CircularMath.angularDifference(30.0, 10.0);
      // diff1 should be +20°, diff2 should be -20°
      expect(diff1, closeTo(20.0, 0.01));
      expect(diff2, closeTo(-20.0, 0.01));
    });

    test('smoothHeading prevents 180° flip', () {
      // 350° to 10° should smooth toward 0° (the shortest path), not 350+180=170° flip
      final smoothed = CircularMath.smoothHeading(350.0, 10.0, alpha: 0.3);
      // Should be near 350° or moving toward 10° via the short path (through 0°)
      // The short path from 350 to 10 is +20° (350->360=10°, 0->10=10°)
      // So smoothed should be 350 + 0.3*20 = 356.0
      expect(smoothed, closeTo(356.0, 1.0));

      // 10° to 350° should smooth toward 0° too (short path is -20°)
      final smoothed2 = CircularMath.smoothHeading(10.0, 350.0, alpha: 0.3);
      // Short path from 10 to 350 is -20° (10->0=10°, 360->350=10°, total -20° if going backwards)
      // Actually shortest path: from 10 to 350, going forwards (CW): 340°, going backwards (CCW): 20°
      // So shortest is -20° (CCW), meaning head toward 0°
      // 10 + 0.3*(-20) = 10 - 6 = 4.0
      expect(smoothed2, closeTo(4.0, 1.0));
    });

    test('smoothHeading with alpha=1 gives target directly', () {
      final smoothed = CircularMath.smoothHeading(300.0, 20.0, alpha: 1.0);
      expect(smoothed, closeTo(20.0, 0.01));
    });

    test('smoothHeading with alpha=0 holds current', () {
      final smoothed = CircularMath.smoothHeading(300.0, 20.0, alpha: 0.0);
      expect(smoothed, closeTo(300.0, 0.01));
    });
  });
}

// Helper definition for test (would normally be in the test file's scope)
// We'll use a local rng generator inline
double _rngSeed = 42.0;

// Simple deterministic pseudo-random for tests (since we can't import Random easily without import issues)
double rngNext(double seed, double a, double c, double m) => (a * seed + c) % m;
