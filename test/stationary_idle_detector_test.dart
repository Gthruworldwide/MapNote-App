import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/core/motion/stationary_idle_detector.dart';

void main() {
  test('starts active', () {
    final StationaryIdleDetector d = StationaryIdleDetector();
    expect(d.state, MotionState.active);
  });

  test('transitions to stationary after 5 min below threshold', () {
    DateTime now = DateTime(2026, 1, 1, 12, 0, 0);
    final StationaryIdleDetector d = StationaryIdleDetector(clock: () => now);
    final List<MotionState> events = <MotionState>[];
    d.stateChanges.listen(events.add);

    // below threshold for 4 min 59 s -> still active
    d.observeAcceleration(0.1);
    now = now.add(const Duration(minutes: 4, seconds: 59));
    d.observeAcceleration(0.1);
    expect(d.state, MotionState.active);

    // reach 5 min -> stationary
    now = now.add(const Duration(seconds: 2));
    d.observeAcceleration(0.1);
    expect(d.state, MotionState.stationary);
    expect(events, contains(MotionState.stationary));
  });

  test('motion resets stationary timer', () {
    DateTime now = DateTime(2026, 1, 1, 12, 0, 0);
    final StationaryIdleDetector d = StationaryIdleDetector(clock: () => now);
    d.observeAcceleration(0.1);
    now = now.add(const Duration(minutes: 3));
    d.observeAcceleration(0.5); // motion above threshold resets
    now = now.add(const Duration(minutes: 3));
    d.observeAcceleration(0.1);
    // only 3 min since reset, not 5 -> still active
    expect(d.state, MotionState.active);
  });

  test('wakes up after 3 s of sustained acceleration', () {
    DateTime now = DateTime(2026, 1, 1, 12, 0, 0);
    final StationaryIdleDetector d = StationaryIdleDetector(clock: () => now);
    // force stationary
    d.observeAcceleration(0.1);
    now = now.add(const Duration(minutes: 5));
    d.observeAcceleration(0.1);
    expect(d.state, MotionState.stationary);

    final List<MotionState> events = <MotionState>[];
    d.stateChanges.listen(events.add);

    // 2 s of motion -> still stationary
    d.observeAcceleration(0.6);
    now = now.add(const Duration(seconds: 2));
    d.observeAcceleration(0.6);
    expect(d.state, MotionState.stationary);

    // reach 3 s -> active
    now = now.add(const Duration(seconds: 2));
    d.observeAcceleration(0.6);
    expect(d.state, MotionState.active);
    expect(events, contains(MotionState.active));
  });

  test('reset returns to active', () {
    DateTime now = DateTime(2026, 1, 1, 12, 0, 0);
    final StationaryIdleDetector d = StationaryIdleDetector(clock: () => now);
    d.observeAcceleration(0.1);
    now = now.add(const Duration(minutes: 5));
    d.observeAcceleration(0.1);
    expect(d.state, MotionState.stationary);
    d.reset();
    expect(d.state, MotionState.active);
  });

  test('observeSpeed keeps active on non-trivial speed', () {
    final StationaryIdleDetector d = StationaryIdleDetector();
    d.observeSpeed(1.0);
    expect(d.state, MotionState.active);
  });
}
