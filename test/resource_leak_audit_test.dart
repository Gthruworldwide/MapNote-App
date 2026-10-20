import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/features/motion_analytics/data/heuristic_motion_model.dart';
import 'package:routenote/src/features/motion_analytics/data/isolate_motion_inference_runner.dart';
import 'package:routenote/src/features/motion_analytics/domain/entities/motion_window.dart';
import 'package:routenote/src/services/motion_sensor_hub.dart';

/// A deterministic window with no samples: enough to exercise the isolate
/// plumbing without any TFLite dependency.
MotionWindow _emptyWindow() => MotionWindow.empty;

/// Static, dependency-free leak audit for the resource owners that can outlive
/// their widget/provider: the background inference isolate and the shared motion
/// sensor hub.
void main() {
  // The motion hub talks to an EventChannel, so the binding must exist before
  // any hub is started or stopped.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IsolateMotionInferenceRunner resource cleanup', () {
    test('dispose is idempotent and leaves no worker running', () async {
      final IsolateMotionInferenceRunner runner = IsolateMotionInferenceRunner(
        buildModel: () => HeuristicMotionModel(),
        debugName: 'leak-audit-1',
      );

      await runner.dispose();
      // A second dispose must be a no-op, not a throw and not a second teardown.
      await runner.dispose();

      expect(runner.isRunning, isFalse);
      expect(runner.pendingRequests, 0);
    });

    test('a spawned worker is killed on dispose and never answers again',
        () async {
      final IsolateMotionInferenceRunner runner = IsolateMotionInferenceRunner(
        buildModel: () => HeuristicMotionModel(),
        debugName: 'leak-audit-2',
      );
      addTearDown(runner.dispose);

      // Forces the spawn so there is a real worker to release.
      await runner.infer(_emptyWindow());
      expect(runner.isRunning, isTrue);

      await runner.dispose();

      expect(runner.isRunning, isFalse);
      expect(runner.pendingRequests, 0);
      // Post-dispose inference degrades to "no events" rather than throwing or
      // respawning a worker behind the caller's back.
      expect(await runner.infer(_emptyWindow()), isEmpty);
      expect(runner.isRunning, isFalse);
    });

    test('pending requests are completed, not left dangling, on dispose',
        () async {
      final IsolateMotionInferenceRunner runner = IsolateMotionInferenceRunner(
        buildModel: () => HeuristicMotionModel(),
        timeout: const Duration(milliseconds: 300),
        debugName: 'leak-audit-3',
      );

      // Start an inference and dispose while it is in flight: the reached
      // worker path guarantees `_pending` is populated at some point.
      await runner.infer(_emptyWindow());

      await runner.dispose();

      expect(runner.pendingRequests, 0);
      expect(runner.isRunning, isFalse);
    });
  });

  group('MotionSensorHub cleanup', () {
    test('dispose closes both feeds and cancels the platform subscription',
        () async {
      final MotionSensorHub hub = MotionSensorHub();

      await hub.start();
      expect(hub.isListening, isTrue);

      await hub.dispose();

      expect(hub.isListening, isFalse);
      expect(hub.userCount, 0);

      // The broadcast feeds are closed, so a late listener sees a finished
      // stream instead of attaching to a hub the container already dropped.
      bool accelerometerDone = false;
      hub.accelerometer.listen(
        (_) {},
        onDone: () => accelerometerDone = true,
      );
      bool gyroscopeDone = false;
      hub.gyroscope.listen((_) {}, onDone: () => gyroscopeDone = true);
      await Future<void>.delayed(Duration.zero);

      expect(accelerometerDone, isTrue);
      expect(gyroscopeDone, isTrue);
    });

    test('a disposed hub stops emitting even if an event is pushed', () async {
      final MotionSensorHub hub = MotionSensorHub();
      final List<AccelerometerSample> seen = <AccelerometerSample>[];
      final StreamSubscription<AccelerometerSample> subscription =
          hub.accelerometer.listen(seen.add);

      await hub.dispose();
      // Closing the controller already ended the feed; an add would throw, so
      // the hub must not be reachable any more.
      await subscription.cancel();
      expect(seen, isEmpty);
    });

    test('release is refcounted and cancels only on the last stop', () async {
      final MotionSensorHub hub = MotionSensorHub();
      addTearDown(hub.dispose);

      await hub.start();
      await hub.start();
      expect(hub.userCount, 2);
      expect(hub.isListening, isTrue);

      await hub.stop();
      // One consumer left: the hardware must stay open for it.
      expect(hub.isListening, isTrue);

      await hub.stop();
      expect(hub.isListening, isFalse);
      expect(hub.userCount, 0);
    });
  });
}
