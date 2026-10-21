import 'dart:async';

/// Detects sustained stationary / idle periods from accelerometer samples so
/// the adaptive engine can drop to the lowest power tier (and pause the
/// location stream) during zero-motion windows, reducing battery drain.
///
/// **Foundation (Phase 3 follow-up).** This detector is intentionally decoupled
/// from the sensor hub: callers feed it samples and observe [isIdle]. It does
/// not open any platform channel or Hive box, and it never stores coordinates
/// or identity (`AGENT_SKILLS.md` §6).
class StationaryIdleDetector {
  StationaryIdleDetector({
    this.sampleWindow = const Duration(seconds: 10),
    this.motionThresholdG = 0.05,
  });

  /// How long samples must stay within [motionThresholdG] before idle is
  /// declared.
  final Duration sampleWindow;

  /// Acceleration magnitude (in g) above which the device is considered
  /// moving.
  final double motionThresholdG;

  final StreamController<bool> _controller =
      StreamController<bool>.broadcast();

  /// Emits `true` when the device has been stationary for [sampleWindow],
  /// `false` the moment motion is observed.
  Stream<bool> get idleChanges => _controller.stream;

  bool _idle = false;
  bool get isIdle => _idle;

  final List<double> _recentMagnitudes = <double>[];
  DateTime? _windowStart;

  /// Feed one accelerometer magnitude (in g). Updates [isIdle] and emits on
  /// [idleChanges] only when the verdict changes.
  void observe(double magnitudeG) {
    final DateTime now = DateTime.now();
    _windowStart ??= now;
    _recentMagnitudes.add(magnitudeG);
    // Trim samples older than the window.
    while (_recentMagnitudes.length > 64) {
      _recentMagnitudes.removeAt(0);
    }
    final bool moving = magnitudeG > motionThresholdG;
    if (moving) {
      if (_idle) {
        _idle = false;
        _controller.add(false);
      }
      _recentMagnitudes.clear();
      _windowStart = now;
      return;
    }
    if (!_idle && _windowStart != null &&
        now.difference(_windowStart!) >= sampleWindow) {
      _idle = true;
      _controller.add(true);
    }
  }

  /// Reset all state (e.g. on trip start).
  void reset() {
    _idle = false;
    _recentMagnitudes.clear();
    _windowStart = null;
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
