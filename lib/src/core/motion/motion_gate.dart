import 'dart:async';

import '../../services/motion_sensor_hub.dart';
import 'activity_state_manager.dart';

/// Gatekeeper that stands **in front of** the analysis pipeline.
///
/// [ActivityStateManager] decides *whether* the device is in a vehicle; this
/// class turns that verdict into the thing the analysis components actually
/// need — an accelerometer feed that carries samples while driving and carries
/// **nothing** otherwise.
///
/// That distinction matters for battery and heat. Stopping at a boolean check
/// inside the analyzer would still pay for every sample: a subscription, a
/// timestamp, a gravity EMA, an FFT window, and (for the classifier) a push into
/// a 128-sample ring buffer. Indoors that is pure waste, because a walking gait
/// can never be classified as a maneuver. Here the analysis sources simply do
/// not receive events, so their `feedSample` is never called and their buffers
/// never fill — the only work left running is the gate's own cheap window
/// judgement over the raw feed.
///
/// The gate therefore owns **two** subscriptions' worth of responsibility:
///
/// * it listens to the raw hub, feeding every sample to [ActivityStateManager]
///   (the evidence that opens or closes the gate), and
/// * it republishes samples on [gated] only while the state allows analysis.
///
/// [gated] is a broadcast stream, so the analyzer and the classifier each keep
/// their own subscription to it exactly as they would to the hub.
///
/// Nothing here is persisted or transmitted: samples are read for their
/// magnitude and cadence only, never their location.
class MotionGate {
  MotionGate({
    required this.manager,
    required this.hub,
    this.accelerationStream,
  });

  /// The state machine whose verdict drives the gate.
  final ActivityStateManager manager;

  /// The shared motion hub this gate borrows the raw feed from.
  final MotionSensorHub hub;

  /// Overrides the raw accelerometer source (tests drive this directly, so no
  /// platform channel or native hub is required).
  final Stream<AccelerometerSample>? accelerationStream;

  final StreamController<AccelerometerSample> _gated =
      StreamController<AccelerometerSample>.broadcast();

  StreamSubscription<AccelerometerSample>? _raw;
  bool _running = false;

  /// Samples forwarded to the analysis pipeline since [start].
  int _forwarded = 0;

  /// Samples swallowed by the gate since [start] — the CPU the user did not pay
  /// for. Diagnostics only.
  int _suppressed = 0;

  /// The feed the analysis components consume: samples **only** while the device
  /// is a confirmed vehicle. Broadcast, so several subscribers can share it.
  Stream<AccelerometerSample> get gated => _gated.stream;

  /// Whether the raw feed is currently being watched.
  bool get isRunning => _running;

  /// Whether analysis is currently permitted (the state manager's verdict).
  bool get allowsAnalysis => manager.isAnalysisEnabled;

  /// How many samples reached the pipeline (diagnostics).
  int get forwardedSamples => _forwarded;

  /// How many samples the gate withheld (diagnostics).
  int get suppressedSamples => _suppressed;

  /// Opens the raw feed and starts gating. Idempotent.
  ///
  /// A sample that *closes* the gate is the last one forwarded, and a sample
  /// that opens it is the first of the new run — the closed-open boundary is
  /// deliberately per-sample rather than per-state-transition, so a maneuver
  /// beginning in the same window that confirms the drive is not lost.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _raw = (accelerationStream ?? hub.accelerometer).listen(_onSample);
  }

  /// Closes the raw feed and releases the native reference. Idempotent.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _raw?.cancel();
    _raw = null;
  }

  /// Forgets all evidence and shuts the gate: a new trip must not inherit the
  /// previous drive's state. The stream itself stays open, so subscribed
  /// analysis components simply go quiet.
  void reset() {
    manager.reset();
    _forwarded = 0;
    _suppressed = 0;
  }

  /// Forces the gate shut without discarding the evidence buffers.
  void suspend() => manager.suspend();

  /// Feeds one raw sample through the gate. Public so tests (and a caller
  /// holding an already-open feed) can drive it without a stream at all.
  void feed(AccelerometerSample sample) => _onSample(sample);

  void _onSample(AccelerometerSample sample) {
    manager.feed(sample.x, sample.y, sample.z, at: sample.at);
    if (manager.isAnalysisEnabled) {
      _forwarded += 1;
      if (!_gated.isClosed) _gated.add(sample);
    } else {
      _suppressed += 1;
    }
  }

  /// Releases the broadcast stream. The gate is unusable afterwards.
  Future<void> dispose() async {
    await stop();
    if (!_gated.isClosed) await _gated.close();
  }
}
