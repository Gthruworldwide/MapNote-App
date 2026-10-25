import 'dart:async';

/// Opens a fresh stream of **absolute** step counts — steps since the device
/// booted — from the hardware pedometer.
///
/// A factory, not a stream: the OS sensor is registered when the stream is
/// listened to and released when it is cancelled, so re-opening the feed (see
/// [StepMeter.refresh]) has to ask for a new one. Production supplies
/// `hardwareStepCount` from `pedometer_steps.dart` (`pedometer` package:
/// Android `TYPE_STEP_COUNTER`, iOS `CMPedometer`).
typedef StepCountSource = Stream<int> Function();

/// Turns the OS's absolute step counter into the per-fix step increments the
/// daily tracker stamps onto its track points.
///
/// The hardware counter is a **monotonic absolute** number — steps since the
/// device booted — and it only emits when the value changes. The engine needs
/// something else entirely: "how many steps were taken between this fix and the
/// previous one", so walking and running distance can be measured instead of
/// inferred from a GPS polyline.
///
/// This class is the single adapter between the two:
///
/// ```
/// sensor: 0 … 4210 ──► 4235 ──► 4290        (absolute, on change)
/// meter:             25     55              (deltas, per drain())
/// ```
///
/// * [drain] returns the steps accumulated since the previous call, so each
///   accepted fix owns exactly its own steps and a day's totals are the sum of
///   the persisted increments.
/// * It returns **`null`** while no sample has arrived, which is the honest
///   "this device has no pedometer / the permission is denied" answer. The
///   classifier uses that to fall back to its GPS-speed bands, so history stays
///   browsable on hardware without a step sensor.
/// * It returns **`0`** once a sample exists but no step was taken — a
///   *measurement*, not an absence of one. That distinction is what lets the
///   classifier call a GPS fix "vehicle" instead of guessing between walking
///   and driving.
///
/// The meter holds the hardware feed open for exactly as long as it is started,
/// so the step sensor is never registered by a tracker that is not recording.
class StepMeter {
  StepMeter({this.stepCounts});

  /// The hardware feed; `null` in unit tests and on platforms without one
  /// (where [drain] simply always answers `null`). Production supplies
  /// `hardwareStepCount` from `pedometer_steps.dart`.
  final StepCountSource? stepCounts;

  StreamSubscription<int>? _subscription;
  bool _running = false;
  bool _disposed = false;

  /// False until the first sample after [start] — the moment the meter learns
  /// its baseline. Steps taken before that belong to a previous trip.
  bool _hasSample = false;

  /// The last absolute counter value consumed.
  int _lastRaw = 0;

  /// Steps observed but not yet handed out by [drain].
  int _pending = 0;

  /// Steps attributed since [start], including the ones still pending.
  int _total = 0;

  /// Whether the meter currently holds the hardware feed open.
  bool get isRunning => _running;

  /// Whether the device has actually delivered a step sample this session.
  /// `false` means "no pedometer" — the classifier falls back to GPS speed.
  bool get hasSensor => _hasSample;

  /// Steps taken since [start], including the ones not yet drained.
  int get totalSteps => _total;

  /// Steps accumulated since the previous drain.
  ///
  /// `null` when no sample has arrived yet (no usable pedometer); otherwise the
  /// increment, which may legitimately be `0`.
  int? drain() {
    if (!_hasSample) return null;
    final int steps = _pending;
    _pending = 0;
    return steps;
  }

  /// Subscribes to the hardware feed. Idempotent, so a tracker restarting its
  /// engine cannot register a second sensor listener.
  Future<void> start() async {
    if (_disposed || _running) return;
    _running = true;
    // A new session starts from a *fresh* baseline: steps taken while nothing
    // was recording must not be attributed to this trip.
    _hasSample = false;
    _lastRaw = 0;
    _pending = 0;
    _total = 0;
    _subscribe();
  }

  /// Re-opens the hardware feed once the OS has allowed the step sensor.
  ///
  /// `ACTIVITY_RECOGNITION` is requested *after* recording starts (a permission
  /// dialog must never delay the first fix), so the plugin's first `listen` can
  /// happen while the OS still refuses `TYPE_STEP_COUNTER`. That registration
  /// fails silently — no error, just no sample — so re-subscribing after the
  /// grant is what actually attaches the sensor. The baseline is deliberately
  /// **preserved**: steps taken during the dialog still belong to this trip.
  ///
  /// A no-op unless the meter is running and still waiting for its first
  /// sample, so calling it on every tracking sync costs nothing once the
  /// pedometer is already reporting.
  Future<void> refresh() async {
    if (!_running || _hasSample) return;
    await _cancel();
    _subscribe();
  }

  /// Cancels the subscription and releases the sensor. Idempotent, and safe to
  /// call from a tracker that never managed to start.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _cancel();
  }

  /// Releases everything; the meter is unusable afterwards. Called from
  /// `ref.onDispose` so a dropped container never leaves the sensor open.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
  }

  void _subscribe() {
    final StepCountSource? source = stepCounts;
    if (source == null) return;
    try {
      _subscription = source().listen(
        _onSample,
        onError: (Object _) {
          // No sensor, permission refused or plugin absent: stay silent so the
          // classifier falls back to GPS speed. `hasSensor` stays false.
        },
      );
    } catch (_) {
      // A source that throws synchronously (unsupported platform) is the same
      // "no pedometer" answer as an empty stream.
    }
  }

  Future<void> _cancel() async {
    final StreamSubscription<int>? subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  void _onSample(int raw) {
    if (!_hasSample) {
      _hasSample = true;
      _lastRaw = raw;
      return;
    }
    if (raw < _lastRaw) {
      // The counter reset (a reboot mid-session). Whatever was counted belongs
      // to the previous boot; continue from the new baseline instead of
      // reporting a negative increment.
      _lastRaw = raw;
      return;
    }
    final int delta = raw - _lastRaw;
    if (delta <= 0) return;
    _lastRaw = raw;
    _pending += delta;
    _total += delta;
  }
}
