import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:routenote/src/core/motion/activity_state_manager.dart';
import 'package:routenote/src/core/motion/motion_gate.dart';
import 'package:routenote/src/services/motion_sensor_hub.dart';

/// A hub that is never started, so its own accelerometer stream stays silent.
/// Tests drive the gate either through `feed` or through the
/// `accelerationStream` override.
MotionSensorHub _hub() => MotionSensorHub();

/// A driving sample: gravity plus broadband (non-gait) rumble.
AccelerometerSample _driveSample(int index, DateTime start) {
  final double t = index * 0.02;
  final double rumble = 1.1 * math.sin(2 * math.pi * 7.3 * t) +
      0.9 * math.sin(2 * math.pi * 11.7 * t + 1.1) +
      0.7 * math.sin(2 * math.pi * 4.1 * t + 2.3);
  return AccelerometerSample(
    0,
    0,
    9.81 + rumble,
    start.add(Duration(milliseconds: index * 20)),
  );
}

/// A walking sample: a 2 Hz gait at vehicle-range amplitude, no vehicle band.
AccelerometerSample _walkSample(int index, DateTime start) => AccelerometerSample(
      0,
      0,
      9.81 + 2.5 * math.sin(2 * math.pi * 2.0 * index * 0.02),
      start.add(Duration(milliseconds: index * 20)),
    );

/// Feeds [count] samples of a confirmed drive through [gate], fusing the
/// Doppler speed the gate's speed test needs.
void _feedDrive(MotionGate gate, ActivityStateManager manager, DateTime start,
    {int count = 50 * 20}) {
  for (int index = 0; index < count; index++) {
    final AccelerometerSample sample = _driveSample(index, start);
    manager.observeSpeed(12, at: sample.at);
    gate.feed(sample);
  }
}

void main() {
  final DateTime epoch = DateTime.utc(2026, 1, 1);

  group('cold gate', () {
    test('starts closed, watching nothing', () {
      final ActivityStateManager manager = ActivityStateManager(clock: () => epoch);
      final MotionGate gate =
          MotionGate(manager: manager, hub: _hub());

      expect(gate.isRunning, isFalse);
      expect(gate.allowsAnalysis, isFalse);
      expect(gate.forwardedSamples, 0);
    });
  });

  group('walking is withheld entirely', () {
    test('walking forwards nothing at all', () async {
      final ActivityStateManager manager = ActivityStateManager(clock: () => epoch);
      final MotionGate gate =
          MotionGate(manager: manager, hub: _hub());
      final List<AccelerometerSample> received = <AccelerometerSample>[];
      final subscription = gate.gated.listen(received.add);

      await gate.start();
      for (int index = 0; index < 50 * 20; index++) {
        gate.feed(_walkSample(index, epoch));
      }
      await Future<void>.delayed(Duration.zero);

      // The whole point: indoors the analytics pipeline receives *zero* samples.
      expect(gate.allowsAnalysis, isFalse);
      expect(gate.forwardedSamples, 0);
      expect(gate.suppressedSamples, 50 * 20);
      expect(received, isEmpty);
      await subscription.cancel();
      await gate.dispose();
    });
  });

  group('a confirmed drive flows through', () {
    test('samples reach the gated consumer', () async {
      final ActivityStateManager manager = ActivityStateManager(clock: () => epoch);
      final MotionGate gate =
          MotionGate(manager: manager, hub: _hub());
      final List<AccelerometerSample> received = <AccelerometerSample>[];
      final subscription = gate.gated.listen(received.add);

      await gate.start();
      _feedDrive(gate, manager, epoch);
      await Future<void>.delayed(Duration.zero);

      expect(gate.allowsAnalysis, isTrue);
      expect(gate.forwardedSamples, greaterThan(0));
      expect(received.length, gate.forwardedSamples);
      await subscription.cancel();
      await gate.dispose();
    });

    test('suspend closes the gate immediately and the next sample is withheld',
        () async {
      final ActivityStateManager manager = ActivityStateManager(clock: () => epoch);
      final MotionGate gate =
          MotionGate(manager: manager, hub: _hub());

      await gate.start();
      _feedDrive(gate, manager, epoch);
      expect(gate.allowsAnalysis, isTrue);
      final int afterDrive = gate.forwardedSamples;

      gate.suspend();
      expect(gate.allowsAnalysis, isFalse);
      expect(gate.forwardedSamples, afterDrive);

      // A sample arriving right after suspend is swallowed.
      gate.feed(AccelerometerSample(
        0,
        0,
        9.81,
        epoch.add(const Duration(minutes: 1)),
      ));
      expect(gate.forwardedSamples, afterDrive);
      await gate.dispose();
    });

    test('a broadcast stream feeds both consumers', () async {
      final ActivityStateManager manager = ActivityStateManager(clock: () => epoch);
      final MotionGate gate =
          MotionGate(manager: manager, hub: _hub());
      final List<AccelerometerSample> first = <AccelerometerSample>[];
      final List<AccelerometerSample> second = <AccelerometerSample>[];
      final subA = gate.gated.listen(first.add);
      final subB = gate.gated.listen(second.add);

      await gate.start();
      _feedDrive(gate, manager, epoch);
      await Future<void>.delayed(Duration.zero);

      // Both the analyzer and the classifier subscribe to the same gated feed.
      expect(first, isNotEmpty);
      expect(first.length, second.length);
      await subA.cancel();
      await subB.cancel();
      await gate.dispose();
    });
  });

  group('reset and lifecycle', () {
    test('reset clears the evidence and counters', () async {
      final ActivityStateManager manager = ActivityStateManager(clock: () => epoch);
      final MotionGate gate =
          MotionGate(manager: manager, hub: _hub());

      await gate.start();
      gate.feed(AccelerometerSample(0, 0, 9.81, epoch));
      gate.reset();

      expect(gate.forwardedSamples, 0);
      expect(gate.suppressedSamples, 0);
      expect(gate.allowsAnalysis, isFalse);
      await gate.dispose();
    });

    test('start is idempotent', () async {
      final StreamController<AccelerometerSample> raw =
          StreamController<AccelerometerSample>.broadcast();
      final ActivityStateManager manager = ActivityStateManager(clock: () => epoch);
      final MotionGate gate = MotionGate(
        manager: manager,
        hub: _hub(),
        accelerationStream: raw.stream,
      );

      await gate.start();
      await gate.start();

      expect(gate.isRunning, isTrue);
      await gate.dispose();
      await raw.close();
    });

    test('a real raw stream is consumed through the gate', () async {
      final StreamController<AccelerometerSample> raw =
          StreamController<AccelerometerSample>.broadcast();
      final ActivityStateManager manager = ActivityStateManager(clock: () => epoch);
      final MotionGate gate = MotionGate(
        manager: manager,
        hub: _hub(),
        accelerationStream: raw.stream,
      );
      final List<AccelerometerSample> received = <AccelerometerSample>[];
      final subscription = gate.gated.listen(received.add);

      await gate.start();
      // A walking stream: the gate must swallow every sample.
      for (int index = 0; index < 50 * 10; index++) {
        raw.add(_walkSample(index, epoch));
      }
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      expect(gate.suppressedSamples, greaterThan(0));
      await subscription.cancel();
      await gate.dispose();
      await raw.close();
    });

    test('stop releases the raw subscription', () async {
      final StreamController<AccelerometerSample> raw =
          StreamController<AccelerometerSample>.broadcast();
      final ActivityStateManager manager = ActivityStateManager(clock: () => epoch);
      final MotionGate gate = MotionGate(
        manager: manager,
        hub: _hub(),
        accelerationStream: raw.stream,
      );

      await gate.start();
      expect(gate.isRunning, isTrue);
      await gate.stop();
      expect(gate.isRunning, isFalse);

      raw.add(AccelerometerSample(0, 0, 9.81, epoch));
      await Future<void>.delayed(Duration.zero);
      expect(gate.forwardedSamples, 0);
      await gate.dispose();
      await raw.close();
    });

    test('dispose closes the gated stream', () async {
      final ActivityStateManager manager = ActivityStateManager(clock: () => epoch);
      final MotionGate gate =
          MotionGate(manager: manager, hub: _hub());

      await gate.dispose();

      // Closed, so a late listen completes rather than throwing.
      await gate.gated.listen((_) {}).asFuture<void>();
    });
  });
}
