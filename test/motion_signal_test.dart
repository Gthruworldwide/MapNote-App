import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/services/motion_sensor_hub.dart';
import 'package:routenote/src/services/motion_signal.dart';

void main() {
  // The channel-backed signal touches ServicesBinding when it subscribes.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MotionClassifier', () {
    test('a phone lying still produces no motion evidence', () {
      final MotionClassifier classifier =
          MotionClassifier(windowSamples: 4);

      // Gravity only: nothing but a constant reading on one axis.
      for (int i = 0; i < 12; i++) {
        expect(classifier.feedAcceleration(0, 0, 9.81), isFalse);
      }
      expect(classifier.lastMotionAt, isNull);
      expect(classifier.inTransit, isFalse);
    });

    test('engine/road vibration registers as motion after one window', () {
      DateTime now = DateTime(2026, 10, 14, 12);
      final MotionClassifier classifier = MotionClassifier(
        clock: () => now,
        windowSamples: 4,
      );

      // A shaky ride: the residual after gravity removal is ~0.5 m/s².
      bool evidence = false;
      for (int i = 0; i < 8 && !evidence; i++) {
        final double jitter = i.isEven ? 0.6 : -0.6;
        evidence = classifier.feedAcceleration(0, 0, 9.81 + jitter);
      }

      expect(evidence, isTrue);
      expect(classifier.lastMotionAt, now);
      expect(classifier.inTransit, isTrue);
    });

    test('inTransit decays after the evidence TTL', () {
      DateTime now = DateTime(2026, 10, 14, 12);
      final MotionClassifier classifier = MotionClassifier(
        clock: () => now,
        windowSamples: 2,
        evidenceTtl: const Duration(seconds: 30),
      );

      classifier.feedAcceleration(0, 0, 9.81 + 1.0);
      classifier.feedAcceleration(0, 0, 9.81 - 1.0);
      expect(classifier.inTransit, isTrue);

      // The device stops: the last evidence time is frozen, so the verdict
      // expires on its own instead of sticking forever.
      now = now.add(const Duration(seconds: 31));
      expect(classifier.inTransit, isFalse);
      expect(classifier.lastMotionAt, DateTime(2026, 10, 14, 12));
    });

    test('a Doppler speed alone is enough evidence (GPS fusion)', () {
      DateTime now = DateTime(2026, 10, 14, 12);
      final MotionClassifier classifier = MotionClassifier(clock: () => now);

      expect(classifier.observeSpeed(0.4), isFalse); // ~1.4 km/h: crawling.
      expect(classifier.lastMotionAt, isNull);

      expect(classifier.observeSpeed(2.5), isTrue); // ~9 km/h: moving.
      expect(classifier.lastMotionAt, now);
      expect(classifier.inTransit, isTrue);
    });

    test('ignores non-finite speed readings', () {
      final MotionClassifier classifier = MotionClassifier();
      expect(classifier.observeSpeed(double.nan), isFalse);
      expect(classifier.observeSpeed(double.infinity), isFalse);
      expect(classifier.lastMotionAt, isNull);
    });
  });

  group('NoMotionSignal', () {
    test('never reports motion and its lifecycle is a no-op', () async {
      const NoMotionSignal signal = NoMotionSignal();
      await signal.start();
      signal.observeSpeed(30);
      expect(signal.lastMotionAt, isNull);
      expect(signal.inTransit, isFalse);
      await signal.stop();
    });
  });

  group('SensorMotionSignal', () {
    test('is inert outside Android and refcounts its subscriptions', () async {
      final SensorMotionSignal signal = SensorMotionSignal(
        channel: const EventChannel('mapnote/test_motion'),
      );

      // Two trackers join, one leaves: nothing to unsubscribe yet.
      await signal.start();
      await signal.start();
      await signal.stop();
      await signal.stop();

      // The bridge is Android-only, so on the test host there is no evidence
      // and (importantly) the channel was never touched.
      expect(signal.lastMotionAt, isNull);
      expect(signal.inTransit, isFalse);

      // Extra stops must not throw.
      await signal.stop();
      expect(signal.lastMotionAt, isNull);
    });

    test('forwards Doppler speed into its classifier', () async {
      final SensorMotionSignal signal = SensorMotionSignal(
        channel: const EventChannel('mapnote/test_motion'),
      );

      signal.observeSpeed(12);
      expect(signal.lastMotionAt, isNotNull);
      expect(signal.inTransit, isTrue);
    });
  });

  group('SensorMotionSignal via the shared MotionSensorHub', () {
    const MethodChannel motionMethodChannel = MethodChannel(
      MotionSensorHub.channelName,
    );

    /// Arms one hub-backed test: the subscription path only runs on Android,
    /// and the EventChannel's underlying `listen`/`cancel` method calls need
    /// a mock handler or they report MissingPluginException through
    /// FlutterError (which the test binding treats as a failure). Both are
    /// undone by addTearDown after the test.
    void armHubTest() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        motionMethodChannel,
        (MethodCall call) async => null,
      );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(motionMethodChannel, null),
      );
    }

    test('classifies hub-fed samples and releases the hub on stop', () async {
      armHubTest();
      final MotionSensorHub hub = MotionSensorHub(
        channel: const EventChannel(MotionSensorHub.channelName),
      );
      final SensorMotionSignal signal = SensorMotionSignal(hub: hub);

      expect(hub.userCount, 0);
      await signal.start();
      expect(signal.inTransit, isFalse);
      expect(hub.userCount, 1, reason: 'the signal holds the hub open');
      expect(hub.isListening, isTrue, reason: 'native channel subscribed once');

      // Legacy bare [x, y, z] payload, gravity only: the phone is lying
      // still, so no window ever clears the vibration threshold.
      for (int i = 0; i < 30; i++) {
        hub.handlePlatformEvent(<num>[0, 0, 9.81]);
      }
      await Future<void>.delayed(Duration.zero);
      expect(signal.inTransit, isFalse);
      expect(signal.lastMotionAt, isNull);

      // [x, y, z, tag] payload with the accelerometer tag: engine/road
      // vibration above the threshold registers as motion evidence.
      for (int i = 0; i < 40; i++) {
        hub.handlePlatformEvent(<num>[
          0,
          0,
          i.isEven ? 10.41 : 9.21,
          MotionSensorHub.accelerometerTag,
        ]);
      }
      await Future<void>.delayed(Duration.zero);
      expect(signal.inTransit, isTrue);
      expect(signal.lastMotionAt, isNotNull);

      await signal.stop();
      expect(hub.userCount, 0, reason: 'the last release frees the hub');
      expect(hub.isListening, isFalse, reason: 'native subscription released');
    });

    test('gyroscope-tagged events never reach the accelerometer classifier',
        () async {
      armHubTest();
      final MotionSensorHub hub = MotionSensorHub(
        channel: const EventChannel(MotionSensorHub.channelName),
      );
      final SensorMotionSignal signal = SensorMotionSignal(hub: hub);
      final List<GyroscopeSample> yawRates = <GyroscopeSample>[];
      final StreamSubscription<GyroscopeSample> gyroFeed =
          hub.gyroscope.listen(yawRates.add);

      await signal.start();

      // Vibration-shaped values, but tagged as the gyroscope: routed to the
      // yaw-rate feed only — fed to the movement classifier they would be
      // motion evidence, so this pins that they are not.
      for (int i = 0; i < 40; i++) {
        hub.handlePlatformEvent(<num>[
          0,
          0,
          i.isEven ? 10.41 : 9.21,
          MotionSensorHub.gyroscopeTag,
        ]);
      }
      await Future<void>.delayed(Duration.zero);
      expect(yawRates, hasLength(40));
      expect(signal.inTransit, isFalse);
      expect(signal.lastMotionAt, isNull);

      // The identical values with the accelerometer tag do register — the
      // tag, not the payload shape, decides which classifier sees a sample.
      for (int i = 0; i < 40; i++) {
        hub.handlePlatformEvent(<num>[
          0,
          0,
          i.isEven ? 10.41 : 9.21,
          MotionSensorHub.accelerometerTag,
        ]);
      }
      await Future<void>.delayed(Duration.zero);
      expect(signal.inTransit, isTrue);

      await gyroFeed.cancel();
      await signal.stop();
      expect(hub.userCount, 0);
      expect(hub.isListening, isFalse);
    });
  });
}
