import 'dart:async';
import 'dart:math' as math;

import 'motion_sensor_hub.dart';
import 'transport_classifier.dart';

/// What a detected driving maneuver was.
enum DrivingEventType {
  /// Sustained forward acceleration beyond the harsh threshold (m/s²).
  harshAcceleration,

  /// Sustained deceleration beyond the hard-braking threshold (m/s²).
  harshBraking,
}

/// One detected harsh maneuver: its kind, the peak signed acceleration it
/// reached, when the threshold was first crossed, and how long it lasted.
///
/// Carries no location, identity or user content — just magnitudes and
/// timestamps — so it can never leak where or who drove.
class DrivingEvent {
  const DrivingEvent({
    required this.type,
    required this.peakMps2,
    required this.startedAt,
    required this.duration,
  });

  /// Which maneuver this is.
  final DrivingEventType type;

  /// Peak signed acceleration (m/s²): positive while accelerating, negative
  /// while braking (always beyond its threshold in magnitude).
  final double peakMps2;

  /// When the acceleration first crossed the threshold.
  final DateTime startedAt;

  /// How long the estimate stayed beyond the threshold.
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is DrivingEvent &&
      other.type == type &&
      other.peakMps2 == peakMps2 &&
      other.startedAt == startedAt &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(type, peakMps2, startedAt, duration);

  @override
  String toString() =>
      'DrivingEvent($type, ${peakMps2.toStringAsFixed(1)} m/s², '
      '${duration.inMilliseconds} ms)';
}

/// Driving-behavior profiler: watches the accelerometer's residual variance
/// and the GPS speed timeline during a trip and emits [DrivingEvent]s for
/// harsh acceleration and hard braking.
///
/// The two sensor feeds play different, complementary roles:
///
/// * **Signed acceleration comes from the speed timeline** (`observeSpeed`).
///   A raw accelerometer cannot distinguish accelerating from braking —
///   both read as a tilted gravity vector plus vibration, and the phone's
///   orientation is unknown. The rate of change of GPS (Doppler) speed,
///   however, *is* the longitudinal acceleration, already signed: climbing
///   above [harshAccelerationThresholdMps2] is a harsh launch, dropping
///   below `-`[harshBrakingThresholdMps2] is a hard brake. Consecutive speed
///   deltas are fed through a small EMA ([accelEmaAlpha]) to reject Doppler
///   jitter before thresholds are compared.
/// * **The accelerometer's residual variance confirms the dynamics**
///   (`feed`/`feedSample`). The same gravity-removed window RMS that
///   `TransportClassifier` uses to mean "still or moving" gates every event:
///   a speed delta that appears while the accelerometer is quiet (fix
///   noise, a Doppler artefact near standstill) is not a maneuver, so it is
///   never reported. While armed, the variance confirmation latches — a real
///   maneuver whose vibration window happens to close early is not dropped.
///
/// Events are additionally gated to **vehicle** trips by default
/// ([gateOnVehicle]): callers stream `TransportMode` verdicts in through
/// `observeTransport` (the same feed `AutoMotionController` already
/// distributes), and no event is recorded while the classifier believes the
/// user is walking, on a train or still.
///
/// Pure Dart, deterministic under injected timestamps, and fully offline —
/// nothing here persists or transmits anything.
class MotionBehaviorAnalyzer {
  MotionBehaviorAnalyzer({
    this.harshAccelerationThresholdMps2 = 3.5,
    this.harshBrakingThresholdMps2 = 4.0,
    this.minEventDuration = const Duration(seconds: 1),
    this.eventCooldown = const Duration(seconds: 10),
    this.minSpeedGap = const Duration(milliseconds: 300),
    this.maxSpeedGap = const Duration(seconds: 10),
    this.accelEmaAlpha = 0.5,
    this.movingVarianceRms = 0.28,
    this.gateOnVehicle = true,
    this.varianceWindowSamples = 32,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Forward acceleration (m/s²) above which a sustained climb counts as
  /// harsh. ~0.35 g — the common telematics boundary between normal
  /// city driving and an aggressive launch.
  final double harshAccelerationThresholdMps2;

  /// Deceleration (m/s²) beyond which a sustained drop counts as hard
  /// braking. ~0.4 g — slightly stricter than the acceleration side, since
  /// traffic forces harder slows than launches.
  final double harshBrakingThresholdMps2;

  /// How long the estimate must stay beyond a threshold before the maneuver
  /// counts. Filters single-sample speed artefacts that no physical vehicle
  /// could produce.
  final Duration minEventDuration;

  /// Back-to-back maneuvers closer together than this are reported as one —
  /// an avoidance swerve (brake, coast, brake) is one event to a driver.
  final Duration eventCooldown;

  /// Speed deltas closer together than this are skipped: differencing
  /// Doppler speeds over a few hundred milliseconds amplifies noise instead
  /// of measuring acceleration.
  final Duration minSpeedGap;

  /// Speed deltas further apart than this re-seed the timeline instead of
  /// differentiating: whatever happened across a ten-second hole cannot be
  /// attributed to one acceleration.
  final Duration maxSpeedGap;

  /// EMA weight of the newest speed delta in [instantAccelerationMps2].
  final double accelEmaAlpha;

  /// Residual RMS (m/s²) at or above which the accelerometer confirms real
  /// dynamics — the same "moving" floor `TransportClassifier` uses, so the
  /// two components agree on still-vs-moving.
  final double movingVarianceRms;

  /// Whether events are only recorded while the classifier reports
  /// [TransportMode.vehicle] (see `observeTransport`).
  final bool gateOnVehicle;

  /// How many accelerometer samples the variance window keeps.
  final int varianceWindowSamples;

  final DateTime Function() _clock;

  /// Detected maneuvers, in detection order.
  List<DrivingEvent> get events => List<DrivingEvent>.unmodifiable(_events);

  /// Emits every event as it is detected (broadcast; buffers nothing).
  Stream<DrivingEvent> get onEvent => _onEvent.stream;

  /// Residual RMS of the latest accelerometer window (m/s²), or `null` until
  /// enough samples have arrived.
  double? get lastVarianceRms =>
      _residuals.isEmpty ? null : TransportClassifier.rmsOf(_residuals);

  /// Current EMA of signed acceleration (m/s²): positive accelerating,
  /// negative braking. `null` until at least two speed readings exist.
  double? get instantAccelerationMps2 => _accelerationEma;

  /// Latest transport verdict from `observeTransport` (`null` = unseen).
  TransportMode? get mode => _mode;

  /// Whether the current context permits events (vehicle, or any context when
  /// [gateOnVehicle] is off).
  bool get isVehicleContext => !gateOnVehicle || _mode == TransportMode.vehicle;

  final List<DrivingEvent> _events = <DrivingEvent>[];
  final StreamController<DrivingEvent> _onEvent =
      StreamController<DrivingEvent>.broadcast();

  final List<double> _residuals = <double>[];

  TransportMode? _mode;
  double? _lastSpeedMps;
  DateTime? _lastSpeedAt;
  double? _accelerationEma;
  double _gravity = 0;
  bool _gravitySeeded = false;

  // Armed-maneuver bookkeeping: the window between crossing a threshold and
  // falling back below it.
  DateTime? _armedSince;
  double _armedPeakAbs = 0;
  bool _armedBrake = false;
  bool _armedVarianceConfirmed = false;
  DateTime? _lastEventAt;

  /// Feeds one raw accelerometer sample (m/s², gravity included) into the
  /// variance window. Equivalent to [feed].
  void feedSample(AccelerometerSample sample) =>
      feed(sample.x, sample.y, sample.z, at: sample.at);

  /// Feeds one raw accelerometer sample. Gravity is removed with the same
  /// seeded EMA the transport classifier uses, so both components interpret
  /// "residual" identically.
  void feed(double x, double y, double z, {DateTime? at}) {
    final double magnitude = math.sqrt(x * x + y * y + z * z);
    if (!_gravitySeeded) {
      _gravity = magnitude;
      _gravitySeeded = true;
    }
    final double residual = magnitude - _gravity;
    _gravity += (magnitude - _gravity) * TransportClassifier.gravityAdaptation;
    _residuals.add(residual);
    if (_residuals.length > varianceWindowSamples) {
      _residuals.removeAt(0);
    }
  }

  /// Fuses one GPS speed reading (m/s) — the signed-acceleration timeline.
  /// Negative or non-finite readings are ignored.
  void observeSpeed(double metersPerSecond, {DateTime? at}) {
    if (!metersPerSecond.isFinite || metersPerSecond < 0) return;
    final DateTime now = at ?? _clock();
    final DateTime? lastAt = _lastSpeedAt;
    final double? lastMps = _lastSpeedMps;
    if (lastAt == null || lastMps == null) {
      _lastSpeedAt = now;
      _lastSpeedMps = metersPerSecond;
      return;
    }
    final double dtSeconds =
        now.difference(lastAt).inMicroseconds / Duration.microsecondsPerSecond;
    if (dtSeconds < minSpeedGap.inMicroseconds / Duration.microsecondsPerSecond) {
      // Too close to difference reliably: keep the previous anchor so the
      // next usable pair spans a meaningful interval.
      return;
    }
    _lastSpeedAt = now;
    _lastSpeedMps = metersPerSecond;
    if (dtSeconds > maxSpeedGap.inMicroseconds / Duration.microsecondsPerSecond) {
      // Too far apart: whatever happened in the hole cannot be attributed to
      // one maneuver. Settle any armed window and restart the timeline.
      _settle(now);
      _accelerationEma = null;
      return;
    }

    final double raw = (metersPerSecond - lastMps) / dtSeconds;
    final double? previous = _accelerationEma;
    _accelerationEma = previous == null
        ? raw
        : previous + accelEmaAlpha * (raw - previous);

    final double estimate = _accelerationEma!;
    if (estimate >= harshAccelerationThresholdMps2) {
      _extendArmed(now, estimate, brake: false);
    } else if (estimate <= -harshBrakingThresholdMps2) {
      _extendArmed(now, estimate, brake: true);
    } else {
      _settle(now);
    }
  }

  /// Feeds a transport verdict; with [gateOnVehicle] on, events are only
  /// recorded while the verdict is [TransportMode.vehicle].
  void observeTransport(TransportMode mode) => _mode = mode;

  /// Ends the current trip's profiling state: armed windows are discarded
  /// and the detected-event history cleared. The accelerometer window and
  /// gravity estimate reset too, so a later trip starts from clean evidence.
  void reset() {
    _events.clear();
    _residuals.clear();
    _lastSpeedMps = null;
    _lastSpeedAt = null;
    _accelerationEma = null;
    _gravity = 0;
    _gravitySeeded = false;
    _armedSince = null;
    _armedPeakAbs = 0;
    _armedBrake = false;
    _armedVarianceConfirmed = false;
    _lastEventAt = null;
  }

  /// Starts, extends or direction-flips the armed window.
  void _extendArmed(DateTime now, double estimate, {required bool brake}) {
    if (_armedSince == null) {
      _armedSince = now;
      _armedPeakAbs = estimate.abs();
      _armedBrake = brake;
      _armedVarianceConfirmed = _varianceConfirmsDynamics();
      return;
    }
    if (brake != _armedBrake) {
      // Direction flipped (brake → launch or back): the first maneuver ends
      // here and the new one starts, subject to the cooldown on emission.
      _settle(now);
      _extendArmed(now, estimate, brake: brake);
      return;
    }
    if (estimate.abs() > _armedPeakAbs) _armedPeakAbs = estimate.abs();
    // Latch: real maneuvers keep their vibration evidence even if the
    // variance window drifts quiet before the speed estimate recovers.
    _armedVarianceConfirmed =
        _armedVarianceConfirmed || _varianceConfirmsDynamics();
  }

  /// Closes an armed window (speed estimate fell below threshold, the trip
  /// reset, or a timing hole opened) and emits it when it qualifies.
  void _settle(DateTime now) {
    final DateTime? since = _armedSince;
    if (since == null) return;
    _armedSince = null;
    final double peakAbs = _armedPeakAbs;
    final bool brake = _armedBrake;
    final bool varianceConfirmed = _armedVarianceConfirmed;
    _armedPeakAbs = 0;
    _armedVarianceConfirmed = false;

    final Duration duration = now.difference(since);
    if (duration < minEventDuration) return;
    if (!varianceConfirmed) return;
    if (!isVehicleContext) return;
    final DateTime? lastEventAt = _lastEventAt;
    if (lastEventAt != null && now.difference(lastEventAt) < eventCooldown) {
      return;
    }
    final DrivingEvent event = DrivingEvent(
      type: brake ? DrivingEventType.harshBraking : DrivingEventType.harshAcceleration,
      peakMps2: brake ? -peakAbs : peakAbs,
      startedAt: since,
      duration: duration,
    );
    _lastEventAt = now;
    _events.add(event);
    if (!_onEvent.isClosed) _onEvent.add(event);
  }

  bool _varianceConfirmsDynamics() =>
      (lastVarianceRms ?? 0) >= movingVarianceRms;
}
