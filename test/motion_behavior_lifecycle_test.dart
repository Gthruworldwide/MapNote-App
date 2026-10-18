import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/app_health_logger.dart';
import 'package:routenote/src/services/motion_profiler.dart';
import 'package:routenote/src/services/motion_sensor_hub.dart';
import 'package:routenote/src/services/transport_classifier.dart';

final DateTime _t0 = DateTime.utc(2026, 1, 1);

/// Feeds [seconds] seconds of 1 Hz speed readings into [analyzer], starting
/// at [start]; [speedsMps] is indexed by second. Identical to the recipe
/// helper in motion_profiler_test.dart.
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
/// Identical to the recipe helper in motion_profiler_test.dart.
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

/// Streams the same vibration waveform as [_feedVibration] through
/// [controller] instead of a direct hand-feed, so the analyzer only sees it
/// through its [MotionBehaviorAnalyzer.start] subscription.
void _addVibration(
  StreamController<AccelerometerSample> controller, {
  DateTime? start,
  int samples = 64,
}) {
  final DateTime from = start ?? _t0;
  for (int i = 0; i < samples; i++) {
    final double seconds = i / 16;
    controller.add(
      AccelerometerSample(
        0,
        0,
        9.81 + 0.5 * math.sin(2 * math.pi * 2 * seconds),
        from.add(Duration(microseconds: (seconds * 1e6).round())),
      ),
    );
  }
}

/// Drives the analyzer through the hard-braking recipe from
/// motion_profiler_test.dart (vibration evidence, vehicle verdict, then
/// 15 → 0 m/s over 4 s), emitting exactly one `harshBraking` event.
void _driveHarshBrake(MotionBehaviorAnalyzer analyzer, {DateTime? start}) {
  final DateTime from = start ?? _t0;
  analyzer.observeTransport(TransportMode.vehicle);
  _feedVibration(analyzer, start: from);
  _feedSpeeds(analyzer, const <double>[15, 10, 5, 0, 0], start: from);
}

/// Drives the analyzer through the harsh-launch recipe from
/// motion_profiler_test.dart (vibration evidence, vehicle verdict, then
/// 0 → 15 m/s over 4 s), emitting exactly one `harshAcceleration` event.
void _driveHarshLaunch(MotionBehaviorAnalyzer analyzer, {DateTime? start}) {
  final DateTime from = start ?? _t0;
  analyzer.observeTransport(TransportMode.vehicle);
  _feedVibration(analyzer, start: from);
  _feedSpeeds(analyzer, const <double>[0, 5, 10, 15, 15], start: from);
}

/// Lets the analyzer's broadcast `onEvent` stream (one microtask hop) and the
/// notifier's state update land before assertions.
Future<void> _settleStream() => Future<void>.delayed(Duration.zero);

/// Builds a container around a REAL [analyzer] with an in-memory health log
/// (no Hive), disposing it at teardown. The logger carries a fake clock at
/// [_t0] + 100 s so `count(within: 7 days)` sees the scripted events.
ProviderContainer _buildContainer(MotionBehaviorAnalyzer analyzer) {
  final AppHealthLogger logger = AppHealthLogger(
    null,
    clock: () => _t0.add(const Duration(seconds: 100)),
  );
  final ProviderContainer container = ProviderContainer(
    overrides: [
      motionBehaviorAnalyzerProvider.overrideWithValue(analyzer),
      appHealthLoggerProvider.overrideWithValue(logger),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('MotionBehaviorAnalyzer sensor lifecycle', () {
    test('start() opens the feed and samples reach the variance window',
        () async {
      final StreamController<AccelerometerSample> controller =
          StreamController<AccelerometerSample>(sync: true);
      addTearDown(controller.close);
      final MotionBehaviorAnalyzer analyzer =
          MotionBehaviorAnalyzer(accelerometer: controller.stream);

      expect(analyzer.isRunning, isFalse);
      expect(analyzer.lastVarianceRms, isNull);

      await analyzer.start();
      expect(analyzer.isRunning, isTrue);

      // A synchronous controller delivers on add(), so the window must have
      // the evidence by the time add() returns.
      _addVibration(controller);
      expect(analyzer.lastVarianceRms, isNotNull);
      expect(analyzer.lastVarianceRms!, greaterThanOrEqualTo(0.28),
          reason: 'the streamed waveform must clear the moving floor');
    });

    test('stop() cancels the feed: later samples never reach the window',
        () async {
      final StreamController<AccelerometerSample> controller =
          StreamController<AccelerometerSample>(sync: true);
      addTearDown(controller.close);
      final MotionBehaviorAnalyzer analyzer =
          MotionBehaviorAnalyzer(accelerometer: controller.stream);

      await analyzer.start();
      _addVibration(controller);
      final double rmsBeforeStop = analyzer.lastVarianceRms!;

      await analyzer.stop();
      expect(analyzer.isRunning, isFalse);

      // Loud samples that would move the RMS if the subscription survived.
      for (int i = 0; i < 64; i++) {
        controller.add(
          AccelerometerSample(0, 0, 20, _t0.add(Duration(seconds: i))),
        );
      }
      expect(analyzer.lastVarianceRms, rmsBeforeStop,
          reason: 'no sample may be consumed after stop()');
    });

    test('start() twice subscribes exactly once', () async {
      final StreamController<AccelerometerSample> controller =
          StreamController<AccelerometerSample>(sync: true);
      addTearDown(controller.close);
      final MotionBehaviorAnalyzer analyzer =
          MotionBehaviorAnalyzer(accelerometer: controller.stream);
      final MotionBehaviorAnalyzer reference = MotionBehaviorAnalyzer();

      await analyzer.start();
      // Idempotent: the stream is single-subscription, so a second
      // `listen` would throw a StateError out of this await.
      await analyzer.start();
      expect(analyzer.isRunning, isTrue);

      // Each sample consumed exactly once: the stream-fed window must match
      // a hand-fed reference fed the identical waveform sample-for-sample
      // (a double subscription would replay every sample and drift).
      _addVibration(controller);
      _addVibration(
        controller,
        start: _t0.add(const Duration(seconds: 10)),
        samples: 8,
      );
      _feedVibration(reference);
      _feedVibration(
        reference,
        start: _t0.add(const Duration(seconds: 10)),
        samples: 8,
      );
      expect(analyzer.lastVarianceRms, reference.lastVarianceRms);
    });

    test('stop() before start and stop() twice are safe', () async {
      final StreamController<AccelerometerSample> controller =
          StreamController<AccelerometerSample>(sync: true);
      addTearDown(controller.close);
      final MotionBehaviorAnalyzer analyzer =
          MotionBehaviorAnalyzer(accelerometer: controller.stream);

      // Nothing to cancel yet: both calls must be silent no-ops.
      await analyzer.stop();
      await analyzer.stop();
      expect(analyzer.isRunning, isFalse);

      await analyzer.start();
      await analyzer.stop();
      // Repeated stop() after a real start stays a no-op.
      await analyzer.stop();
      expect(analyzer.isRunning, isFalse);
    });

    test('a stream-less analyzer never runs but still detects by hand',
        () async {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();

      await analyzer.start();
      expect(analyzer.isRunning, isFalse,
          reason: 'no stream was provided, so there is nothing to open');

      // The manual feeds keep working untouched.
      _driveHarshBrake(analyzer);
      expect(analyzer.events, hasLength(1));
      expect(analyzer.events.single.type, DrivingEventType.harshBraking);
    });
  });

  group('DrivingEventsNotifier mirrors the analyzer', () {
    test('mirrors a harsh brake and then a harsh launch, in order', () async {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      final ProviderContainer container = _buildContainer(analyzer);
      final List<List<DrivingEvent>> emissions = <List<DrivingEvent>>[];
      final ProviderSubscription<List<DrivingEvent>> subscription =
          container.listen(
        drivingEventsProvider,
        (List<DrivingEvent>? previous, List<DrivingEvent> next) {
          emissions.add(next);
        },
      );
      addTearDown(subscription.close);

      // Reading once builds the notifier and arms its onEvent subscription.
      expect(container.read(drivingEventsProvider), isEmpty);

      _driveHarshBrake(analyzer);
      await _settleStream();
      expect(container.read(drivingEventsProvider), analyzer.events);
      expect(container.read(drivingEventsProvider), hasLength(1));
      expect(emissions, hasLength(1),
          reason: 'the container listener must fire per event');

      // The launch settles 20 s after the brake, clear of the 10 s cooldown.
      _driveHarshLaunch(analyzer, start: _t0.add(const Duration(seconds: 20)));
      await _settleStream();
      final List<DrivingEvent> mirrored = container.read(drivingEventsProvider);
      expect(mirrored, analyzer.events, reason: 'order preserved, oldest first');
      expect(mirrored, hasLength(2));
      expect(mirrored.first.type, DrivingEventType.harshBraking);
      expect(mirrored.last.type, DrivingEventType.harshAcceleration);
      expect(emissions, hasLength(2));
      expect(emissions.last, mirrored);
    });

    test('a fresh notifier catches up with events detected before it existed',
        () {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      _driveHarshBrake(analyzer);
      expect(analyzer.events, hasLength(1));

      // The notifier is first read only after the event already exists; its
      // initial state must include the catch-up event, synchronously.
      final ProviderContainer container = _buildContainer(analyzer);
      final List<DrivingEvent> state = container.read(drivingEventsProvider);
      expect(state, analyzer.events);
      expect(state.single.type, DrivingEventType.harshBraking);
    });

    test('clear() empties the mirror and the analyzer, and detection resumes',
        () async {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      final ProviderContainer container = _buildContainer(analyzer);
      final DrivingEventsNotifier notifier =
          container.read(drivingEventsProvider.notifier);

      _driveHarshBrake(analyzer);
      await _settleStream();
      expect(container.read(drivingEventsProvider), hasLength(1));

      notifier.clear();
      expect(analyzer.events, isEmpty, reason: 'reset() discards history');
      expect(container.read(drivingEventsProvider), isEmpty);

      // The same analyzer is fully usable after the reset: the recipe emits
      // again and the still-subscribed notifier mirrors the new event.
      _driveHarshBrake(analyzer);
      await _settleStream();
      expect(analyzer.events, hasLength(1));
      expect(container.read(drivingEventsProvider), analyzer.events);
    });

    test('clear() on a fresh notifier is safe', () {
      final ProviderContainer container =
          _buildContainer(MotionBehaviorAnalyzer());
      expect(container.read(drivingEventsProvider), isEmpty);

      container.read(drivingEventsProvider.notifier).clear();

      expect(container.read(drivingEventsProvider), isEmpty);
      expect(container.read(motionBehaviorAnalyzerProvider).events, isEmpty);
    });
  });

  group('DrivingEventsNotifier health-log mirroring', () {
    test('logs one privacy-safe health entry per detected event', () async {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      final ProviderContainer container = _buildContainer(analyzer);
      final List<DrivingEvent> initial =
          container.read(drivingEventsProvider);
      expect(initial, isEmpty);

      _driveHarshBrake(analyzer);
      _driveHarshLaunch(analyzer, start: _t0.add(const Duration(seconds: 20)));
      await _settleStream();

      final AppHealthLogger logger = container.read(appHealthLoggerProvider);
      expect(logger.count(HealthEventType.drivingManeuver), 2);
      final List<HealthEvent> logged = logger.recent();
      expect(logged, hasLength(2), reason: 'the log must hold nothing else');

      // Newest first: the launch, then the brake.
      final HealthEvent launchLog = logged.first;
      final HealthEvent brakeLog = logged.last;
      expect(launchLog.type, HealthEventType.drivingManeuver);
      expect(brakeLog.type, HealthEventType.drivingManeuver);

      // Privacy contract: the payload carries EXACTLY the three sanctioned
      // keys — no coordinates, no place, no identity, nothing else.
      expect(
        launchLog.data.keys.toSet(),
        <String>{'maneuver', 'peak_mps2', 'duration_ms'},
      );
      expect(
        brakeLog.data.keys.toSet(),
        <String>{'maneuver', 'peak_mps2', 'duration_ms'},
      );

      final DrivingEvent brakeEvent = analyzer.events.first;
      final DrivingEvent launchEvent = analyzer.events.last;
      expect(launchLog.data['maneuver'], launchEvent.type.name);
      expect(brakeLog.data['maneuver'], brakeEvent.type.name);
      expect(launchLog.data['peak_mps2'], closeTo(5.0, 0.001));
      expect(brakeLog.data['peak_mps2'], closeTo(-5.0, 0.001));
      expect(launchLog.data['duration_ms'], 3000);
      expect(brakeLog.data['duration_ms'], isA<int>());
      expect(brakeLog.data['duration_ms'] as int, greaterThan(0));
    });
  });

  group('vehicle gating through the notifier', () {
    test('a walking verdict swallows the same recipe: no event, mirror or log',
        () async {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      final ProviderContainer container = _buildContainer(analyzer);
      final List<List<DrivingEvent>> emissions = <List<DrivingEvent>>[];
      final ProviderSubscription<List<DrivingEvent>> subscription =
          container.listen(
        drivingEventsProvider,
        (List<DrivingEvent>? previous, List<DrivingEvent> next) {
          emissions.add(next);
        },
      );
      addTearDown(subscription.close);

      // Identical to the emitting brake recipe except for the verdict.
      analyzer.observeTransport(TransportMode.walking);
      _feedVibration(analyzer);
      _feedSpeeds(analyzer, const <double>[15, 10, 5, 0, 0]);
      await _settleStream();

      expect(analyzer.events, isEmpty);
      expect(container.read(drivingEventsProvider), isEmpty);
      expect(emissions, isEmpty, reason: 'no state churn while walking');
      expect(container.read(appHealthLoggerProvider).recent(), isEmpty,
          reason: 'a suppressed maneuver is never logged');

      // Positive control: the identical recipe under a vehicle verdict
      // emits and reaches the notifier.
      analyzer.reset();
      _driveHarshBrake(analyzer);
      await _settleStream();
      expect(container.read(drivingEventsProvider), hasLength(1));
    });
  });
}
