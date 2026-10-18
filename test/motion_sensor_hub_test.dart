import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/services/motion_sensor_hub.dart';

void main() {
  // The hub subscribes to an EventChannel when it starts.
  TestWidgetsFlutterBinding.ensureInitialized();

  final DateTime stamp = DateTime(2026, 10, 18, 9, 30);

  group('MotionSensorHub parsing', () {
    test('a legacy bare [x, y, z] payload counts as an accelerometer sample',
        () {
      final AccelerometerSample? sample =
          MotionSensorHub.parseAccelerometer(<num>[1, 2, 3], stamp);

      expect(sample, isNotNull);
      expect(sample!.x, 1.0);
      expect(sample.y, 2.0);
      expect(sample.z, 3.0);
      expect(sample.at, stamp);

      // The same bare payload is never gyroscope data.
      expect(MotionSensorHub.parseGyroscope(<num>[1, 2, 3], stamp), isNull);
    });

    test('tagged [x, y, z, tag] payloads parse to the matching sensor', () {
      final AccelerometerSample? accelerometer = MotionSensorHub
          .parseAccelerometer(<num>[1.0, 2.0, 3.0, 0], stamp);
      expect(accelerometer, isNotNull);
      expect(accelerometer!.x, 1.0);
      expect(accelerometer.y, 2.0);
      expect(accelerometer.z, 3.0);
      expect(accelerometer.at, stamp);

      final GyroscopeSample? gyroscope =
          MotionSensorHub.parseGyroscope(<num>[1.0, 2.0, 3.0, 1], stamp);
      expect(gyroscope, isNotNull);
      expect(gyroscope!.x, 1.0);
      expect(gyroscope.y, 2.0);
      expect(gyroscope.z, 3.0);
      expect(gyroscope.at, stamp);

      // Cross-checks: each parser rejects the other sensor's tag.
      expect(
        MotionSensorHub.parseAccelerometer(
          <num>[1, 2, 3, MotionSensorHub.gyroscopeTag],
          stamp,
        ),
        isNull,
      );
      expect(
        MotionSensorHub.parseGyroscope(
          <num>[1, 2, 3, MotionSensorHub.accelerometerTag],
          stamp,
        ),
        isNull,
      );
      // …and the public tag constants mean what they say.
      expect(MotionSensorHub.accelerometerTag, 0);
      expect(MotionSensorHub.gyroscopeTag, 1);
      expect(MotionSensorHub.channelName, 'com.routenote.routenote/motion');
    });

    test('malformed payloads are ignored instead of throwing', () {
      final MotionSensorHub hub = MotionSensorHub(clock: () => stamp);
      final List<Object?> malformed = <Object?>[
        <num>[1, 2], // too short for any sensor
        <Object>['a', 'b', 'c', 0], // non-numeric axes
        42, // not a list at all
        <num>[1, 2, 3, 7], // unknown sensor tag
        <Object>[1, 2, 3, 'x'], // non-numeric tag
        <num>[double.nan, 2, 3, 0], // non-finite axis
      ];

      for (final Object? payload in malformed) {
        expect(
          MotionSensorHub.parseAccelerometer(payload, stamp),
          isNull,
          reason: 'accelerometer must ignore $payload',
        );
        expect(
          MotionSensorHub.parseGyroscope(payload, stamp),
          isNull,
          reason: 'gyroscope must ignore $payload',
        );
        expect(
          () => hub.handlePlatformEvent(payload),
          returnsNormally,
          reason: 'dispatch must not throw on $payload',
        );
      }
    });
  });

  group('MotionSensorHub dispatch', () {
    test('fans events out to the right broadcast stream', () async {
      final MotionSensorHub hub = MotionSensorHub(clock: () => stamp);
      final List<AccelerometerSample> accelerometers =
          <AccelerometerSample>[];
      final List<GyroscopeSample> gyroscopes = <GyroscopeSample>[];
      final StreamSubscription<AccelerometerSample> accelerometerSubscription =
          hub.accelerometer.listen(accelerometers.add);
      final StreamSubscription<GyroscopeSample> gyroscopeSubscription =
          hub.gyroscope.listen(gyroscopes.add);

      hub.handlePlatformEvent(<num>[1, 2, 3, MotionSensorHub.accelerometerTag]);
      hub.handlePlatformEvent(<num>[4, 5, 6]); // legacy payload → accelerometer
      hub.handlePlatformEvent(<num>[7, 8, 9, MotionSensorHub.gyroscopeTag]);
      await pumpEventQueue();

      expect(accelerometers, hasLength(2));
      expect(gyroscopes, hasLength(1));
      expect(accelerometers[0].x, 1.0);
      expect(accelerometers[1].x, 4.0);
      expect(gyroscopes.single.x, 7.0);
      expect(accelerometers.every((AccelerometerSample s) => s.at == stamp),
          isTrue);
      expect(gyroscopes.single.at, stamp);

      await accelerometerSubscription.cancel();
      await gyroscopeSubscription.cancel();
    });

    test('stamps samples with the injected clock', () async {
      final MotionSensorHub hub = MotionSensorHub(clock: () => stamp);
      final List<AccelerometerSample> accelerometers =
          <AccelerometerSample>[];
      final StreamSubscription<AccelerometerSample> subscription =
          hub.accelerometer.listen(accelerometers.add);

      hub.handlePlatformEvent(<num>[0.1, 0.2, 0.3]);
      await pumpEventQueue();

      expect(accelerometers, hasLength(1));
      expect(accelerometers.single.at, stamp);

      await subscription.cancel();
    });

    test('events nobody listens to are dropped without throwing', () {
      final MotionSensorHub hub = MotionSensorHub(clock: () => stamp);

      expect(() {
        hub.handlePlatformEvent(<num>[1, 2, 3, MotionSensorHub.accelerometerTag]);
        hub.handlePlatformEvent(<num>[1, 2, 3, MotionSensorHub.gyroscopeTag]);
        hub.handlePlatformEvent(42);
      }, returnsNormally);
      expect(hub.userCount, 0);
      expect(hub.isListening, isFalse);
    });
  });

  group('MotionSensorHub platform channel', () {
    const EventChannel channel = EventChannel(MotionSensorHub.channelName);

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(channel, null);
    });

    test('ref-counts the native channel across consumers', () async {
      int listens = 0;
      int cancels = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        channel,
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink events) {
            listens += 1;
          },
          onCancel: (Object? arguments) {
            cancels += 1;
          },
        ),
      );
      final MotionSensorHub hub = MotionSensorHub();

      // First consumer opens the hardware exactly once.
      await hub.start();
      await pumpEventQueue();
      expect(listens, 1);
      expect(hub.userCount, 1);
      expect(hub.isListening, isTrue);

      // A second consumer only bumps the reference count.
      await hub.start();
      await pumpEventQueue();
      expect(listens, 1);
      expect(hub.userCount, 2);
      expect(hub.isListening, isTrue);

      // One release left: the feed stays open.
      await hub.stop();
      await pumpEventQueue();
      expect(cancels, 0);
      expect(hub.userCount, 1);
      expect(hub.isListening, isTrue);

      // The last release powers the sensor down.
      await hub.stop();
      await pumpEventQueue();
      expect(cancels, 1);
      expect(hub.userCount, 0);
      expect(hub.isListening, isFalse);

      // Releasing without a matching start is a safe no-op.
      await hub.stop();
      expect(hub.userCount, 0);
      expect(cancels, 1);
    });

    test('delivers platform events end-to-end and swallows channel errors',
        () async {
      MockStreamHandlerEventSink? events;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        channel,
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink sink) {
            events = sink;
          },
          onCancel: (Object? arguments) {},
        ),
      );

      final MotionSensorHub hub = MotionSensorHub(clock: () => stamp);
      final List<AccelerometerSample> accelerometers =
          <AccelerometerSample>[];
      final StreamSubscription<AccelerometerSample> subscription =
          hub.accelerometer.listen(accelerometers.add);

      await hub.start();
      await pumpEventQueue();
      expect(events, isNotNull);

      events!.success(<num>[0.5, 0.6, 0.7, MotionSensorHub.accelerometerTag]);
      // A sensor error from the platform must be swallowed, never thrown at
      // a consumer (start() documents this).
      events!.error(code: 'sensor_unavailable', message: 'no accelerometer');
      await pumpEventQueue();

      expect(accelerometers, hasLength(1));
      expect(accelerometers.single.x, 0.5);
      expect(accelerometers.single.y, 0.6);
      expect(accelerometers.single.z, 0.7);
      expect(accelerometers.single.at, stamp);

      await subscription.cancel();
      await hub.stop();
      await pumpEventQueue();
      expect(hub.isListening, isFalse);
    });
  });
}
