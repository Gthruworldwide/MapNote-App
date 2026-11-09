import 'dart:math' as math;
import 'package:flutter_test/flutter/test';
import 'package:motion_smooth/circular_math.dart';

void main() {
  group('CircularMath bearing calculations', () {
    test('calculateBearing across all quadrants', () {
      // North to North (same point)
      expect(CircularMath.calculateBearing(30.0, 31.0, 30.0, 31.0),
          closeTo(0.0, 0.01));

      // West to East (equator, 1° longitude)
      expect(CircularMath.calculateBearing(30.0, 31.0, 30.0, 32.0),
          closeTo(90.0, 0.1));

      // South to North
      expect(CircularMath.calculateBearing(31.0, 31.0, 29.0, 31.0),
          closeTo(180.0, 0.1));

      // East to West
      expect(CircularMath.calculateBearing(30.0, 31.0, 30.0, 29.0),
          closeTo(270.0, 0.1));
    });

    test('bearing normalizes to [0, 360)', () {
      // Test extreme values still produce valid normalized output
      final b = CircularMath.calculateBearing(0.0, 0.0, 0.0, 0.0);
      expect(b, greaterThanOrEqualTo(0.0));
      expect(b, lessThan(360.0));
    });

    test('angularDifference signed correctness', () {
      // From 10° to 30° should be +20° (clockwise)
      final diff1 = CircularMath.angularDifference(10.0, 30.0);
      expect(diff1, closeTo(20.0, 0.01));

      // From 30° to 10° should be -20° (counter-clockwise)
      final diff2 = CircularMath.angularDifference(30.0, 10.0);
      expect(diff2, closeTo(-20.0, 0.01));

      // Anti-symmetry: diff(a,b) = -diff(b,a)
      expect(diff1, closesPairWith(diff2 * -1));
    });

    test('angularDifference wrap-around', () {
      // From 350° to 10° should be +20° (crossing 0/360 boundary)
      final diff1 = CircularMath.angularDifference(350.0, 10.0);
      expect(diff1, closeTo(20.0, 0.01));

      // From 10° to 350° should be -20°
      final diff2 = CircularMath.angularDifference(10.0, 350.0);
      expect(diff2, closeTo(-20.0, 0.01));
    });

    test('smoothHeading rollover preservation', () {
      // 350° to 10° via short path (through 0°)
      final s1 = CircularMath.smoothHeading(350.0, 10.0, alpha: 0.5);
      // Short path: from 350 to 10 is +20°. 350 + 0.5*20 = 360.0 -> normalized to 0.0
      // Actually 350 + 10 = 360 -> 0. But let's compute: diff = 10 - 350 = -340, but shortest is +20
      // Our algorithm should find diff = +20, result = 350 + 0.5*20 = 360 -> 0
      expect(s1, closeTo(0.0, 1.0));

      // 10° to 350° via short path (through 0°, i.e., -20°)
      final s2 = CircularMath.smoothHeading(10.0, 350.0, alpha: 0.5);
      // Shortest path from 10 to 350 is -20° (going backwards through 0)
      // 10 + 0.5*(-20) = 0.0
      expect(s2, closeTo(0.0, 1.0));
    });

    test('smoothHeading alpha boundaries', () {
      // alpha = 0: hold current
      expect(CircularMath.smoothHeading(100.0, 200.0, alpha: 0.0),
          closeTo(100.0, 0.01));

      // alpha = 1: go to target directly
      expect(CircularMath.smoothHeading(100.0, 200.0, alpha: 1.0),
          closeTo(200.0, 0.01));
    });
  });
}
