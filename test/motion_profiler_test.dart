import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:routenote/src/services/motion_profiler.dart';
import 'package:routenote/src/services/transport_classifier.dart';

final DateTime _t0 = DateTime.utc(2026, 1, 1);

/// Feeds [seconds] seconds of 1 Hz speed readings into [analyzer], starting
/// at [start]; [speedsMps] is indexed by second.
void _feedSpeeds(
  MotionBehaviorAnalyzer analyzer,
  List<double> speedsMps, {
  DateTime? start,
}) {
  final DateTime from = start ?? _t0;
  for (int i = 0; i < speedsMps.length; i++) {
    analyzer.observeSpeed(
      speedsMps[i],
      at: from.add(Duration(seconds: i)),
    );
  }
}

/// Feeds a rhythmic vibration waveform (2 Hz at 16 Hz sampling, ±0.5 m/s² on
/// top of gravity) so the residual RMS sits above the moving floor — the
/// accelerometer "confirming dynamics" evidence every event requires.
void _feedVibration(
  MotionBehaviorAnalyzer analyzer, {
  DateTime? start,
  int samples = 64,
}) {
  final DateTime from = start ?? _t0;
  for (int i = 0; i < samples; i++) {
    final double seconds = i / 16;
    analyzer.feed(
      0,
      0,
      9.81 + 0.5 * math.sin(2 * math.pi * 2 * seconds),
      at: from.add(Duration(microseconds: (seconds * 1e6).round())),
    );
  }
}

void main() {
  group('MotionBehaviorAnalyzer variance window', () {
    test('starts empty and measures the residual RMS of what it is fed', () {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      expect(analyzer.lastVarianceRms, isNull);

      analyzer.feed(0, 0, 9.81, at: _t0); // perfectly still
      expect(analyzer.lastVarianceRms, closeTo(0, 1e-9));

      _feedVibration(analyzer);
      final double rms = analyzer.lastVarianceRms!;
      expect(rms, greaterThanOrEqualTo(0.28), reason: 'moving floor');
      expect(rms, lessThan(0.5), reason: 'a 0.5 amplitude sine is ~0.35 rms');
    });
  });

  group('MotionBehaviorAnalyzer event detection', () {
    test('a harsh launch is reported once, with its peak and span', () {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      analyzer.observeTransport(TransportMode.vehicle);
      _feedVibration(analyzer);
      // 0 → 15 m/s in 3 s (5 m/s² raw), then a cruise step that ends the
      // maneuver. The first delta seeds the EMA at 5 m/s² (armed from t+1 s);
      // the cruise step halves it below the threshold at t+4 s.
      _feedSpeeds(analyzer, const <double>[0, 5, 10, 15, 15]);

      expect(analyzer.events, hasLength(1));
      final DrivingEvent event = analyzer.events.single;
      expect(event.type, DrivingEventType.harshAcceleration);
      expect(event.peakMps2, closeTo(5.0, 0.001));
      expect(event.startedAt, _t0.add(const Duration(seconds: 1)));
      expect(event.duration, const Duration(seconds: 3));
    });

    test('a hard brake is reported with its peak and span', () {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      analyzer.observeTransport(TransportMode.vehicle);
      _feedVibration(analyzer);
      // 15 → 0 m/s in 3 s; the first delta seeds the EMA at -5 m/s², past
      // the braking threshold from t+1 s until the cruise step halves it.
      _feedSpeeds(analyzer, const <double>[15, 10, 5, 0, 0]);

      expect(analyzer.events, hasLength(1));
      final DrivingEvent event = analyzer.events.single;
      expect(event.type, DrivingEventType.harshBraking);
      expect(event.peakMps2, closeTo(-5.0, 0.001));
      expect(event.startedAt, _t0.add(const Duration(seconds: 1)));
      expect(event.duration, const Duration(seconds: 3));
    });

    test('steady cruising and gentle ramps report nothing', () {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      analyzer.observeTransport(TransportMode.vehicle);
      _feedVibration(analyzer);
      _feedSpeeds(analyzer, <double>[for (int i = 0; i < 10; i++) 20]);
      _feedSpeeds(
        analyzer,
        <double>[for (int i = 0; i < 10; i++) 20.0 + i], // 1 m/s²
        start: _t0.add(const Duration(seconds: 10)),
      );
      expect(analyzer.events, isEmpty);
    });

    test('a speed drop with a quiet accelerometer is not a maneuver', () {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      analyzer.observeTransport(TransportMode.vehicle);
      const List<double> brakeScript = <double>[15, 10, 5, 0, 0];

      // No accelerometer evidence at all.
      _feedSpeeds(analyzer, brakeScript);
      expect(analyzer.events, isEmpty);

      // Still-phone evidence: residual RMS far below the moving floor.
      analyzer.reset();
      analyzer.observeTransport(TransportMode.vehicle);
      analyzer.feed(0, 0, 9.81, at: _t0);
      _feedSpeeds(analyzer, brakeScript);
      expect(analyzer.events, isEmpty);

      // Positive control: the same script with real vibration reports.
      analyzer.reset();
      analyzer.observeTransport(TransportMode.vehicle);
      _feedVibration(analyzer);
      _feedSpeeds(analyzer, brakeScript);
      expect(analyzer.events, hasLength(1));
    });
  });

  group('MotionBehaviorAnalyzer context gating', () {
    test('events require a vehicle verdict by default', () {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      _feedVibration(analyzer);
      _feedSpeeds(analyzer, const <double>[15, 10, 5, 0, 0]);
      expect(analyzer.events, isEmpty, reason: 'no transport verdict yet');

      analyzer.reset();
      analyzer.observeTransport(TransportMode.walking);
      _feedVibration(analyzer);
      _feedSpeeds(analyzer, const <double>[15, 10, 5, 0, 0]);
      expect(analyzer.events, isEmpty, reason: 'walking is not driving');

      analyzer.reset();
      analyzer.observeTransport(TransportMode.vehicle);
      _feedVibration(analyzer);
      _feedSpeeds(analyzer, const <double>[15, 10, 5, 0, 0]);
      expect(analyzer.events, hasLength(1));
    });

    test('gateOnVehicle: false reports in any context', () {
      final MotionBehaviorAnalyzer analyzer =
          MotionBehaviorAnalyzer(gateOnVehicle: false);
      _feedVibration(analyzer);
      _feedSpeeds(analyzer, const <double>[15, 10, 5, 0, 0]);
      expect(analyzer.events, hasLength(1));
    });
  });

  group('MotionBehaviorAnalyzer event hygiene', () {
    test('a maneuver shorter than minEventDuration is discarded', () {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer(
        minEventDuration: const Duration(seconds: 4),
      );
      analyzer.observeTransport(TransportMode.vehicle);
      _feedVibration(analyzer);
      _feedSpeeds(analyzer, const <double>[15, 10, 5, 0, 0]); // 3 s armed
      expect(analyzer.events, isEmpty);
    });

    test('back-to-back maneuvers merge through the cooldown', () {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer(
        eventCooldown: const Duration(seconds: 30),
      );
      analyzer.observeTransport(TransportMode.vehicle);
      _feedVibration(analyzer);

      // Burst 1: armed from t+1 s, settles at t+4 s → reported.
      _feedSpeeds(analyzer, const <double>[15, 10, 5, 0, 0]);
      // Idle, then a gentle ramp (below threshold — the 0→15 step arms a
      // brief launch the cooldown swallows along with burst 2).
      _feedSpeeds(
        analyzer,
        <double>[
          for (int i = 0; i < 5; i++) 0.0,
          3, 6, 9, 12, 15,
        ],
        start: _t0.add(const Duration(seconds: 5)),
      );
      // Burst 2: settles 14 s after burst 1 → inside the 30 s cooldown.
      _feedSpeeds(
        analyzer,
        const <double>[10, 5, 0, 0, 0],
        start: _t0.add(const Duration(seconds: 15)),
      );
      // A fresh cruise and burst 3, whose emission lands 36 s after burst 1
      // — past the cooldown, so it reports.
      _feedVibration(analyzer, start: _t0.add(const Duration(seconds: 37)));
      _feedSpeeds(
        analyzer,
        <double>[
          for (int i = 0; i < 17; i++) 15.0,
          10, 5, 0, 0,
        ],
        start: _t0.add(const Duration(seconds: 20)),
      );

      expect(analyzer.events, hasLength(2));
      expect(analyzer.events.first.startedAt,
          _t0.add(const Duration(seconds: 1)));
      expect(
        analyzer.events.last.startedAt,
        _t0.add(const Duration(seconds: 39)),
      );
    });

    test('a timing hole re-seeds the timeline instead of differentiating', () {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      analyzer.observeTransport(TransportMode.vehicle);
      _feedVibration(analyzer);
      analyzer.observeSpeed(20, at: _t0);
      analyzer.observeSpeed(0, at: _t0.add(const Duration(seconds: 15)));

      expect(analyzer.instantAccelerationMps2, isNull,
          reason: 'the 15 s hole must not become an acceleration');
      expect(analyzer.events, isEmpty);

      // The timeline works again from the next usable pair.
      analyzer.observeSpeed(0, at: _t0.add(const Duration(seconds: 17)));
      expect(analyzer.instantAccelerationMps2, 0);
    });

    test('speed readings closer than minSpeedGap are skipped', () {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      analyzer.observeTransport(TransportMode.vehicle);
      _feedVibration(analyzer);
      analyzer.observeSpeed(20, at: _t0);
      analyzer.observeSpeed(
        0,
        at: _t0.add(const Duration(milliseconds: 100)),
      ); // skipped
      analyzer.observeSpeed(0, at: _t0.add(const Duration(seconds: 2)));
      analyzer.observeSpeed(0, at: _t0.add(const Duration(seconds: 4)));
      analyzer.observeSpeed(0, at: _t0.add(const Duration(seconds: 6)));

      expect(analyzer.events, hasLength(1));
      final DrivingEvent event = analyzer.events.single;
      expect(event.type, DrivingEventType.harshBraking);
      expect(event.peakMps2, closeTo(-10, 0.001));
      expect(event.startedAt, _t0.add(const Duration(seconds: 2)));
    });

    test('negative and non-finite speeds are ignored', () {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      analyzer.observeSpeed(-5, at: _t0);
      analyzer.observeSpeed(double.nan, at: _t0);
      analyzer.observeSpeed(double.infinity, at: _t0);
      expect(analyzer.instantAccelerationMps2, isNull);

      analyzer.observeSpeed(10, at: _t0);
      analyzer.observeSpeed(20, at: _t0.add(const Duration(seconds: 1)));
      expect(analyzer.instantAccelerationMps2, closeTo(10, 0.001));
    });

    test('onEvent broadcasts every reported event', () async {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      analyzer.observeTransport(TransportMode.vehicle);
      final List<DrivingEvent> received = <DrivingEvent>[];
      final StreamSubscription<DrivingEvent> subscription =
          analyzer.onEvent.listen(received.add);
      addTearDown(subscription.cancel);

      _feedVibration(analyzer);
      _feedSpeeds(analyzer, const <double>[15, 10, 5, 0, 0]);
      await Future<void>.delayed(Duration.zero);

      expect(received, analyzer.events);
    });

    test('reset clears history, evidence and the armed window', () {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      analyzer.observeTransport(TransportMode.vehicle);
      _feedVibration(analyzer);
      _feedSpeeds(analyzer, const <double>[15, 10, 5, 0, 0]);
      expect(analyzer.events, hasLength(1));

      analyzer.reset();
      expect(analyzer.events, isEmpty);
      expect(analyzer.lastVarianceRms, isNull);
      expect(analyzer.instantAccelerationMps2, isNull);
    });
  });
}
