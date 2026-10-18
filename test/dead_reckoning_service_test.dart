import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/services/dead_reckoning_service.dart';
import 'package:routenote/src/services/motion_sensor_hub.dart';

/// 16 Hz accelerometer cadence (62.5 ms), the Android UI sensor rate.
const Duration _sample16Hz = Duration(microseconds: 62500);

/// 4 Hz cadence (250 ms) — used for the very long history-spanning feed,
/// where 16 Hz would only make the test slower, and one predict step per
/// sample still honours the filter's 1 s maximum.
const Duration _sample4Hz = Duration(milliseconds: 250);

/// Lets queued stream events (broadcast controllers deliver asynchronously)
/// settle before assertions.
Future<void> _flush() => Future<void>.delayed(Duration.zero);

/// package:matcher ships no `isFinite` matcher; a tiny predicate instead.
final Matcher isFiniteValue =
    predicate<double>((double value) => value.isFinite, 'is finite');

/// A service over silent sensor streams: these tests drive [onAccelerometer]
/// / [onGyroscope] directly for deterministic, synchronous feeds.
DeadReckoningService _newService({
  Stream<AccelerometerSample>? accelerometer,
  Stream<GyroscopeSample>? gyroscope,
}) {
  return DeadReckoningService(
    accelerometer: accelerometer ?? Stream<AccelerometerSample>.empty(),
    gyroscope: gyroscope ?? Stream<GyroscopeSample>.empty(),
  );
}

/// Feeds [count] gravity-only samples with a fixed-seed jitter far below the
/// ZUPT threshold, plus a zeroed gyroscope — a phone lying on a desk.
void _feedRest(
  DeadReckoningService service, {
  required DateTime base,
  required int count,
  Duration step = _sample16Hz,
}) {
  int state = 7;
  for (int i = 0; i < count; i++) {
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF;
    final double jitter = (state / 0x100000000 * 2 - 1) * 0.02;
    final DateTime at = base.add(step * i);
    service.onAccelerometer(AccelerometerSample(0, 0, 9.81 + jitter, at));
    service.onGyroscope(GyroscopeSample(0, 0, 0, at));
  }
}

/// Feeds a sustained dynamic pattern that keeps ZUPT from firing: one neutral
/// sample seeds gravity at rest, then ±2 m/s² held for 0.5 s per direction —
/// far above the stillness threshold at every instant, while the 2 s gravity
/// low-pass keeps the mean (zero) as gravity and the square wave as residual.
/// The velocity ratchets forward instead of snapping to zero, so the anchored
/// trajectory gains ground every half-second.
void _feedSquareWave(
  DeadReckoningService service, {
  required DateTime base,
  required int count,
  Duration step = _sample16Hz,
}) {
  final int halfCycleSamples =
      const Duration(milliseconds: 500).inMicroseconds ~/
          step.inMicroseconds;
  for (int i = 0; i < count; i++) {
    double east = 0;
    if (i > 0) {
      final int block = (i - 1) ~/ halfCycleSamples;
      east = block.isEven ? 2.0 : -2.0;
    }
    service.onAccelerometer(
      AccelerometerSample(east, 0, 9.81, base.add(step * i)),
    );
  }
}

void main() {
  group('NoopDistanceEstimator', () {
    test('never vouches for a displacement, in either time direction', () {
      const DistanceEstimator estimator = NoopDistanceEstimator();
      final DateTime t0 = DateTime(2026, 10, 18, 12);
      expect(
        estimator.displacementKmBetween(
          t0,
          t0.add(const Duration(hours: 3)),
        ),
        0,
      );
      expect(
        estimator.displacementKmBetween(
          t0.add(const Duration(hours: 3)),
          t0,
        ),
        0,
      );
      expect(estimator.displacementKmBetween(t0, t0), 0);
    });
  });

  group('DeadReckoningService evidence contracts', () {
    test('a fresh estimator with no samples vouches for nothing', () async {
      final DeadReckoningService service = _newService();
      await service.start();
      expect(service.isRunning, isTrue);
      expect(service.anchorCount, 0);
      expect(service.lastUpdateAt, isNull);
      expect(service.estimatedEastM, 0);
      expect(service.estimatedNorthM, 0);
      expect(service.estimatedSpeedMps, 0);

      final DateTime t0 = DateTime(2026, 10, 18, 13);
      expect(
        service.displacementKmBetween(
          t0,
          t0.add(const Duration(minutes: 45)),
        ),
        0,
      );
      await service.stop();
      expect(service.isRunning, isFalse);
    });

    test('a stationary feed displaces (almost) nothing and stays finite',
        () async {
      final DeadReckoningService service = _newService();
      await service.start();
      final DateTime t0 = DateTime(2026, 10, 18, 14);

      // 4 s at 16 Hz of a phone at rest: gravity-only accelerometer and a
      // zeroed gyroscope.
      _feedRest(service, base: t0, count: 65);
      final DateTime tEnd = t0.add(_sample16Hz * 64);

      final double km = service.displacementKmBetween(t0, tEnd);
      expect(km, isFiniteValue);
      expect(km, greaterThanOrEqualTo(0));
      expect(km, lessThan(0.005)); // a few metres at the very most

      // Diagnostics stayed sane: anchors every 2 s, no NaN anywhere.
      expect(service.anchorCount, greaterThanOrEqualTo(3));
      expect(service.lastUpdateAt, tEnd);
      expect(service.estimatedEastM, isFiniteValue);
      expect(service.estimatedNorthM, isFiniteValue);
      expect(service.estimatedSpeedMps, isFiniteValue);
      await service.stop();
    });

    test('window edge rules refuse ranges the history cannot answer',
        () async {
      final DeadReckoningService service = _newService();
      await service.start();
      final DateTime t0 = DateTime(2026, 10, 18, 14);
      _feedRest(service, base: t0, count: 65);
      final DateTime tMid = t0.add(_sample16Hz * 32);

      // `to` before `from`: no time, no distance.
      expect(service.displacementKmBetween(tMid, t0), 0);

      // Equal instants: nothing moved between an instant and itself.
      expect(service.displacementKmBetween(t0, t0), 0);
      expect(service.displacementKmBetween(tMid, tMid), 0);

      // The window starts before the first anchor: the estimator never
      // extrapolates past what it sensed.
      expect(
        service.displacementKmBetween(
          t0.subtract(const Duration(seconds: 1)),
          t0.add(const Duration(seconds: 3)),
        ),
        0,
      );

      // A supported window inside the retained range still answers.
      expect(
        service.displacementKmBetween(t0, t0.add(const Duration(seconds: 4))),
        greaterThanOrEqualTo(0),
      );
      await service.stop();
    });

    test('a window starting before two-hour-old anchors is refused',
        () async {
      final DeadReckoningService service = _newService();
      await service.start();
      final DateTime t0 = DateTime(2026, 10, 18, 14);

      // 2 h + 60 s of sustained motion at 4 Hz: the anchor history (bounded
      // by maxHistory = 2 h) must have pruned the oldest anchors by now.
      final int count = (const Duration(hours: 2) + const Duration(minutes: 1))
              .inMicroseconds ~/
          _sample4Hz.inMicroseconds +
          1;
      expect(count, 29041); // 7260 s of 250 ms samples
      _feedSquareWave(service, base: t0, count: count, step: _sample4Hz);
      final DateTime tEnd = t0.add(_sample4Hz * (count - 1));
      expect(tEnd.difference(t0), const Duration(hours: 2) + const Duration(minutes: 1));

      // The oldest anchors fell out of the bounded history.
      final int anchorsWhileFeeding = (tEnd.difference(t0).inSeconds ~/ 2) + 1;
      expect(service.anchorCount, lessThan(anchorsWhileFeeding));

      // A window that starts before all retained evidence: refused (0), even
      // though the estimator was busy the whole time.
      expect(service.displacementKmBetween(t0, tEnd), 0);

      // A window fully inside the retained history still answers positively.
      final DateTime recent = tEnd.subtract(const Duration(minutes: 1));
      final double km = service.displacementKmBetween(recent, tEnd);
      expect(km, isFiniteValue);
      expect(km, greaterThan(0));
      expect(km, lessThan(5));
      await service.stop();
    });

    test('a sustained dynamic feed yields positive, finite, monotonic distance',
        () async {
      final DeadReckoningService service = _newService();
      await service.start();
      final DateTime t0 = DateTime(2026, 10, 18, 15);

      // 4 s of sustained horizontal acceleration at 16 Hz: the residual never
      // settles below the ZUPT threshold, so the filter is free to integrate.
      _feedSquareWave(service, base: t0, count: 65);
      final DateTime tEnd = t0.add(_sample16Hz * 64);

      final double full = service.displacementKmBetween(t0, tEnd);
      expect(full, isFiniteValue);
      expect(full, greaterThan(0));

      // A sub-window ending earlier never reports more distance than the
      // full window (monotonic accumulation).
      final double half =
          service.displacementKmBetween(t0, t0.add(const Duration(seconds: 2)));
      expect(half, isFiniteValue);
      expect(half, greaterThanOrEqualTo(0));
      expect(half, lessThanOrEqualTo(full));

      final double quarter = service.displacementKmBetween(
        t0,
        t0.add(const Duration(seconds: 1)),
      );
      expect(quarter, isFiniteValue);
      expect(quarter, lessThanOrEqualTo(full));

      expect(service.estimatedEastM, isFiniteValue);
      expect(service.estimatedNorthM, isFiniteValue);
      expect(service.estimatedSpeedMps, isFiniteValue);
      await service.stop();
    });
  });

  group('DeadReckoningService lifecycle', () {
    test('start is idempotent, stop releases and forgets, restart re-origins',
        () async {
      int accelListens = 0;
      int gyroListens = 0;
      final StreamController<AccelerometerSample> accelerometer =
          StreamController<AccelerometerSample>.broadcast(
        onListen: () => accelListens++,
      );
      final StreamController<GyroscopeSample> gyroscope =
          StreamController<GyroscopeSample>.broadcast(
        onListen: () => gyroListens++,
      );
      addTearDown(accelerometer.close);
      addTearDown(gyroscope.close);
      final DeadReckoningService service = DeadReckoningService(
        accelerometer: accelerometer.stream,
        gyroscope: gyroscope.stream,
      );

      expect(service.isRunning, isFalse);
      await service.start();
      await service.start(); // idempotent: no second subscription
      expect(service.isRunning, isTrue);
      expect(accelListens, 1);
      expect(gyroListens, 1);

      // The subscription carries real samples into the filter.
      final DateTime t0 = DateTime(2026, 10, 18, 16);
      accelerometer.add(AccelerometerSample(0, 0, 9.81, t0));
      gyroscope.add(GyroscopeSample(0, 0, 0, t0));
      await _flush();
      expect(service.lastUpdateAt, t0);
      expect(service.anchorCount, 1);

      // Stop cancels both streams and forgets every filter artefact.
      await service.stop();
      expect(service.isRunning, isFalse);
      expect(service.anchorCount, 0);
      expect(service.lastUpdateAt, isNull);
      expect(service.estimatedEastM, 0);
      expect(service.estimatedSpeedMps, 0);

      // Samples added after stop never reach the filter.
      accelerometer.add(
        AccelerometerSample(0, 0, 9.81, t0.add(const Duration(seconds: 10))),
      );
      await _flush();
      expect(service.lastUpdateAt, isNull);

      // The pre-stop anchors are gone, so that window vouches for nothing.
      expect(
        service.displacementKmBetween(
          t0,
          t0.add(const Duration(seconds: 10)),
        ),
        0,
      );

      // A restart re-subscribes once and begins from a clean origin.
      await service.start();
      expect(service.isRunning, isTrue);
      expect(accelListens, 2);
      expect(gyroListens, 2);
      final DateTime t1 = t0.add(const Duration(seconds: 20));
      accelerometer.add(AccelerometerSample(0, 0, 9.81, t1));
      await _flush();
      expect(service.lastUpdateAt, t1);
      expect(service.anchorCount, 1);
      await service.stop();
      expect(service.isRunning, isFalse);
    });
  });
}
