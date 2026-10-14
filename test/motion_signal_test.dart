import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
