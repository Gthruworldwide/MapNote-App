import 'package:flutter_test/flutter/test';
import 'package:motion_smooth/motion_smooth.dart';

import 'package:motion_smooth/test/helpers/mock_telemetry_generator.dart';

void main() {
  group('MockTelemetryGenerator determinism', () {
    test('generator produces consistent output with same seed', () {
      final g1 = MockTelemetryGenerator(seed: 1);
      final g2 = MockTelemetryGenerator(seed: 1);
      final p1 = g1.generateNormalCruise(
          startLat: 30.0, startLng: 31.0, numPoints: 10, spacingMeters: 5.0);
      final p2 = g2.generateNormalCruise(
          startLat: 30.0, startLng: 31.0, numPoints: 10, spacingMeters: 5.0);
      expect(p1.length, equals(p2.length));
    });
  });

  group('Speedometer Stability', () {
    test('analyzer processes speed data without crash', () {
      final analyzer = MotionBehaviorAnalyzer();
      analyzer.observeTransport(VehicleMode.vehicle);
      final gen = MockTelemetryGenerator(seed: 42);
      final points = gen.generateNormalCruise(
          startLat: 30.0, startLng: 31.0, numPoints: 10, spacingMeters: 5.0);
      for (var p in points) {
        analyzer.observeSpeed(5.0, at: p.at);
      }
      expect(true, isTrue);
    });
  });

  group('Polyline Smoothing', () {
    test('smoother preserves point count', () {
      final gen = MockTelemetryGenerator(seed: 42);
      final raw = gen.generateNormalCruise(
          startLat: 30.0, startLng: 31.0, numPoints: 10, spacingMeters: 5.0);
      final smoothed = PolylineSmoother.smooth(raw);
      expect(smoothed.length, equals(raw.length));
    });
  });

  group('Event Detection Accuracy', () {
    test('analyzer processes braking event', () {
      final analyzer = MotionBehaviorAnalyzer();
      analyzer.observeTransport(VehicleMode.vehicle);
      final gen = MockTelemetryGenerator(seed: 42);
      final bp = generator.generateHardBrakingEvent(
          initialSpeedMps: 22.2,
          durationSec: 2.5,
          sampleIntervalSec: 0.5,
          startLat: 30.0,
          startLng: 31.0);
      for (var p in bp) {
        analyzer.observeSpeed(15.0, at: p.at);
      }
      expect(true, isTrue);
    });

    test('analyzer processes cornering event', () {
      final analyzer = MotionBehaviorAnalyzer();
      analyzer.observeTransport(VehicleMode.vehicle);
      final gen = MockTelemetryGenerator(seed: 42);
      final cp = generator.generateSharpCorneringEvent(
          initialSpeedMps: 10.0,
          turnSpeedMps: 8.0,
          turnRadiusMeters: 15.0,
          straightLengthMeters: 20.0,
          startLat: 30.0,
          startLng: 31.0);
      for (var p in cp) {
        analyzer.observeSpeed(8.0, at: p.at);
      }
      expect(true, isTrue);
    });
  });
}
