import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/services/step_meter.dart';

/// `StepMeter` is the adapter between the pedometer's absolute step counter and
/// the per-fix increments the tracker stamps onto its track points, so the
/// contract worth pinning is exactly the arithmetic: baseline on the first
/// sample, deltas afterwards, a `null` "no pedometer" answer before it, a `0`
/// "measured, but no step" answer after it, and no negative increment when the
/// counter reboots.
///
/// The hardware feed is injected as a factory (production supplies
/// `hardwareStepCount` from the `pedometer` plugin — see
/// `pedometer_steps_test.dart` for that end), so every case here runs without a
/// platform channel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// One stand-in for the OS step counter: absolute counts, broadcast (the
  /// plugin's event channel is broadcast too), and only delivering while a
  /// consumer is actually listening.
  late StreamController<int> feed;
  late int opens;
  late int listens;
  late int cancels;

  setUp(() {
    opens = 0;
    listens = 0;
    cancels = 0;
    feed = StreamController<int>.broadcast(
      onListen: () => listens += 1,
      onCancel: () => cancels += 1,
    );
  });

  tearDown(() async {
    await feed.close();
  });

  /// The production-shaped factory: every call opens a new stream.
  Stream<int> openFeed() {
    opens += 1;
    return feed.stream;
  }

  /// Pushes one absolute reading down the feed and lets the meter observe it,
  /// exactly as the hardware sensor does on a device.
  Future<void> sample(int steps) async {
    feed.add(steps);
    await pumpEventQueue();
  }

  group('StepMeter — readings to increments', () {
    test('answers null before any sample, so the classifier can fall back', () {
      final StepMeter meter = StepMeter(stepCounts: openFeed);

      expect(meter.hasSensor, isFalse);
      expect(meter.drain(), isNull);
      expect(meter.totalSteps, 0);
    });

    test('the first sample is a baseline, not a step count', () async {
      // A phone that booted days ago reports tens of thousands of steps; none
      // of them belong to the trip that is starting now.
      final StepMeter meter = StepMeter(stepCounts: openFeed);
      await meter.start();
      await sample(4210);

      expect(meter.hasSensor, isTrue);
      expect(meter.drain(), 0);
      expect(meter.totalSteps, 0);

      await meter.dispose();
    });

    test('reports the increment between consecutive samples', () async {
      final StepMeter meter = StepMeter(stepCounts: openFeed);
      await meter.start();
      await sample(4210);

      await sample(4235);
      expect(meter.drain(), 25);

      await sample(4290);
      expect(meter.drain(), 55);

      await meter.dispose();
    });

    test('an increment is handed out exactly once', () async {
      final StepMeter meter = StepMeter(stepCounts: openFeed);
      await meter.start();
      await sample(100);
      await sample(130);

      expect(meter.drain(), 30);
      // The next fix took no steps of its own: a measured zero, not a repeat.
      expect(meter.drain(), 0);
      expect(meter.hasSensor, isTrue);

      await meter.dispose();
    });

    test('totalSteps includes steps not yet drained', () async {
      final StepMeter meter = StepMeter(stepCounts: openFeed);
      await meter.start();
      await sample(100);
      await sample(140);
      await sample(150);

      expect(meter.totalSteps, 50);
      expect(meter.drain(), 50);
      expect(meter.totalSteps, 50);

      await meter.dispose();
    });

    test('a repeated reading adds nothing', () async {
      final StepMeter meter = StepMeter(stepCounts: openFeed);
      await meter.start();
      await sample(100);
      await sample(100);
      await sample(100);

      expect(meter.drain(), 0);
      expect(meter.totalSteps, 0);

      await meter.dispose();
    });

    test('a counter reset rebases instead of reporting negative steps',
        () async {
      final StepMeter meter = StepMeter(stepCounts: openFeed);
      await meter.start();
      await sample(100);
      await sample(150);
      expect(meter.drain(), 50);

      // The device rebooted mid-session: the counter restarts from near zero.
      await sample(10);
      expect(meter.drain(), 0);
      expect(meter.totalSteps, 50);

      // Counting resumes from the new baseline.
      await sample(40);
      expect(meter.drain(), 30);
      expect(meter.totalSteps, 80);

      await meter.dispose();
    });
  });

  group('StepMeter — lifecycle', () {
    test('opens the hardware feed once and releases it on stop', () async {
      final StepMeter meter = StepMeter(stepCounts: openFeed);

      expect(opens, 0);
      await meter.start();
      expect(meter.isRunning, isTrue);
      expect(opens, 1);
      expect(listens, 1);

      // A tracker restarting its engine must not register a second sensor.
      await meter.start();
      expect(opens, 1);

      await meter.stop();
      await pumpEventQueue();
      expect(meter.isRunning, isFalse);
      expect(cancels, 1);

      // Releasing twice is a no-op, never a second cancel.
      await meter.stop();
      await pumpEventQueue();
      expect(cancels, 1);

      await meter.dispose();
    });

    test('a new session never inherits steps taken while stopped', () async {
      final StepMeter meter = StepMeter(stepCounts: openFeed);

      await meter.start();
      await sample(100);
      await sample(150);
      expect(meter.drain(), 50);

      await meter.stop();
      await pumpEventQueue();
      // Steps taken with nothing recording (walking to the car) are invisible:
      // the feed has no listener at all.
      await sample(400);

      await meter.start();
      // The counter now reads 400: that is the new baseline, not a 250-step
      // burst attributed to the trip that just started.
      await sample(500);
      expect(meter.drain(), 0);
      expect(meter.totalSteps, 0);

      await sample(520);
      expect(meter.drain(), 20);

      await meter.dispose();
    });

    test('refresh re-opens the feed when no sample has arrived yet', () async {
      // The permission path: tracking starts before `ACTIVITY_RECOGNITION` is
      // answered, so the plugin's first listen registers nothing and emits
      // nothing. Re-opening once the OS agrees is what attaches the sensor.
      final StepMeter meter = StepMeter(stepCounts: openFeed);
      await meter.start();
      expect(opens, 1);
      expect(meter.hasSensor, isFalse);

      await meter.refresh();
      await pumpEventQueue();
      expect(opens, 2);
      expect(cancels, 1);

      // The re-opened feed delivers the counter's current value: that is the
      // session baseline, exactly as a first-ever listen would be.
      await sample(900);
      expect(meter.hasSensor, isTrue);
      expect(meter.drain(), 0);

      await sample(930);
      expect(meter.drain(), 30);

      await meter.dispose();
    });

    test('refresh is a no-op once the pedometer is reporting', () async {
      final StepMeter meter = StepMeter(stepCounts: openFeed);
      await meter.start();
      await sample(100);
      expect(meter.hasSensor, isTrue);

      // Called on every tracking sync: a live sensor is never churned.
      await meter.refresh();
      await meter.refresh();
      expect(opens, 1);
      expect(cancels, 0);

      await meter.dispose();
    });

    test('refresh before start never touches the hardware', () async {
      final StepMeter meter = StepMeter(stepCounts: openFeed);

      await meter.refresh();
      expect(opens, 0);
      expect(meter.isRunning, isFalse);
      expect(meter.drain(), isNull);
    });

    test('dispose releases the feed and refuses to restart', () async {
      final StepMeter meter = StepMeter(stepCounts: openFeed);
      await meter.start();
      await sample(100);

      await meter.dispose();
      await pumpEventQueue();
      expect(meter.isRunning, isFalse);
      expect(cancels, 1);

      // Disposing twice is safe, and the dropped meter cannot reopen the
      // hardware by being started again.
      await meter.dispose();
      await meter.start();
      await pumpEventQueue();
      expect(opens, 1);
      expect(meter.isRunning, isFalse);
    });

    test('stopping a meter that never started is safe', () async {
      final StepMeter meter = StepMeter(stepCounts: openFeed);

      await meter.stop();
      expect(meter.isRunning, isFalse);
      expect(meter.drain(), isNull);
      expect(opens, 0);
    });

    test('without a source it degrades to "no pedometer"', () async {
      // The unit-test / unsupported-platform case: no hardware feed at all.
      final StepMeter meter = StepMeter();

      await meter.start();
      expect(meter.isRunning, isTrue);
      expect(meter.hasSensor, isFalse);
      expect(meter.drain(), isNull);

      // Refreshing has nothing to re-open either.
      await meter.refresh();
      expect(meter.hasSensor, isFalse);

      await meter.stop();
      await meter.dispose();
      expect(meter.isRunning, isFalse);
    });

    test('a source that refuses to open degrades instead of throwing',
        () async {
      // A platform without the plugin throws as soon as it is listened to;
      // tracking must keep working on GPS alone.
      final StepMeter meter = StepMeter(
        stepCounts: () => throw StateError('no pedometer plugin'),
      );

      await meter.start();
      expect(meter.isRunning, isTrue);
      expect(meter.hasSensor, isFalse);
      expect(meter.drain(), isNull);

      await meter.dispose();
    });

    test('a feed error leaves the meter on the GPS fallback', () async {
      final StepMeter meter = StepMeter(stepCounts: openFeed);
      await meter.start();

      // The plugin reports "StepCount not available" as a platform error.
      feed.addError(
        PlatformException(code: '1', message: 'StepCount not available'),
      );
      await pumpEventQueue();

      expect(meter.hasSensor, isFalse);
      expect(meter.drain(), isNull);

      // A later reading still counts: the error is not fatal.
      await sample(50);
      await sample(70);
      expect(meter.drain(), 20);

      await meter.dispose();
    });
  });
}
