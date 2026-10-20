import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:routenote/src/core/security/device_lock_detector.dart';
import 'package:routenote/src/core/security/session_guard.dart';
import 'package:routenote/src/services/motion_sensor_hub.dart';

/// A hub that is never started; tests drive the detector through its stream
/// override or `handleSample` directly, so no platform channel is involved.
MotionSensorHub _hub() => MotionSensorHub();

/// A phone lying perfectly still on a solid surface: gravity, no tremor.
AccelerometerSample _stillSample(DateTime at) =>
    AccelerometerSample(0, 0, 9.81, at);

/// A hand-held phone: gravity plus a small hand tremor.
AccelerometerSample _tremorSample(int index, DateTime at) {
  final double t = index * 0.02;
  final double tremor = 0.45 * math.sin(2 * math.pi * 3.1 * t) +
      0.3 * math.sin(2 * math.pi * 5.7 * t + 0.7);
  return AccelerometerSample(tremor, 0.25 * tremor, 9.81 + tremor, at);
}

void main() {
  final DateTime epoch = DateTime.utc(2026, 1, 1);

  group('verdict', () {
    test('starts unknown and reports hand-held until proven otherwise', () {
      final DeviceLockDetector detector = DeviceLockDetector(hub: _hub());

      expect(detector.context, InteractionContext.unknown);
      // `unknown` must never be read as "surface idle": a broken sensor must
      // not shorten the vault's window.
      expect(detector.isHandHeld, isTrue);
    });

    test('a still device becomes surface-idle only after the threshold',
        () {
      final DeviceLockDetector detector = DeviceLockDetector(
        hub: _hub(),
        stillnessThreshold: const Duration(seconds: 20),
      );

      detector.handleSample(_stillSample(epoch), at: epoch);
      expect(detector.context, InteractionContext.handHeld);

      // 10 s of stillness is not enough: people hold a phone still to read.
      detector.handleSample(_stillSample(epoch.add(const Duration(seconds: 10))),
          at: epoch.add(const Duration(seconds: 10)));
      expect(detector.context, InteractionContext.handHeld);

      // Past the threshold the phone has been put down.
      final DateTime far = epoch.add(const Duration(seconds: 21));
      detector.handleSample(_stillSample(far), at: far);
      expect(detector.context, InteractionContext.surfaceIdle);
      expect(detector.isHandHeld, isFalse);
    });

    test('hand tremor keeps the verdict hand-held indefinitely', () {
      final DeviceLockDetector detector = DeviceLockDetector(
        hub: _hub(),
        stillnessThreshold: const Duration(seconds: 20),
      );

      for (int index = 0; index < 50 * 60; index++) {
        final DateTime at = epoch.add(Duration(milliseconds: index * 20));
        detector.handleSample(_tremorSample(index, at), at: at);
      }

      expect(detector.context, InteractionContext.handHeld);
    });

    test('picking a surface-idle device back up restores hand-held', () {
      final DeviceLockDetector detector = DeviceLockDetector(
        hub: _hub(),
        stillnessThreshold: const Duration(seconds: 20),
      );

      final DateTime down = epoch.add(const Duration(seconds: 30));
      detector.handleSample(_stillSample(epoch), at: epoch);
      detector.handleSample(_stillSample(down), at: down);
      expect(detector.context, InteractionContext.surfaceIdle);

      // One real movement sample is enough to clear the verdict.
      final DateTime lifted = down.add(const Duration(seconds: 1));
      detector.handleSample(
        AccelerometerSample(3.5, 2.0, 8.0, lifted),
        at: lifted,
      );
      expect(detector.context, InteractionContext.handHeld);
    });

    test('a large re-orientation counts as movement', () {
      final DeviceLockDetector detector = DeviceLockDetector(
        hub: _hub(),
        stillnessThreshold: const Duration(seconds: 20),
      );

      // Flat on a table.
      detector.handleSample(_stillSample(epoch), at: epoch);
      final DateTime later = epoch.add(const Duration(seconds: 30));
      detector.handleSample(_stillSample(later), at: later);
      expect(detector.context, InteractionContext.surfaceIdle);

      // Rotated onto its edge: same magnitude, different direction. The
      // residual is tiny but the orientation drift is 90°.
      final DateTime rotated = later.add(const Duration(seconds: 1));
      detector.handleSample(
        AccelerometerSample(9.81, 0, 0, rotated),
        at: rotated,
      );
      expect(detector.context, InteractionContext.handHeld);
    });

    test('reset clears the evidence back to unknown', () {
      final DeviceLockDetector detector = DeviceLockDetector(hub: _hub());

      detector.handleSample(_stillSample(epoch), at: epoch);
      expect(detector.sampleCount, 1);

      detector.reset();
      expect(detector.context, InteractionContext.unknown);
      expect(detector.sampleCount, 0);
    });
  });

  group('context changes', () {
    test('emits only on an actual transition', () async {
      final DeviceLockDetector detector = DeviceLockDetector(
        hub: _hub(),
        stillnessThreshold: const Duration(seconds: 20),
      );
      final List<InteractionContext> seen = <InteractionContext>[];
      final StreamSubscription<InteractionContext> subscription =
          detector.contextChanges.listen(seen.add);
      addTearDown(subscription.cancel);

      // First sample: unknown → handHeld is a change.
      detector.handleSample(_stillSample(epoch), at: epoch);
      // Still within the threshold: no change, so no extra emission.
      detector.handleSample(_stillSample(epoch.add(const Duration(seconds: 5))),
          at: epoch.add(const Duration(seconds: 5)));
      // Past the threshold: handHeld → surfaceIdle.
      final DateTime idle = epoch.add(const Duration(seconds: 25));
      detector.handleSample(_stillSample(idle), at: idle);
      // Still idle: no repeat.
      detector.handleSample(_stillSample(idle.add(const Duration(seconds: 5))),
          at: idle.add(const Duration(seconds: 5)));

      await Future<void>.delayed(Duration.zero);
      expect(seen, <InteractionContext>[
        InteractionContext.handHeld,
        InteractionContext.surfaceIdle,
      ]);
    });

    test('reset publishes the return to unknown', () async {
      final DeviceLockDetector detector = DeviceLockDetector(hub: _hub());
      final List<InteractionContext> seen = <InteractionContext>[];
      final StreamSubscription<InteractionContext> subscription =
          detector.contextChanges.listen(seen.add);
      addTearDown(subscription.cancel);

      detector.handleSample(_stillSample(epoch), at: epoch);
      detector.reset();

      await Future<void>.delayed(Duration.zero);
      expect(seen.last, InteractionContext.unknown);
    });
  });

  group('stream wiring', () {
    test('start listens to the injected stream and stop cancels it', () async {
      final StreamController<AccelerometerSample> source =
          StreamController<AccelerometerSample>();
      final DeviceLockDetector detector = DeviceLockDetector(
        hub: _hub(),
        accelerationStream: source.stream,
      );

      await detector.start();
      expect(detector.isRunning, isTrue);

      final DateTime down = epoch.add(const Duration(seconds: 30));
      source.add(_stillSample(epoch));
      source.add(_stillSample(down));
      await Future<void>.delayed(Duration.zero);

      expect(detector.context, InteractionContext.surfaceIdle);

      await detector.stop();
      expect(detector.isRunning, isFalse);

      // No further samples are observed after stopping.
      final int seen = detector.sampleCount;
      source.add(_stillSample(down.add(const Duration(seconds: 1))));
      await Future<void>.delayed(Duration.zero);
      expect(detector.sampleCount, seen);

      await source.close();
    });

    test('start is idempotent', () async {
      final StreamController<AccelerometerSample> source =
          StreamController<AccelerometerSample>();
      final DeviceLockDetector detector = DeviceLockDetector(
        hub: _hub(),
        accelerationStream: source.stream,
      );

      await detector.start();
      await detector.start();
      expect(detector.isRunning, isTrue);

      await detector.dispose();
      expect(detector.isRunning, isFalse);
      await source.close();
    });
  });
}
