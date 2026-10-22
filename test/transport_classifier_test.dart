import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/services/motion_sensor_hub.dart';
import 'package:routenote/src/services/transport_classifier.dart';

/// Sample rate the synthetic waveforms are built for (Android UI rate).
const int _sampleRateHz = 16;

/// Spacing of consecutive 16 Hz stamps: exactly 62.5 ms.
const Duration _step = Duration(microseconds: 62500);

/// A synthetic 16 Hz timestamp base for a window of [count] samples.
List<DateTime> _stamps(int count, {DateTime? start}) {
  final DateTime base = start ?? DateTime(2026, 10, 18, 9);
  return List<DateTime>.generate(count, (int i) => base.add(_step * i));
}

/// A sine of [hz] and [amplitude] sampled at 16 Hz — the gravity-removed
/// residual a rhythmic motion would leave.
List<double> _sine(int count, double hz, double amplitude) {
  return List<double>.generate(
    count,
    (int i) =>
        amplitude * math.sin(2 * math.pi * hz * i / _sampleRateHz),
  );
}

/// Fixed-seed LCG broadband noise, rescaled to exactly [amplitude] RMS so it
/// can be compared fairly against a sine of the same energy.
List<double> _noise(int count, double amplitude, {int seed = 0xC0FFEE}) {
  int state = seed;
  final List<double> raw = List<double>.generate(count, (int _) {
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF;
    return state / 0x100000000 * 2 - 1;
  });
  final double mean =
      raw.reduce((double a, double b) => a + b) / raw.length;
  final List<double> centred =
      raw.map((double value) => value - mean).toList();
  final double rms = TransportClassifier.rmsOf(centred);
  return centred.map((double value) => value * amplitude / rms).toList();
}

/// Lets queued stream events (broadcast controllers deliver asynchronously)
/// settle before assertions.
Future<void> _flush() => Future<void>.delayed(Duration.zero);

/// Feeds one full 64-sample window of a 2 Hz step cadence directly through
/// [classifier.feed]: the raw magnitude oscillates around gravity exactly the
/// way a swinging phone would read it.
void _feedWalkingWindow(
  TransportClassifier classifier, {
  required DateTime base,
  int startSample = 0,
}) {
  for (int i = startSample; i < startSample + 64; i++) {
    final double swing = math.sin(2 * math.pi * 2.0 * i / _sampleRateHz);
    classifier.feed(0, 0, 9.81 + swing, at: base.add(_step * i));
  }
}

/// Feeds one full 64-sample window of a phone at rest (gravity only).
void _feedStationaryWindow(
  TransportClassifier classifier, {
  required DateTime base,
  int startSample = 0,
}) {
  for (int i = startSample; i < startSample + 64; i++) {
    classifier.feed(0, 0, 9.81, at: base.add(_step * i));
  }
}

/// A classifier whose sensor feed is silent: these tests drive [feed],
/// [analyse] and the statics directly, so no subscription is ever opened.
TransportClassifier _silentClassifier() =>
    TransportClassifier(accelerometer: Stream<AccelerometerSample>.empty());

void main() {
  group('TransportClassifier.rmsOf', () {
    test('measures the root mean square of a known window', () {
      expect(
        TransportClassifier.rmsOf(<double>[3, -4]),
        closeTo(math.sqrt(12.5), 1e-9),
      );
      expect(TransportClassifier.rmsOf(<double>[0, 0, 0]), 0);
      expect(
        TransportClassifier.rmsOf(<double>[2, 2, 2, 2]),
        closeTo(2, 1e-12),
      );
    });
  });

  group('TransportClassifier.dominantFrequencyHzOf', () {
    test('finds a 2 Hz cadence inside a 64-sample 16 Hz window', () {
      final double? hz = TransportClassifier.dominantFrequencyHzOf(
        residuals: _sine(64, 2.0, 1.0),
        stamps: _stamps(64),
      );
      expect(hz, isNotNull);
      // Bin width is ~0.25 Hz; the true tone must land within one bin.
      expect(hz, closeTo(2.0, 0.35));
    });

    test('is null when every stamp is identical (no usable sample rate)', () {
      final DateTime frozen = DateTime(2026, 10, 18, 9);
      final List<DateTime> degenerate = List<DateTime>.filled(64, frozen);
      expect(
        TransportClassifier.dominantFrequencyHzOf(
          residuals: _sine(64, 2.0, 1.0),
          stamps: degenerate,
        ),
        isNull,
      );
      expect(
        TransportClassifier.peakRatioOf(
          residuals: _sine(64, 2.0, 1.0),
          stamps: degenerate,
        ),
        0,
      );
    });
  });

  group('TransportClassifier.peakRatioOf', () {
    test('a pure sine concentrates far more power than broadband rumble', () {
      final List<double> sine = _sine(64, 2.0, 1.0);
      final List<double> rumble =
          _noise(64, TransportClassifier.rmsOf(sine));
      final double sineRatio = TransportClassifier.peakRatioOf(
        residuals: sine,
        stamps: _stamps(64),
      );
      final double rumbleRatio = TransportClassifier.peakRatioOf(
        residuals: rumble,
        stamps: _stamps(64),
      );
      expect(sineRatio, greaterThan(0.7));
      expect(rumbleRatio, lessThan(0.5));
      expect(sineRatio, greaterThan(rumbleRatio * 2));
    });
  });

  group('TransportClassifier.analyse', () {
    final TransportClassifier classifier = _silentClassifier();

    TransportMode analyse({
      required List<double> residuals,
      double? speedMps,
    }) {
      return classifier.analyse(
        residuals: residuals,
        stamps: _stamps(residuals.length),
        speedMps: speedMps,
      );
    }

    test('near-zero residuals with no speed read as stationary', () {
      final TransportMode mode = analyse(
        residuals: List<double>.filled(64, 0.001),
      );
      expect(mode, TransportMode.stationary);
    });

    test('near-zero residuals with GPS insisting on 72 km/h read as a vehicle',
        () {
      final TransportMode mode = analyse(
        residuals: List<double>.filled(64, 0.001),
        speedMps: 20, // 72 km/h
      );
      expect(mode, TransportMode.vehicle);
    });

    test('a 2 Hz step cadence without a speed hint reads as walking', () {
      final List<double> residuals = _sine(64, 2.0, 1.0); // RMS ≈ 0.71
      expect(TransportClassifier.rmsOf(residuals), greaterThan(0.28));
      final TransportMode mode = analyse(residuals: residuals);
      expect(mode, TransportMode.walking);
    });

    test('a smooth slow sway at highway speed reads as a train', () {
      final List<double> residuals = _sine(64, 0.5, 0.5); // RMS ≈ 0.35
      final double rms = TransportClassifier.rmsOf(residuals);
      expect(rms, greaterThan(0.28));
      expect(rms, lessThan(0.9));
      final TransportMode mode = analyse(residuals: residuals, speedMps: 30);
      expect(mode, TransportMode.train);
    });

    test('broadband rumble at riding speed reads as a vehicle', () {
      final TransportMode mode = analyse(
        residuals: _noise(64, 2.0),
        speedMps: 6, // 21.6 km/h, at or above the riding threshold
      );
      expect(mode, TransportMode.vehicle);
    });

    test('broadband rumble with no speed hint still falls back to a vehicle',
        () {
      final TransportMode mode = analyse(residuals: _noise(64, 1.5));
      expect(mode, TransportMode.vehicle);
    });

    test('gentle walking-band sway drowned in noise is not walking', () {
      final List<double> sway = _sine(64, 2.0, 0.6);
      final List<double> noise = _noise(64, 3.0);
      final List<double> residuals = List<double>.generate(
        64,
        (int i) => sway[i] + noise[i],
      );
      final TransportMode mode = analyse(residuals: residuals);
      expect(mode, isNot(TransportMode.walking));
      expect(mode, TransportMode.vehicle);
    });
  });

  group('TransportClassifier.feed', () {
    test('a full window of 2 Hz cadence flips the verdict to walking', () {
      final TransportClassifier classifier = _silentClassifier();
      final DateTime base = DateTime(2026, 10, 18, 10);
      expect(classifier.mode, TransportMode.stationary);

      _feedWalkingWindow(classifier, base: base);

      expect(classifier.mode, TransportMode.walking);
      expect(classifier.dominantFrequencyHz, closeTo(2.0, 0.35));
      expect(classifier.residualRms, isNotNull);
      expect(classifier.residualRms!, greaterThan(0.28));
    });

    test('the modes stream announces the change exactly once, no duplicates',
        () async {
      final TransportClassifier classifier = _silentClassifier();
      final List<TransportMode> announcements = <TransportMode>[];
      final StreamSubscription<TransportMode> subscription =
          classifier.modes.listen(announcements.add);
      final DateTime base = DateTime(2026, 10, 18, 10);

      // The first full window changes stationary → walking: one announcement.
      _feedWalkingWindow(classifier, base: base);
      await _flush();
      expect(classifier.mode, TransportMode.walking);
      expect(announcements, <TransportMode>[TransportMode.walking]);

      // A second identical window keeps the same verdict: silence, since the
      // stream only emits on change.
      _feedWalkingWindow(classifier, base: base, startSample: 64);
      await _flush();
      expect(classifier.mode, TransportMode.walking);
      expect(announcements, <TransportMode>[TransportMode.walking]);

      await subscription.cancel();
    });

    test('modes announces through expectLater when the verdict flips',
        () async {
      final TransportClassifier classifier = _silentClassifier();
      final Future<TransportMode> announced = classifier.modes.first;
      _feedWalkingWindow(classifier, base: DateTime(2026, 10, 18, 10));
      await expectLater(announced, completion(TransportMode.walking));
    });

    test('the residual stream publishes the RMS of every analysed window',
        () async {
      final TransportClassifier classifier = _silentClassifier();
      final List<double> published = <double>[];
      final StreamSubscription<double> subscription =
          classifier.residualStream.listen(published.add);
      final DateTime base = DateTime(2026, 10, 18, 10);

      // A partial window is no verdict: nothing is published before the
      // window is full.
      classifier.feed(0, 0, 9.81, at: base);
      await _flush();
      expect(published, isEmpty);

      _feedWalkingWindow(classifier, base: base);
      await _flush();
      expect(published, isNotEmpty);
      expect(published.last, closeTo(classifier.residualRms!, 1e-9));
      // The idle detector compares against the very same bar.
      expect(published.last, greaterThan(classifier.stationaryRms));

      // The window slides, so the RMS is republished as it changes: the idle
      // detector needs a steady feed, not just the verdict changes.
      final int afterFirstWindow = published.length;
      _feedWalkingWindow(classifier, base: base, startSample: 64);
      await _flush();
      expect(published.length, greaterThan(afterFirstWindow));

      await subscription.cancel();
    });

    test('the residual stream is closed by dispose', () async {
      final TransportClassifier classifier = _silentClassifier();
      await classifier.dispose();
      // A closed broadcast controller: listening again is legal but yields
      // nothing, and feeding more samples must not throw.
      final List<double> published = <double>[];
      classifier.residualStream.listen(published.add);
      _feedWalkingWindow(classifier, base: DateTime(2026, 10, 18, 10));
      await _flush();
      expect(published, isEmpty);
    });
  });

  group('TransportClassifier speed hint', () {
    test('a fresh hint steers the very next verdict', () {
      final TransportClassifier classifier = _silentClassifier();
      final DateTime base = DateTime(2026, 10, 18, 11);
      classifier.observeSpeed(20, at: base); // 72 km/h

      // Gravity-only window: quiet, but GPS insists the device is moving.
      _feedStationaryWindow(classifier, base: base);

      expect(classifier.mode, TransportMode.vehicle);
    });

    test('a hint older than the TTL is ignored entirely', () {
      final TransportClassifier classifier = _silentClassifier();
      final DateTime base = DateTime(2026, 10, 18, 11);
      classifier.observeSpeed(20, at: base); // 72 km/h...

      // ...but the window arrives 2 minutes later, well past the 30 s TTL.
      _feedStationaryWindow(
        classifier,
        base: base.add(const Duration(minutes: 2)),
      );

      expect(classifier.mode, TransportMode.stationary);
    });
  });

  group('TransportClassifier lifecycle', () {
    test('start is idempotent and stop releases the subscription', () async {
      int subscriptions = 0;
      final StreamController<AccelerometerSample> controller =
          StreamController<AccelerometerSample>.broadcast(
        onListen: () => subscriptions++,
      );
      addTearDown(controller.close);
      final TransportClassifier classifier =
          TransportClassifier(accelerometer: controller.stream);
      final DateTime base = DateTime(2026, 10, 18, 12);

      expect(classifier.isRunning, isFalse);
      await classifier.start();
      await classifier.start();
      expect(classifier.isRunning, isTrue);
      expect(subscriptions, 1);

      // The one subscription carries samples into feed().
      for (int i = 0; i < 64; i++) {
        final double swing = math.sin(2 * math.pi * 2.0 * i / 16);
        controller.add(
          AccelerometerSample(0, 0, 9.81 + swing, base.add(_step * i)),
        );
      }
      await _flush();
      expect(classifier.mode, TransportMode.walking);

      // Stop closes the window and the subscription.
      await classifier.stop();
      expect(classifier.isRunning, isFalse);
      final double? rmsAtStop = classifier.residualRms;

      // Samples added afterwards never reach the window or the verdict.
      for (int i = 64; i < 128; i++) {
        controller.add(
          AccelerometerSample(0, 0, 9.81, base.add(_step * i)),
        );
      }
      await _flush();
      expect(classifier.mode, TransportMode.walking);
      expect(classifier.residualRms, rmsAtStop);
    });

    test('stop clears the window, so another full window is needed', () async {
      final TransportClassifier classifier = _silentClassifier();
      final List<TransportMode> announcements = <TransportMode>[];
      classifier.modes.listen(announcements.add);
      final DateTime base = DateTime(2026, 10, 18, 12);

      _feedWalkingWindow(classifier, base: base);
      expect(classifier.mode, TransportMode.walking);

      await classifier.stop();
      expect(classifier.isRunning, isFalse);

      // One sample after stop() cannot complete a window: if the old window
      // had survived, this single sample would already trigger a verdict.
      classifier.feed(0, 0, 9.81, at: base.add(_step * 64));
      expect(classifier.mode, TransportMode.walking);
      expect(announcements, <TransportMode>[TransportMode.walking]);

      // Only a brand-full window of rest reads as stationary again.
      _feedStationaryWindow(
        classifier,
        base: base,
        startSample: 65,
      );
      expect(classifier.mode, TransportMode.stationary);
      await _flush(); // the modes stream announces asynchronously
      expect(
        announcements,
        <TransportMode>[TransportMode.walking, TransportMode.stationary],
      );
    });
  });
}
