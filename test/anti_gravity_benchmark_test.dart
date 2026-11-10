import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:motion_smooth/motion_smooth.dart';
import 'package:routenote/src/features/anti_gravity/domain/anti_gravity_models.dart';
import 'package:routenote/src/features/anti_gravity/domain/anti_gravity_motion_adapter.dart';

void main() {
  group('AntiGravityMotionAdapter Stress & Benchmark Suite', () {
    late AntiGravityMotionAdapter adapter;
    const int testPointCount = 5000;

    setUp(() {
      adapter = AntiGravityMotionAdapter(
        config: const AntiGravityConfig(
          massKg: 1500.0,
          mode: AntiGravityMode.velocityLift,
          smoothingAlpha: 0.3,
          liftGain: 1.2,
          maneuverDamping: 0.6,
        ),
      );
    });

    test('Stress Test: Ingest and process 5,000 telemetry points (< 2.0 ms latency)', () {
      final points = <RoutePoint>[];
      final startTime = DateTime(2026, 11, 9, 12, 0, 0);

      // Generate 5,000 sequential high-frequency trajectory points with GPS noise
      const double centerLat = 30.0444;
      const double centerLng = 31.2357;

      for (int i = 0; i < testPointCount; i++) {
        final double t = i * 0.05; // 20 Hz telemetry rate
        final double jitterLat = (i % 2 == 0 ? 0.00004 : -0.00003) * math.sin(t * 3.7);
        final double jitterLng = (i % 3 == 0 ? -0.00005 : 0.00002) * math.cos(t * 2.9);

        final double lat = centerLat + 0.0001 * i + jitterLat;
        final double lng = centerLng + 0.00008 * i * math.sin(i * 0.01) + jitterLng;
        final timestamp = startTime.add(Duration(milliseconds: i * 50));

        points.add(RoutePoint(
          latitude: lat,
          longitude: lng,
          at: timestamp,
        ));
      }

      // Warmup phase (100 points)
      for (int i = 0; i < 100; i++) {
        adapter.processPoint(points[i]);
      }
      adapter.reset();

      // Benchmark timing
      final pointLatencies = <double>[];
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < testPointCount; i++) {
        final pointTimer = Stopwatch()..start();
        final state = adapter.processPoint(points[i]);
        pointTimer.stop();

        pointLatencies.add(pointTimer.elapsedMicroseconds / 1000.0);

        // Verify mathematical consistency on every 100th point
        if (i % 100 == 0) {
          final expectedFNet = (state.accelerationVector - state.antiGravityVector) *
              adapter.config.massKg;
          expect(
            (state.netForce - expectedFNet).length,
            lessThan(1e-5),
            reason: 'F_net must strictly satisfy m * (a_motion - g_anti)',
          );
        }
      }

      stopwatch.stop();

      final totalElapsedMs = stopwatch.elapsedMilliseconds;
      final avgLatencyMs = totalElapsedMs / testPointCount;
      pointLatencies.sort();
      final p50 = pointLatencies[(testPointCount * 0.50).toInt()];
      final p95 = pointLatencies[(testPointCount * 0.95).toInt()];
      final p99 = pointLatencies[(testPointCount * 0.99).toInt()];

      // Print comprehensive benchmark report
      // ignore: avoid_print
      print('''
===============================================================
🚀 ANTI-GRAVITY MOTION PIPELINE BENCHMARK (5,000 Points)
===============================================================
Total Points Processed:   $testPointCount
Total Pipeline Time:      $totalElapsedMs ms
Average Processing Latency: ${avgLatencyMs.toStringAsFixed(4)} ms / point
50th Percentile (p50):    ${p50.toStringAsFixed(4)} ms
95th Percentile (p95):    ${p95.toStringAsFixed(4)} ms
99th Percentile (p99):    ${p99.toStringAsFixed(4)} ms
Throughput:               ${(testPointCount / (totalElapsedMs / 1000.0)).toStringAsFixed(0)} points/sec
Target Threshold:         < 2.0 ms
Result:                   ${avgLatencyMs < 2.0 ? 'PASSED ✅' : 'FAILED ❌'}
===============================================================
''');

      // Requirement: average latency must be strictly less than 2.0 ms
      expect(avgLatencyMs, lessThan(2.0),
          reason: 'Average processing latency per point must be under 2.0 ms');
    });

    test('Kinematic Transform & Gravity Compensation Verification', () {
      adapter.updateConfig(
        const AntiGravityConfig(
          massKg: 1000.0,
          mode: AntiGravityMode.microGravity,
        ),
      );

      final now = DateTime.now();
      final p1 = RoutePoint(latitude: 30.0, longitude: 31.0, at: now);
      final p2 = RoutePoint(
        latitude: 30.0001,
        longitude: 31.0,
        at: now.add(const Duration(milliseconds: 100)),
      );

      adapter.processPoint(p1);
      final state2 = adapter.processPoint(p2, overrideSpeedMps: 20.0);

      // In Micro-Gravity mode, apparent weight should drop to ~5% of mass (50 kg)
      expect(state2.apparentWeightKg, lessThan(100.0));
      expect(state2.weightRatio, lessThan(10.0));

      // Test formula: F_net = m * (a - g_anti)
      final calculatedFNet =
          (state2.accelerationVector - state2.antiGravityVector) * 1000.0;
      expect((state2.netForce - calculatedFNet).length, lessThan(1e-5));
    });

    test('Maneuver Detection triggers during harsh braking', () {
      adapter.updateConfig(
        const AntiGravityConfig(
          massKg: 1200.0,
          mode: AntiGravityMode.earthNormal,
        ),
      );

      final now = DateTime.now();
      // Fast speed fix
      adapter.processPoint(
        RoutePoint(latitude: 30.0, longitude: 31.0, at: now),
        overrideSpeedMps: 30.0,
      );

      // Sudden hard brake (decelerates from 30 m/s to 5 m/s in 0.5s -> -50 m/s²)
      final brakeState = adapter.processPoint(
        RoutePoint(
          latitude: 30.0001,
          longitude: 31.0,
          at: now.add(const Duration(milliseconds: 500)),
        ),
        overrideSpeedMps: 5.0,
      );

      expect(brakeState.activeManeuvers, contains(DrivingEventType.harshBraking));
    });
  });
}
