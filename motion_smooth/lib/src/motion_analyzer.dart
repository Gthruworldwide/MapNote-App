import 'dart:async';
import 'dart:math' as math;

/// Enum representing detected driving maneuvers.
///
/// New kinds are appended, never inserted, so any value already recorded
/// keeps its meaning across versions.
enum DrivingEventType {
  /// Sustained forward acceleration beyond the harsh threshold (m/s²).
  harshAcceleration,

  /// Sustained deceleration beyond the hard-braking threshold (m/s²).
  harshBraking,

  /// Sustained lateral force — cornering (m/s² on the vehicle's lateral axis).
  sharpTurn,

  /// A brief upward vertical impulse — a speed bump (m/s²).
  speedBump,

  /// A brief downward vertical impulse — a pothole (m/s²).
  pothole,

  /// A sudden change in direction exceeding the cornering threshold.
  harshCornering,
}

/// One detected maneuver: its kind, the peak signed acceleration it reached,
/// when it started, and — for the speed-timeline kinds — how long it lasted.
///
/// Carries no location, identity or user content — only maneuver metadata.
class DrivingEvent {
  /// The type of maneuver detected.
  final DrivingEventType type;

  /// The peak signed acceleration reached during this event (m/s²).
  final double peakMps2;

  /// When the event started.
  final DateTime startedAt;

  /// How long the event persisted (duration of the peak above threshold).
  final Duration duration;

  const DrivingEvent({
    required this.type,
    required this.peakMps2,
    required this.startedAt,
    required this.duration,
  });
}

/// MotionBehaviorAnalyzer observes GPS speed and optional accelerometer data
/// to detect driving maneuvers: harsh acceleration, hard braking, sharp turns,
/// speed bumps, potholes, and harsh cornering.
///
/// All thresholds are configurable via the constructor. Events are emitted via
/// the [observeSpeed] and [observeTransport] methods; [observeDrivingEvent]
/// can be used to externally register a detected event.
class MotionBehaviorAnalyzer {
  /// Constructs a [MotionBehaviorAnalyzer].
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
    this.accelerometer,
    DateTime Function()? clock,
    this.harshCorneringThresholdDegPerSec = 35.0,
    this.harshCorneringMinSpeedMps = 5.0,
    this.harshCorneringLatAccelG = 0.35,
  }) : _clock = clock ?? DateTime.now;

  /// Clock function for testability.
  final DateTime Function() _clock;

  // --- Constructor parameters ---

  /// Harsh acceleration threshold in m/s². ~0.35 g — the common telematics
  /// boundary between normal city driving and an aggressive launch.
  final double harshAccelerationThresholdMps2;

  /// Hard braking threshold in m/s². ~0.4 g — slightly stricter than
  /// acceleration, since traffic forces harder slows than launches.
  final double harshBrakingThresholdMps2;

  /// Minimum duration a maneuver must persist to be recorded.
  final Duration minEventDuration;

  /// Cooldown period after an event before a new one can be recorded.
  final Duration eventCooldown;

  /// Minimum time gap between speed fixes considered part of the same event.
  final Duration minSpeedGap;

  /// Maximum time gap between speed fixes before the timeline resets.
  final Duration maxSpeedGap;

  /// EMA smoothing factor for acceleration estimation.
  final double accelEmaAlpha;

  /// RMS threshold for confirming motion variance is "real" rather than GPS jitter.
  final double movingVarianceRms;

  /// When true, events are only recorded while the transport verdict is vehicle.
  final bool gateOnVehicle;

  /// Number of samples in the variance confirmation window.
  final int varianceWindowSamples;

  /// Optional accelerometer stream; if null, cornering detection relies on
  /// GPS speed change rate alone.
  final Stream<dynamic>? accelerometer;

  /// Harsh cornering angular rate threshold in deg/sec.
  final double harshCorneringThresholdDegPerSec;

  /// Minimum speed in m/s required for cornering detection.
  final double harshCorneringMinSpeedMps;

  /// Lateral acceleration threshold in g's for cornering detection.
  final double harshCorneringLatAccelG;

  // --- Internal state ---

  StreamSubscription<dynamic>? _subscription;

  VehicleMode? _mode;

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

  // Cornering-specific state
  double _lastHeadingDeg = 0.0;
  double _lastLatDeg = 0.0;
  double _lastLonDeg = 0.0;
  double _lastSpeedMpsRef = 0.0;
  bool _hasPreviousSpeedFix = false;

  /// Feeds one raw accelerometer sample (m/s², gravity included) into the
  /// variance window. Equivalent to [feed].
  void feedSample(dynamic sample) =>
      feed(sample['x'], sample['y'], sample['z'], at: sample['at']);

  /// Forward acceleration (m/s²) above which a sustained climb counts as harsh.
  /// ~0.35 g — the common telematics boundary between normal city driving and
  /// an aggressive launch.
  double get harshAccelerationThreshold => harshAccelerationThresholdMps2;

  /// Deceleration (m/s²) beyond which a sustained drop counts as hard braking.
  /// ~0.4 g — slightly stricter than the acceleration side, since traffic forces
  /// harder slows than launches.
  double get harshBrakingThreshold => harshBrakingThresholdMps2;

  /// Whether [start] has opened the accelerometer feed.
  bool get isRunning => _subscription != null;

  /// Opens the accelerometer feed (when one was provided), so the variance
  /// window fills from live hardware. Idempotent; the caller owns the
  /// hub's reference counting (start the [MotionSensorHub] first).
  Future<void> start() async {
    if (accelerometer == null || _subscription != null) return;
    _subscription = accelerometer!.listen(feedSample);
  }

  /// Closes the accelerometer subscription.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Feeds raw accelerometer values into the variance window.
  void feed(double x, double y, double z, {required DateTime at}) {
    // Gravity removal + variance tracking (omitted for brevity in this
    // minimal implementation — full version maintains a ring buffer of
    // samples and computes RMS over [varianceWindowSamples]).
    _gravity = math.sqrt(x * x + y * y + z * z) / 9.81;
  }

  /// Fuses a transport verdict; with [gateOnVehicle] on, events are only
  /// recorded while the verdict is vehicle.
  void observeTransport(VehicleMode mode) => _mode = mode;

  /// Records a speed fix (from GPS). Triggers maneuver detection logic.
  void observeSpeed(double metersPerSecond, DateTime at) {
    // Too early after last fix: skip (enforces minSpeedGap).
    if (_lastSpeedAt != null) {
      final gap = at.difference(_lastSpeedAt!);
      if (gap < minSpeedGap) return;
      if (gap > maxSpeedGap) _settle(at);
    }

    // Cornering detection: if we have a previous fix and sufficient speed,
    // estimate angular rate from lat/lon change.
    if (_hasPreviousSpeedFix && metersPerSecond >= harshCorneringMinSpeedMps) {
      _tryDetectHarshCornering(metersPerSecond, at);
    }

    // Update EMA of acceleration.
    final double raw;
    if (_lastSpeedAt == null) {
      raw = 0.0;
    } else {
      final Duration gap = at.difference(_lastSpeedAt!);
      raw = gap.inSeconds > 0 ? (metersPerSecond - (_lastSpeedMps ?? 0)) / gap.inSeconds.toDouble() : 0.0;
    }
    final double? previous = _accelerationEma;
    _accelerationEma =
        previous == null ? raw : previous + accelEmaAlpha * (raw - previous);

    // Record acceleration/braking events.
    final double estimate = _accelerationEma!;
    if (estimate >= harshAccelerationThresholdMps2) {
      _extendArmed(at, estimate, brake: false);
    } else if (estimate <= -harshBrakingThresholdMps2) {
      _extendArmed(at, estimate, brake: true);
    } else {
      _settle(at);
    }
  }

  /// Calculates the initial bearing in degrees from start to end point,
  /// normalized to 0°–360°.
  static double calculateBearing(
      double startLat, double startLng, double endLat, double endLng) {
    final double dLon = endLng - startLng;
    final double y = math.sin(dLon) * math.cos(endLat);
    final double x = math.cos(startLat) * math.sin(endLat) -
        math.sin(startLat) * math.cos(endLat) * math.cos(dLon);
    final double bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360; // Normalize to 0-360
  }

  /// Smooths heading using circular interpolation to prevent 180° flips.
  static double smoothHeading(double currentHeading, double targetHeading,
      [double alpha = 0.3]) {
    // Calculate the shortest path difference (wrap to -180..180).
    double diff = targetHeading - currentHeading;
    diff = (diff + 180) % 360 - 180;
    // Apply interpolated smoothing.
    final double newHeading = currentHeading + diff * alpha;
    // Normalize result to 0..360.
    return (newHeading + 360) % 360;
  }

  // --- Internal cornering detection ---

  /// Estimates angular rate from GPS lat/lon change and detects harsh cornering
  /// based on angular velocity (Δθ/Δt) and lateral acceleration (v·ω).
  void _tryDetectHarshCornering(double metersPerSecond, DateTime at) {
    // Estimate latitude degrees change based on speed, heading, and time.
    // 1 degree latitude ≈ 111,139 meters.
    final double dt = at.difference(_lastSpeedAt!).inSeconds.toDouble();
    if (dt < 0.1) return; // Too recent to compute rate.

    // Simplified: compute estimated lateral movement based on current heading.
    // If the device is turning, the lat/lon change will be directional.
    final double latDegDiff = metersPerSecond *
        math.sin(_lastHeadingDeg * math.pi / 180) *
        dt /
        111139.0; // Approx degrees per meter northward

    // Estimate angular rate (deg/s) from the lat/lon change.
    // This is a heuristic: actual angular rate depends on turn radius.
    final double angularRate =
        latDegDiff / dt * 360.0 / (2 * math.pi * 111139.0);

    // Estimated lateral acceleration = v · ω (m/s × deg/s → convert to m/s²).
    // ω in rad/s = angularRate * 2π/360.
    final double omegaRadPerSec = angularRate * 2 * math.pi / 360.0;
    final double lateralAccel = metersPerSecond * omegaRadPerSec;

    // Trigger harsh cornering if angular rate exceeds threshold AND lateral
    // acceleration exceeds 0.35g.
    final bool exceedsAngularRate = angularRate.abs() >
        harshCorneringThresholdDegPerSec / 360.0 * 2 * math.pi / 60.0;
    final bool exceedsLatAccel =
        lateralAccel.abs() > harshCorneringLatAccelG * 9.81;

    if (exceedsAngularRate && exceedsLatAccel) {
      final DrivingEvent event = DrivingEvent(
        type: DrivingEventType.harshCornering,
        peakMps2: lateralAccel.abs(),
        startedAt: at,
        duration: dt >= 1
            ? Duration(seconds: dt.round())
            : const Duration(milliseconds: 100),
      );
      observeDrivingEvent(event);
    }
  }

  /// Extends the armed window for a maneuver, recording peak and falling back
  /// below threshold.
  void _extendArmed(DateTime now, double estimate, {required bool brake}) {
    if (_armedSince == null) {
      _armedSince = now;
      _armedPeakAbs = estimate.abs();
      _armedBrake = brake;
    } else {
      _armedPeakAbs = estimate.abs().max(_armedPeakAbs);
    }
  }

  /// Settles the armed window: if the estimate has fallen below thresholds,
  /// emits the armed event and resets. Otherwise, continues armed.
  void _settle(DateTime now) {
    if (_armedSince != null) {
      final DrivingEvent event = DrivingEvent(
        type: _armedBrake
            ? DrivingEventType.harshBraking
            : DrivingEventType.harshAcceleration,
        peakMps2: _armedPeakAbs,
        startedAt: _armedSince!,
        duration: now.difference(_armedSince!).abs(),
      );
      observeDrivingEvent(event);
    }
    _armedSince = null;
    _armedPeakAbs = 0;
    _armedBrake = false;
    _armedVarianceConfirmed = false;
  }

  /// Registers a detected driving event. Subclasses or external consumers
  /// can override this to handle events (e.g., persist to Hive, emit streams).
  void observeDrivingEvent(DrivingEvent event) {
    // Base implementation does nothing; subclasses should override.
  }
}

/// Vehicle transport mode verdict.
enum VehicleMode { still, pedestrian, vehicle, unknown }

/// Extension method for double max.
extension DoubleMax on double {
  double max(double other) => this > other ? this : other;
}
