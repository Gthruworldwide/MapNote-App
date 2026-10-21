import 'dart:async';

/// Motion state published by [StationaryIdleDetector].
enum MotionState { active, stationary }

/// Detects sustained stationary / idle periods so the adaptive engine can
/// drop to a low-power tier (and pause/throttle the location stream) during
/// zero-motion windows, reducing battery drain.
///
/// Spec:
/// - Transition to [MotionState.stationary] when movement stays below
///   [motionThreshold] (0.2 m/s²) for [stationaryWindow] (5 min).
/// - Instant wakeup to [MotionState.active] when sustained acceleration >=
///   [wakeupThreshold] (0.5 m/s²) for [wakeupWindow] (3 s).
///
/// The detector is decoupled from any sensor or Hive box: callers feed it
/// samples via [observeAcceleration] / [observeSpeed] and observe [state] /
/// [stateChanges]. It never stores coordinates or identity.
class StationaryIdleDetector {
  StationaryIdleDetector({
    this.motionThreshold = 0.2,
    this.stationaryWindow = const Duration(minutes: 5),
    this.wakeupThreshold = 0.5,
    this.wakeupWindow = const Duration(seconds: 3),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final double motionThreshold;
  final Duration stationaryWindow;
  final double wakeupThreshold;
  final Duration wakeupWindow;

  final DateTime Function() _clock;

  final StreamController<MotionState> _controller =
      StreamController<MotionState>.broadcast(sync: true);

  /// Emits whenever the state changes.
  Stream<MotionState> get stateChanges => _controller.stream;

  MotionState _state = MotionState.active;
  MotionState get state => _state;

  DateTime? _stationarySince;
  DateTime? _motionSince;

  /// Feed an accelerometer magnitude in m/s².
  void observeAcceleration(double magnitude) {
    final DateTime now = _clock();
    if (magnitude >= wakeupThreshold) {
      _motionSince ??= now;
      if (_state == MotionState.stationary &&
          now.difference(_motionSince!) >= wakeupWindow) {
        _transition(MotionState.active);
      }
    } else {
      _motionSince = null;
    }

    if (magnitude < motionThreshold) {
      _stationarySince ??= now;
      if (_state == MotionState.active &&
          now.difference(_stationarySince!) >= stationaryWindow) {
        _transition(MotionState.stationary);
      }
    } else {
      _stationarySince = null;
      if (_state == MotionState.stationary && magnitude >= wakeupThreshold) {
        // handled above
      }
    }
  }

  /// Feed a GPS speed in m/s (used when no accelerometer is available).
  void observeSpeed(double speedMps) {
    // Treat speed as motion evidence: any non-trivial speed keeps us active.
    if (speedMps >= 0.5) {
      _stationarySince = null;
      _motionSince ??= _clock();
      if (_state == MotionState.stationary) {
        _transition(MotionState.active);
      }
    } else {
      _motionSince = null;
      _stationarySince ??= _clock();
    }
  }

  void _transition(MotionState next) {
    if (next == _state) return;
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
    if (next == MotionState.active) {
      _stationarySince = null;
    } else {
      _motionSince = null;
    }
  }

  /// Force a state (testing).
  void setState(MotionState s) => _transition(s);

  void reset() {
    _state = MotionState.active;
    _stationarySince = null;
    _motionSince = null;
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
