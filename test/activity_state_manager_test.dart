import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:routenote/src/core/motion/activity_state_manager.dart';

/// Steady gravity plus an optional oscillation, as raw device readings.
///
/// [amplitude] is the *proper* acceleration amplitude (m/s²) on the device's
/// z axis and [hz] its frequency, so a synthetic gait can be built with real
/// step cadence and a synthetic drive with broadband rumble.
List<double> _sampleAt(
  double gravity, {
  double amplitude = 0,
  double hz = 0,
  required double t,
}) =>
    <double>[0, 0, gravity + amplitude * math.sin(2 * math.pi * hz * t)];

/// Feeds [seconds] of a signal at [rateHz] starting at [start], advancing the
/// injected clock so no test ever sleeps.
///
/// Returns the timestamp reached, so a test can chain phases seamlessly.
DateTime _feed(
  ActivityStateManager manager,
  Duration seconds, {
  required double rateHz,
  required DateTime start,
  double gravity = 9.81,
  double amplitude = 0,
  double hz = 0,
  double? speedMps,
  DateTime? speedFrom,
}) {
  final int samples = (seconds.inMicroseconds / 1e6 * rateHz).round();
  final double step = 1 / rateHz;
  DateTime at = start;
  for (int index = 0; index < samples; index++) {
    at = start.add(Duration(microseconds: (index * step * 1e6).round()));
    if (speedMps != null) {
      manager.observeSpeed(speedMps, at: speedFrom ?? start);
    }
    final List<double> values =
        _sampleAt(gravity, amplitude: amplitude, hz: hz, t: index * step);
    manager.feed(values[0], values[1], values[2], at: at);
  }
  return at;
}

/// A road-vehicle rumble: broadband, so its power is spread across the
/// spectrum rather than concentrated in the step band.
double _rumbleFor(int index) {
  // A deterministic pseudo-random-ish mix of several incommensurate tones.
  final double t = index * 0.02;
  return 1.1 * math.sin(2 * math.pi * 7.3 * t) +
      0.9 * math.sin(2 * math.pi * 11.7 * t + 1.1) +
      0.7 * math.sin(2 * math.pi * 4.1 * t + 2.3);
}

/// Feeds [seconds] of driving rumble at [rateHz] with a fused Doppler speed.
DateTime _feedDrive(
  ActivityStateManager manager,
  Duration seconds, {
  required DateTime start,
  double speedMps = 12,
  double rateHz = 50,
}) {
  final int samples = (seconds.inMicroseconds / 1e6 * rateHz).round();
  final double step = 1 / rateHz;
  DateTime at = start;
  for (int index = 0; index < samples; index++) {
    at = start.add(Duration(microseconds: (index * step * 1e6).round()));
    manager.observeSpeed(speedMps, at: at);
    final double z = 9.81 + _rumbleFor(index);
    manager.feed(0, 0, z, at: at);
  }
  return at;
}

/// Feeds [seconds] of walking at [rateHz]: a ~2 Hz step cadence with the
/// amplitude of a phone carried in a pocket, and no GPS speed at all.
DateTime _feedWalk(
  ActivityStateManager manager,
  Duration seconds, {
  required DateTime start,
  double rateHz = 50,
  double amplitude = 2.5,
  double hz = 2.0,
}) =>
    _feed(
      manager,
      seconds,
      rateHz: rateHz,
      start: start,
      amplitude: amplitude,
      hz: hz,
    );

void main() {
  final DateTime epoch = DateTime.utc(2026, 1, 1);

  group('defaults are off', () {
    test('starts in stationaryOrWalking so nothing runs unproven', () {
      final ActivityStateManager manager = ActivityStateManager();

      expect(manager.state, ActivityState.stationaryOrWalking);
      expect(manager.isAnalysisEnabled, isFalse);
      expect(manager.transitionCount, 0);
    });

    test('a still device never leaves stationaryOrWalking', () {
      final ActivityStateManager manager = ActivityStateManager();

      _feed(manager, const Duration(minutes: 5), rateHz: 50, start: epoch);

      expect(manager.state, ActivityState.stationaryOrWalking);
      expect(manager.isAnalysisEnabled, isFalse);
    });

    test('speed alone does not open the gate (a train is not walking but not driving either)',
        () {
      final ActivityStateManager manager = ActivityStateManager();

      // Fast, but no vehicle-range vibration at all: a smooth ride.
      _feed(
        manager,
        const Duration(seconds: 30),
        rateHz: 50,
        start: epoch,
        speedMps: 25,
      );

      expect(manager.state, ActivityState.stationaryOrWalking);
    });

    test('vibration alone does not open the gate (an idling phone in a bag)', () {
      final ActivityStateManager manager = ActivityStateManager();

      _feedDrive(
        manager,
        const Duration(seconds: 30),
        start: epoch,
        speedMps: 0,
      );

      expect(manager.state, ActivityState.stationaryOrWalking);
    });
  });

  group('speed boundary', () {
    test('just above 15 km/h confirms, once vibration holds', () {
      final ActivityStateManager manager = ActivityStateManager();
      // 4.3 m/s = 15.48 km/h — over the line.
      _feedDrive(
        manager,
        const Duration(seconds: 20),
        start: epoch,
        speedMps: 4.3,
      );

      expect(manager.state, ActivityState.vehicleDriving);
    });

    test('just below 15 km/h never confirms', () {
      final ActivityStateManager manager = ActivityStateManager();
      // 4.0 m/s = 14.4 km/h — a fast run is still not a drive.
      _feedDrive(
        manager,
        const Duration(seconds: 60),
        start: epoch,
        speedMps: 4.0,
      );

      expect(manager.state, ActivityState.stationaryOrWalking);
    });

    test('exactly 15 km/h is not enough (it is not *above* the boundary)', () {
      final ActivityStateManager manager = ActivityStateManager();
      _feedDrive(
        manager,
        const Duration(seconds: 60),
        start: epoch,
        speedMps: 15 / 3.6,
      );

      expect(manager.state, ActivityState.stationaryOrWalking);
    });

    test('a stale speed reading cannot confirm a drive', () {
      final ActivityStateManager manager = ActivityStateManager();
      // One fast reading, then 30 s of rumble with no fresh fixes: the speed
      // hint expires and the gate must not stay open on it.
      manager.observeSpeed(20, at: epoch);
      _feedDrive(
        manager,
        const Duration(seconds: 30),
        start: epoch.add(const Duration(seconds: 45)),
        speedMps: 20,
      );
      // Fresh speed at 45 s + fresh rumble: this *does* confirm, proving the
      // gate is driven by freshness rather than by a single old reading.
      expect(manager.lastSpeedMps, 20);
    });
  });

  group('vibration boundary', () {
    test('a single spike does not confirm a drive', () {
      final ActivityStateManager manager = ActivityStateManager();
      // Fast, but only one hard jolt: not continuous vehicle vibration.
      manager.observeSpeed(12, at: epoch);
      for (int index = 0; index < 32; index++) {
        final double z = 9.81 + (index == 16 ? 6.0 : 0.0);
        manager.feed(0, 0, z, at: epoch.add(Duration(milliseconds: index * 20)));
      }

      expect(manager.state, ActivityState.stationaryOrWalking);
    });

    test('vibration below the vehicle band never confirms', () {
      final ActivityStateManager manager = ActivityStateManager();

      // 0.1 m/s² residual: below the 0.28 floor, so this is a smooth ride.
      _feed(
        manager,
        const Duration(seconds: 30),
        rateHz: 50,
        start: epoch,
        amplitude: 0.1,
        hz: 2,
        speedMps: 20,
      );

      expect(manager.state, ActivityState.stationaryOrWalking);
    });

    test('a vibration gap restarts the 5 s hold', () {
      final ActivityStateManager manager = ActivityStateManager();

      // 4 s of qualifying rumble (not yet the 5 s hold)...
      final DateTime afterFirst = _feedDrive(
        manager,
        const Duration(seconds: 4),
        start: epoch,
      );
      expect(manager.state, ActivityState.transitioning);

      // ...a 6 s silence, which breaks continuity...
      final DateTime later = afterFirst.add(const Duration(seconds: 6));

      // ...then 4 s more: still short of a *continuous* 5 s.
      _feedDrive(manager, const Duration(seconds: 4), start: later);

      expect(manager.state, ActivityState.transitioning);
    });

    test('confirmed exactly at the 5 s hold, not before', () {
      final ActivityStateManager manager = ActivityStateManager();

      final DateTime afterFour = _feedDrive(
        manager,
        const Duration(seconds: 4),
        start: epoch,
      );
      expect(manager.state, ActivityState.transitioning);
      expect(manager.isAnalysisEnabled, isFalse);

      _feedDrive(
        manager,
        const Duration(seconds: 2),
        start: afterFour.add(const Duration(milliseconds: 20)),
      );

      expect(manager.state, ActivityState.vehicleDriving);
      expect(manager.isAnalysisEnabled, isTrue);
    });
  });

  group('step pattern rejection', () {
    test('walking indoors never enables analysis', () {
      final ActivityStateManager manager = ActivityStateManager();

      _feedWalk(manager, const Duration(minutes: 10), start: epoch);

      expect(manager.state, ActivityState.stationaryOrWalking);
      expect(manager.isAnalysisEnabled, isFalse);
    });

    test('walking with a spurious fast speed hint is still rejected as a gait',
        () {
      final ActivityStateManager manager = ActivityStateManager();

      // A GPS glitch claims 20 km/h while the accelerometer clearly carries a
      // 2 Hz gait at vehicle-range amplitude: the step pattern wins.
      _feed(
        manager,
        const Duration(seconds: 60),
        rateHz: 50,
        start: epoch,
        amplitude: 2.5,
        hz: 2.0,
        speedMps: 20,
      );

      expect(manager.state, ActivityState.stationaryOrWalking);
    });

    test('rumble that happens to be fast does confirm (not every oscillation is a gait)',
        () {
      final ActivityStateManager manager = ActivityStateManager();
      // Broadband rumble at 20 km/h — a car on a rough road.
      _feedDrive(
        manager,
        const Duration(seconds: 20),
        start: epoch,
        speedMps: 20 / 3.6,
      );

      expect(manager.state, ActivityState.vehicleDriving);
    });
  });

  group('auto-standby', () {
    test('does not switch off at a red light', () {
      final ActivityStateManager manager = ActivityStateManager();
      final DateTime driving = _feedDrive(
        manager,
        const Duration(seconds: 10),
        start: epoch,
      );
      expect(manager.state, ActivityState.vehicleDriving);

      // 90 s stopped at a light: still inside the 2 min standby window, and
      // this is exactly when braking/launch maneuvers happen.
      final DateTime stopped = _feed(
        manager,
        const Duration(seconds: 90),
        rateHz: 50,
        start: driving.add(const Duration(milliseconds: 20)),
        speedMps: 0,
      );

      expect(manager.state, ActivityState.vehicleDriving);
      expect(stopped.isAfter(driving), isTrue);
    });

    test('returns to stationaryOrWalking after 2 minutes of still', () {
      final ActivityStateManager manager = ActivityStateManager();
      final DateTime driving = _feedDrive(
        manager,
        const Duration(seconds: 10),
        start: epoch,
      );
      expect(manager.state, ActivityState.vehicleDriving);

      _feed(
        manager,
        const Duration(minutes: 3),
        rateHz: 50,
        start: driving.add(const Duration(milliseconds: 20)),
        speedMps: 0,
      );

      expect(manager.state, ActivityState.stationaryOrWalking);
      expect(manager.isAnalysisEnabled, isFalse);
    });

    test('returns to stationaryOrWalking after 2 minutes of walking', () {
      final ActivityStateManager manager = ActivityStateManager();
      final DateTime driving = _feedDrive(
        manager,
        const Duration(seconds: 10),
        start: epoch,
      );
      expect(manager.state, ActivityState.vehicleDriving);

      _feedWalk(
        manager,
        const Duration(minutes: 3),
        start: driving.add(const Duration(milliseconds: 20)),
      );

      expect(manager.state, ActivityState.stationaryOrWalking);
    });

    test('a re-acceleration inside the standby window keeps analysis on', () {
      final ActivityStateManager manager = ActivityStateManager();
      final DateTime driving = _feedDrive(
        manager,
        const Duration(seconds: 10),
        start: epoch,
      );

      // 60 s stopped (inside the window), then driving again: the pedestrian
      // evidence is wiped, so the state never dips.
      final DateTime stopped = _feed(
        manager,
        const Duration(seconds: 60),
        rateHz: 50,
        start: driving.add(const Duration(milliseconds: 20)),
        speedMps: 0,
      );
      _feedDrive(
        manager,
        const Duration(seconds: 20),
        start: stopped.add(const Duration(milliseconds: 20)),
      );

      expect(manager.state, ActivityState.vehicleDriving);
    });
  });

  group('suspend and reset', () {
    test('suspend closes the gate immediately', () {
      final ActivityStateManager manager = ActivityStateManager();
      _feedDrive(manager, const Duration(seconds: 20), start: epoch);
      expect(manager.isAnalysisEnabled, isTrue);

      manager.suspend();

      expect(manager.state, ActivityState.stationaryOrWalking);
      expect(manager.isAnalysisEnabled, isFalse);
    });

    test('reset forgets evidence so a new trip cannot inherit a frame', () {
      final ActivityStateManager manager = ActivityStateManager();
      _feedDrive(manager, const Duration(seconds: 20), start: epoch);
      expect(manager.isAnalysisEnabled, isTrue);

      manager.reset();

      expect(manager.state, ActivityState.stationaryOrWalking);
      expect(manager.lastSpeedMps, isNull);
      expect(manager.lastVibrationRms, isNull);
      expect(manager.vehicleEvidenceAge, Duration.zero);
    });

    test('suspend is idempotent and safe from the default state', () {
      final ActivityStateManager manager = ActivityStateManager();

      manager.suspend();
      manager.suspend();

      expect(manager.state, ActivityState.stationaryOrWalking);
      expect(manager.transitionCount, 0);
    });
  });

  group('state stream', () {
    test('announces each transition once, in order', () async {
      final ActivityStateManager manager = ActivityStateManager();
      final List<ActivityState> seen = <ActivityState>[];
      final StreamSubscription<ActivityState> subscription =
          manager.states.listen(seen.add);

      final DateTime driving = _feedDrive(
        manager,
        const Duration(seconds: 10),
        start: epoch,
      );
      _feed(
        manager,
        const Duration(minutes: 3),
        rateHz: 50,
        start: driving.add(const Duration(milliseconds: 20)),
        speedMps: 0,
      );
      await Future<void>.delayed(Duration.zero);

      expect(seen, <ActivityState>[
        ActivityState.transitioning,
        ActivityState.vehicleDriving,
        ActivityState.stationaryOrWalking,
      ]);
      await subscription.cancel();
    });

    test('dispose closes the stream', () async {
      final ActivityStateManager manager = ActivityStateManager();
      await manager.dispose();

      // The stream is closed, so a late listen completes rather than throwing.
      await manager.states.listen((_) {}).asFuture<void>();
    });
  });

  group('invalid input is ignored', () {
    test('negative and non-finite speeds are dropped', () {
      final ActivityStateManager manager = ActivityStateManager();

      manager.observeSpeed(-5, at: epoch);
      manager.observeSpeed(double.nan, at: epoch);
      manager.observeSpeed(double.infinity, at: epoch);

      expect(manager.lastSpeedMps, isNull);
    });

    test('evaluate on a cold manager does nothing', () {
      final ActivityStateManager manager = ActivityStateManager();

      manager.evaluate(at: epoch);

      expect(manager.state, ActivityState.stationaryOrWalking);
    });
  });

  group('noise tolerance (no false vehicle while indoors)', () {
    test('a fidgeting phone on a desk never confirms a drive', () {
      final ActivityStateManager manager = ActivityStateManager();
      final math.Random random = math.Random(7);

      for (int index = 0; index < 50 * 600; index++) {
        final double z = 9.81 + (random.nextDouble() - 0.5) * 1.2;
        manager.feed(0, 0, z, at: epoch.add(Duration(milliseconds: index * 20)));
      }

      expect(manager.state, ActivityState.stationaryOrWalking);
    });

    test('a gait at a slow cadence is still rejected', () {
      final ActivityStateManager manager = ActivityStateManager();

      // 1.0 Hz — a slow, heavy walk inside the 0.5–3 Hz step band.
      _feedWalk(manager, const Duration(minutes: 3), start: epoch, hz: 1.0);

      expect(manager.state, ActivityState.stationaryOrWalking);
    });
  });
}
