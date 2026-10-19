import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:routenote/src/core/sensors/gravity_alignment_calculator.dart';
import 'package:routenote/src/features/motion_analytics/domain/entities/motion_window.dart';

/// Feeds the same reading [count] times so the low-pass filter settles on it.
void _settle(
  GravityAlignmentCalculator calculator,
  double x,
  double y,
  double z, {
  int count = 40,
}) {
  for (int index = 0; index < count; index++) {
    calculator.addSample(x, y, z);
  }
}

void main() {
  group('GravityAlignmentCalculator gravity estimate', () {
    test('seeds from the first sample instead of starting at zero', () {
      final GravityAlignmentCalculator calculator =
          GravityAlignmentCalculator();

      calculator.addSample(0, 0, 9.81);

      expect(calculator.sampleCount, 1);
      expect(calculator.gravity[2], closeTo(9.81, 1e-9));
      expect(calculator.gravityMagnitude, closeTo(9.81, 1e-9));
    });

    test('low-pass filters toward a steady reading', () {
      final GravityAlignmentCalculator calculator =
          GravityAlignmentCalculator(gravityAdaptation: 0.1);

      _settle(calculator, 0, 0, 9.81, count: 100);

      expect(calculator.gravityMagnitude, closeTo(9.81, 0.01));
      expect(calculator.gravity[2], closeTo(9.81, 0.01));
    });

    test('ignores a vibration spike instead of tracking it', () {
      final GravityAlignmentCalculator calculator =
          GravityAlignmentCalculator(gravityAdaptation: 0.1);
      _settle(calculator, 0, 0, 9.81, count: 100);

      // One hard bump sample: a real maneuver, so the estimate must not move
      // toward it at all — following the spike would drag the reference frame
      // into the bump and cancel it out.
      calculator.addSample(0, 40, 9.81);

      expect(calculator.gravity[1], closeTo(0, 1e-9));
      expect(calculator.gravityMagnitude, closeTo(9.81, 1e-9));
      expect(calculator.isAligned, isTrue);
    });

    test('re-learns a cradle re-seated gradually', () {
      final GravityAlignmentCalculator calculator =
          GravityAlignmentCalculator(gravityAdaptation: 0.1);
      _settle(calculator, 0, 0, 9.81, count: 100);

      // The phone sags slowly into a new tilt while parked: each step is small
      // relative to the current estimate, so the at-rest path tracks it.
      const int steps = 60;
      for (int index = 1; index <= steps; index++) {
        final double y = 4.0 * index / steps;
        _settle(calculator, 0, y, math.sqrt(9.81 * 9.81 - y * y), count: 60);
      }

      final VehicleFrame frame = calculator.frame!;
      expect(frame.yAxis[1], closeTo(4.0 / 9.81, 0.02));
    });

    test('a sustained maneuver never re-trains the frame', () {
      final GravityAlignmentCalculator calculator =
          GravityAlignmentCalculator(gravityAdaptation: 0.1);
      _settle(calculator, 0, 0, 9.81, count: 100);

      // A hard, perfectly steady 4 m/s² brake for a full window: the estimate
      // must not creep toward it, or the maneuver would cancel itself out.
      _settle(calculator, 0, -4.0, 9.81, count: MotionWindow.sampleCount);

      expect(calculator.gravity[1], closeTo(0, 1e-9));
      final VehicleAcceleration reading = calculator.transform(0, -4.0, 9.81)!;
      expect(reading.longitudinal, closeTo(-4.0, 1e-6));
      expect(reading.vertical, closeTo(0, 1e-6));
    });

    test('reset forgets the estimate and the frame', () {
      final GravityAlignmentCalculator calculator =
          GravityAlignmentCalculator();
      _settle(calculator, 0, 0, 9.81);
      expect(calculator.isAligned, isTrue);

      calculator.reset();

      expect(calculator.isAligned, isFalse);
      expect(calculator.sampleCount, 0);
      expect(calculator.gravityMagnitude, 0);
      expect(calculator.gravity, <double>[0, 0, 0]);
    });
  });

  group('GravityAlignmentCalculator frame', () {
    test('stays unaligned until enough samples have arrived', () {
      final GravityAlignmentCalculator calculator =
          GravityAlignmentCalculator(minSamples: 20);

      for (int index = 0; index < 19; index++) {
        calculator.addSample(0, 0, 9.81);
      }

      expect(calculator.isAligned, isFalse);
      expect(calculator.frame, isNull);
      expect(calculator.transform(0, 0, 9.81), isNull);
    });

    test('refuses free-fall and impossible gravity', () {
      final GravityAlignmentCalculator calculator =
          GravityAlignmentCalculator();

      // A falling device: nothing to align to, and no frame may be published.
      _settle(calculator, 0, 0, 1.0, count: 40);
      expect(calculator.isAligned, isFalse);

      final GravityAlignmentCalculator impossible =
          GravityAlignmentCalculator();
      _settle(impossible, 0, 0, 40.0, count: 40);
      expect(impossible.isAligned, isFalse);
    });

    test('refuses a cradle that points along gravity', () {
      // Phone on its end: the +y forward axis is parallel to gravity, so
      // heading is unobservable and no frame may be invented.
      final GravityAlignmentCalculator calculator = GravityAlignmentCalculator(
        mounting: DeviceMounting.deviceY,
      );

      _settle(calculator, 0, 9.81, 0);

      expect(calculator.isAligned, isFalse);
      expect(calculator.frame, isNull);
    });

    test('publishes an orthonormal, right-handed rotation', () {
      final GravityAlignmentCalculator calculator =
          GravityAlignmentCalculator();
      // Tilted 20° about the device's x axis: gravity keeps a y component.
      _settle(calculator, 0, 9.81 * math.sin(0.35), 9.81 * math.cos(0.35));

      final VehicleFrame frame = calculator.frame!;
      for (final List<double> axis in <List<double>>[
        frame.xAxis,
        frame.yAxis,
        frame.zAxis,
      ]) {
        expect(_length(axis), closeTo(1.0, 1e-9));
      }
      expect(_dot(frame.xAxis, frame.yAxis), closeTo(0.0, 1e-9));
      expect(_dot(frame.yAxis, frame.zAxis), closeTo(0.0, 1e-9));
      expect(_dot(frame.xAxis, frame.zAxis), closeTo(0.0, 1e-9));
      expect(frame.determinant, closeTo(1.0, 1e-9));
      expect(frame.matrix.length, 9);
    });

    test('vertical axis follows the measured gravity direction', () {
      final GravityAlignmentCalculator calculator =
          GravityAlignmentCalculator();
      // Device rolled: gravity now leans on the device's x axis.
      _settle(calculator, 9.81 * 0.5, 0, 9.81 * math.sqrt(3) / 2);

      final VehicleFrame frame = calculator.frame!;
      expect(frame.yAxis[0], closeTo(0.5, 1e-6));
      expect(frame.yAxis[2], closeTo(math.sqrt(3) / 2, 1e-6));
    });
  });

  group('GravityAlignmentCalculator transform', () {
    test('flat portrait cradle: forward on Z, driver-left on X, up on Y', () {
      final GravityAlignmentCalculator calculator =
          GravityAlignmentCalculator();

      _settle(calculator, 0, 0, 9.81); // screen up, top of phone forward

      final VehicleFrame frame = calculator.frame!;
      // Y_car is the device's up axis.
      expect(frame.yAxis, <double>[0, 0, 1]);
      // Z_car is the device's forward (+y) axis.
      expect(frame.zAxis[0], closeTo(0, 1e-9));
      expect(frame.zAxis[1], closeTo(1, 1e-9));
      expect(frame.zAxis[2], closeTo(0, 1e-9));
      // X_car = Y × Z closes the right-handed triad: the device's -x.
      expect(frame.xAxis[0], closeTo(-1, 1e-9));
    });

    test('gravity itself projects to zero, so only dynamics remain', () {
      final GravityAlignmentCalculator calculator =
          GravityAlignmentCalculator();
      _settle(calculator, 0, 0, 9.81);

      final VehicleAcceleration atRest = calculator.transform(0, 0, 9.81)!;

      expect(atRest.longitudinal, closeTo(0, 1e-6));
      expect(atRest.lateral, closeTo(0, 1e-6));
      expect(atRest.vertical, closeTo(0, 1e-6));
    });

    test('accelerating reads positive longitudinal, braking negative', () {
      final GravityAlignmentCalculator calculator =
          GravityAlignmentCalculator();
      _settle(calculator, 0, 0, 9.81);

      // The car accelerates forward: the device's forward axis (+y) reads
      // gravity plus the push.
      final VehicleAcceleration accelerating =
          calculator.transform(0, 3.0, 9.81)!;
      expect(accelerating.longitudinal, closeTo(3.0, 1e-6));
      expect(accelerating.lateral, closeTo(0, 1e-6));

      final VehicleAcceleration braking = calculator.transform(0, -3.0, 9.81)!;
      expect(braking.longitudinal, closeTo(-3.0, 1e-6));
    });

    test('a right-hand turn reads negative lateral (left is positive)', () {
      final GravityAlignmentCalculator calculator =
          GravityAlignmentCalculator();
      _settle(calculator, 0, 0, 9.81);

      // Turning right, the phone is pushed toward the device's +x.
      final VehicleAcceleration rightTurn =
          calculator.transform(2.5, 0, 9.81)!;
      expect(rightTurn.lateral, closeTo(-2.5, 1e-6));

      final VehicleAcceleration leftTurn =
          calculator.transform(-2.5, 0, 9.81)!;
      expect(leftTurn.lateral, closeTo(2.5, 1e-6));
    });

    test('a bump reads positive vertical, a pothole negative', () {
      final GravityAlignmentCalculator calculator =
          GravityAlignmentCalculator();
      _settle(calculator, 0, 0, 9.81);

      final VehicleAcceleration bump = calculator.transform(0, 0, 14.0)!;
      expect(bump.vertical, closeTo(4.19, 1e-6));
      expect(bump.longitudinal, closeTo(0, 1e-6));

      final VehicleAcceleration pothole = calculator.transform(0, 0, 4.0)!;
      expect(pothole.vertical, closeTo(-5.81, 1e-6));
    });

    test('a landscape cradle keeps forward on Z_car', () {
      final GravityAlignmentCalculator calculator =
          GravityAlignmentCalculator(mounting: DeviceMounting.deviceX);
      _settle(calculator, 0, 0, 9.81);

      // Landscape: the device's +x faces forward.
      final VehicleAcceleration accelerating =
          calculator.transform(3.0, 0, 9.81)!;
      expect(accelerating.longitudinal, closeTo(3.0, 1e-6));
    });

    test('removes gravity even when the cradle is tilted', () {
      final GravityAlignmentCalculator calculator =
          GravityAlignmentCalculator();
      const double tilt = 0.35;
      final double gx = 9.81 * math.sin(tilt);
      final double gz = 9.81 * math.cos(tilt);
      _settle(calculator, gx, 0, gz);

      // A rest position in that same tilt must read as no acceleration at all.
      final VehicleAcceleration atRest = calculator.transform(gx, 0, gz)!;
      expect(atRest.magnitude, lessThan(1e-6));

      // And a forward push must still land purely on the longitudinal axis.
      final VehicleAcceleration accelerating =
          calculator.transform(gx, 2.0, gz)!;
      expect(accelerating.longitudinal, closeTo(2.0, 1e-6));
      expect(accelerating.lateral, closeTo(0, 1e-6));
    });
  });
}

double _length(List<double> vector) =>
    math.sqrt(vector[0] * vector[0] + vector[1] * vector[1] + vector[2] * vector[2]);

double _dot(List<double> a, List<double> b) =>
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
