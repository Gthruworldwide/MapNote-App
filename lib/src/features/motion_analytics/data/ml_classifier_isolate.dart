import 'dart:async';

import '../../../core/sensors/gravity_alignment_calculator.dart';
import '../../../services/motion_sensor_hub.dart';
import '../domain/entities/motion_event.dart';
import '../domain/entities/motion_window.dart';
import '../domain/services/motion_model.dart';
import '../domain/services/motion_inference_runner.dart';
import 'heuristic_motion_model.dart';
import 'isolate_motion_inference_runner.dart';

/// Turns the raw accelerometer feed into classified driving maneuvers.
///
/// The pipeline, end to end:
///
/// 1. **Align** — every sample goes through [GravityAlignmentCalculator], which
///    isolates gravity and rotates the reading into the vehicle frame
///    (`X_car` lateral, `Y_car` vertical, `Z_car` longitudinal).
/// 2. **Buffer** — the gravity-free sample is appended to a
///    [MotionWindow.sampleCount]-sample sliding window at
///    [MotionWindow.sampleRateHz]; the window slides one sample at a time, so
///    every maneuver is seen in full.
/// 3. **Offload** — once the window is full, a fresh one is classified every
///    [hopSamples] samples (16 = 0.32 s) by [MotionInferenceRunner], which in
///    the app is a **dedicated background isolate** so no inference ever runs
///    on the platform thread.
/// 4. **Publish** — predictions become [MotionEvent]s, de-duplicated per kind
///    over [eventCooldown] so one maneuver does not produce an event per
///    overlapping window.
///
/// Uncalibrated driving is *not* guessed at: until
/// [GravityAlignmentCalculator.isAligned] the samples are counted in
/// [uncalibratedSamples] and dropped, because a device-frame reading cannot
/// tell braking from a phone being picked up.
///
/// Everything stays on the device: events carry a kind, a magnitude and a time,
/// never location or identity.
class MLClassifierIsolate {
  /// Builds the pipeline with a caller-supplied [runner] — the seam that lets
  /// tests run the model inline and production run it in an isolate.
  MLClassifierIsolate({
    required this.runner,
    GravityAlignmentCalculator? alignment,
    this.accelerometer,
    this.windowSize = MotionWindow.sampleCount,
    this.hopSamples = 16,
    this.eventCooldown = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : alignment = alignment ?? GravityAlignmentCalculator(),
       _clock = clock ?? DateTime.now,
       assert(windowSize > 0),
       assert(hopSamples > 0);

  /// The app's wiring: the shipped model, built **inside** a dedicated worker
  /// isolate, fed by the hub's accelerometer.
  factory MLClassifierIsolate.standard({
    Stream<AccelerometerSample>? accelerometer,
    GravityAlignmentCalculator? alignment,
    MotionModelBuilder buildModel = buildHeuristicMotionModel,
    Duration inferenceTimeout = const Duration(seconds: 2),
  }) => MLClassifierIsolate(
    runner: IsolateMotionInferenceRunner(
      buildModel: buildModel,
      timeout: inferenceTimeout,
    ),
    alignment: alignment,
    accelerometer: accelerometer,
  );

  /// The [MotionInferenceRunner] that performs the actual inference — the seam
  /// that lets tests run the model inline and production run it in an isolate.
  final MotionInferenceRunner runner;

  /// The accelerometer feed [start] listens to — normally the shared
  /// `MotionSensorHub` broadcast stream. `null` in unit tests, which drive
  /// [feed] directly.
  final Stream<AccelerometerSample>? accelerometer;

  final DateTime Function() _clock;

  /// The live device→vehicle alignment, reused as the pipeline's calibration
  /// state.
  final GravityAlignmentCalculator alignment;

  /// Samples per inference (the model's input length).
  final int windowSize;

  /// New samples between inferences — the window slides by this much.
  final int hopSamples;

  /// Minimum spacing between two events of the *same* kind, so one maneuver
  /// seen in several overlapping windows is reported once.
  final Duration eventCooldown;

  final List<MotionWindowSample> _buffer = <MotionWindowSample>[];
  final List<MotionEvent> _events = <MotionEvent>[];
  final Map<MotionEventKind, DateTime> _lastEmitted =
      <MotionEventKind, DateTime>{};

  StreamController<MotionEvent>? _onEvent =
      StreamController<MotionEvent>.broadcast();
  StreamSubscription<AccelerometerSample>? _subscription;
  int _sinceLastInference = 0;
  int _inferences = 0;
  int _uncalibratedSamples = 0;
  bool _inferenceInFlight = false;
  bool _smoothDriving = false;
  bool _disposed = false;

  /// Classified maneuvers, in order (broadcast: safe to listen late).
  Stream<MotionEvent> get onEvent => _onEvent?.stream ?? const Stream<MotionEvent>.empty();

  /// Everything classified this trip, for a UI that mounts after the fact.
  List<MotionEvent> get events => List<MotionEvent>.unmodifiable(_events);

  /// Whether the accelerometer feed is currently subscribed.
  bool get isRunning => _subscription != null;

  /// Whether a vehicle frame is available (see `GravityAlignmentCalculator`).
  bool get isCalibrated => alignment.isAligned;

  /// Samples currently in the sliding window.
  int get bufferedSamples => _buffer.length;

  /// Samples dropped because the device was not yet calibrated.
  int get uncalibratedSamples => _uncalibratedSamples;

  /// Inferences completed (diagnostics/tests).
  int get inferenceCount => _inferences;

  /// Whether a classification is running on the far side right now.
  bool get inferenceInFlight => _inferenceInFlight;

  /// Subscribes to the accelerometer feed. Safe to call twice.
  Future<void> start() async {
    if (_disposed || _subscription != null) return;
    final Stream<AccelerometerSample>? feed = accelerometer;
    if (feed == null) return;
    _subscription = feed.listen(_onAccelerometerSample);
  }

  /// Unsubscribes from the feed, keeping the buffered window and events.
  Future<void> stop() async {
    final StreamSubscription<AccelerometerSample>? subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  /// Releases the worker isolate. The instance is unusable afterwards.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await runner.dispose();
    final StreamController<MotionEvent>? events = _onEvent;
    _onEvent = null;
    await events?.close();
  }

  /// Forgets the buffered window, the events and the cooldowns — a new trip
  /// starts clean.
  void clear() {
    _buffer.clear();
    _events.clear();
    _lastEmitted.clear();
    _sinceLastInference = 0;
    _smoothDriving = false;
    _uncalibratedSamples = 0;
  }

  /// Feeds one gravity-free vehicle-frame sample.
  ///
  /// Public because it is the deterministic entry point tests drive; the
  /// accelerometer path funnels through the same method after alignment.
  void feed(VehicleAcceleration acceleration, {DateTime? at}) {
    if (_disposed) return;
    _buffer.add(
      MotionWindowSample(
        lateral: acceleration.lateral,
        vertical: acceleration.vertical,
        longitudinal: acceleration.longitudinal,
        at: at ?? _clock(),
      ),
    );
    while (_buffer.length > windowSize) {
      _buffer.removeAt(0);
    }
    _sinceLastInference++;
    if (_buffer.length < windowSize || _sinceLastInference < hopSamples) return;
    // An in-flight inference keeps the samples buffering and simply retries on
    // the next hop, so a slow worker can never queue up work.
    if (_inferenceInFlight) return;
    _sinceLastInference = 0;
    unawaited(_classify());
  }

  void _onAccelerometerSample(AccelerometerSample sample) {
    alignment.addSample(sample.x, sample.y, sample.z);
    final VehicleAcceleration? acceleration = alignment.transform(
      sample.x,
      sample.y,
      sample.z,
    );
    if (acceleration == null) {
      _uncalibratedSamples++;
      return;
    }
    feed(acceleration, at: sample.at);
  }

  Future<void> _classify() async {
    _inferenceInFlight = true;
    final MotionWindow window = MotionWindow(
      List<MotionWindowSample>.unmodifiable(_buffer),
    );
    try {
      final List<MotionPrediction> predictions = await runner.infer(window);
      if (_disposed) return;
      _publish(window, predictions);
    } catch (_) {
      // A failed inference contributes nothing; the next hop retries.
    } finally {
      _inferenceInFlight = false;
      _inferences++;
    }
  }

  void _publish(MotionWindow window, List<MotionPrediction> predictions) {
    if (predictions.isEmpty) return;
    final DateTime at = window.samples.last.at;
    final List<MotionPrediction> maneuvers = <MotionPrediction>[
      for (final MotionPrediction prediction in predictions)
        if (prediction.kind != MotionEventKind.smoothDrive) prediction,
    ];

    if (maneuvers.isEmpty) {
      // Smooth driving is a *state*, not a maneuver: report only the
      // transition into it, or a calm motorway hour would emit an event every
      // cooldown period.
      if (_smoothDriving) return;
      _smoothDriving = true;
      _emit(predictions.first, at);
      return;
    }

    _smoothDriving = false;
    for (final MotionPrediction maneuver in maneuvers) {
      final DateTime? last = _lastEmitted[maneuver.kind];
      if (last != null && at.difference(last) < eventCooldown) continue;
      _lastEmitted[maneuver.kind] = at;
      _emit(maneuver, at);
    }
  }

  void _emit(MotionPrediction prediction, DateTime at) {
    final MotionEvent event = MotionEvent(
      kind: prediction.kind,
      confidence: prediction.confidence,
      peakMps2: prediction.peakMps2,
      startedAt: at,
    );
    _events.add(event);
    final StreamController<MotionEvent>? events = _onEvent;
    if (events != null && !events.isClosed) events.add(event);
  }
}
