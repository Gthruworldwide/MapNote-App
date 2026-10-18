import 'dart:async';
import 'dart:math' as math;

import 'motion_sensor_hub.dart';

/// Estimates travelled distance between two instants from evidence that is
/// independent of GPS fixes — the inertial complement to
/// `GapRecoveryService`, which judges a gap geometrically once a fix returns.
///
/// The track engine consults a [DistanceEstimator] for an outage window in
/// two situations: the Haversine crossing was refused as implausible (a bad
/// "first fix back"), or the session ends while the outage is still open and
/// no fix will ever judge it.
abstract class DistanceEstimator {
  /// Inertially estimated displacement, in kilometres, between two instants:
  /// the straight line from where the estimator believed the device was at
  /// [from] to where it believed it was at [to]. Returns `0` when the
  /// estimator has no evidence covering the window — silence is never
  /// invented into distance.
  double displacementKmBetween(DateTime from, DateTime to);
}

/// [DistanceEstimator] that vouches for nothing. Default for the trackers so
/// unit tests and platforms without the sensor bridge keep working.
class NoopDistanceEstimator implements DistanceEstimator {
  const NoopDistanceEstimator();

  @override
  double displacementKmBetween(DateTime from, DateTime to) => 0;
}

/// Inertial dead reckoning over the accelerometer and gyroscope streams, with
/// a simplified 4-state Extended Kalman Filter.
///
/// **State.** `[east m, north m, east m/s, north m/s]` in a local plane whose
/// origin is wherever the filter started (the engine only ever consumes
/// *differences* between two instants, so absolute drift cancels out).
///
/// **Process model.** Constant-velocity propagation driven by the linear
/// acceleration left after gravity removal. Gravity is tracked with a slow
/// per-axis low-pass filter (2 s time constant) exactly like the trackers'
/// `MotionClassifier`; the horizontal residual is rotated into the world
/// frame by the gyroscope-integrated yaw. Process noise follows the standard
/// discrete white-noise-acceleration model, scaled by σa = [accelNoise].
///
/// **Zero-velocity updates (ZUPT).** While the residual stays below
/// [zuptThreshold] for [zuptHold] — the phone is standing still, between
/// steps, or parked — a zero-velocity measurement is fused into the filter.
/// This is what bounds velocity drift for a pedestrian (every step ends in a
/// standstill) and stops a parked phone from accumulating phantom distance.
///
/// **Anchors.** Every [anchorEvery] the filter's position is written to a
/// bounded history (last [maxHistory]); [displacementKmBetween] interpolates
/// that history. A window that starts before all retained evidence returns
/// `0` — the estimator never extrapolates past what it sensed.
///
/// Honest limits: this is a flat-plane, phone-flat approximation — it cannot
/// see elevation, cannot tell the phone's orientation without magnetometer
/// fusion, and drifts over very long GPS-black stretches. It is therefore
/// only ever a *fallback* witness: whenever a plausible Haversine crossing
/// exists, the engine prefers it and this estimator is not consulted.
class DeadReckoningService implements DistanceEstimator {
  DeadReckoningService({
    required this._accelerometer,
    required this._gyroscope,
    this.gravityTau = const Duration(seconds: 2),
    this.anchorEvery = const Duration(seconds: 2),
    this.maxHistory = const Duration(hours: 2),
    this.zuptThreshold = 0.12,
    this.zuptHold = const Duration(milliseconds: 600),
    this.accelNoise = 1.5,
  });

  /// Time constant of the gravity low-pass filter.
  final Duration gravityTau;

  /// Cadence at which the filter's position enters the anchor history.
  final Duration anchorEvery;

  /// How long anchor history is retained; covers the engines' longest
  /// bridgeable gap (2 h) with margin.
  final Duration maxHistory;

  /// Residual RMS (m/s²) below which the device counts as standing still.
  final double zuptThreshold;

  /// How long the residual must stay below [zuptThreshold] before a
  /// zero-velocity update is fused.
  final Duration zuptHold;

  /// 1σ accelerometer noise fed into the process model (m/s²).
  final double accelNoise;

  final Stream<AccelerometerSample> _accelerometer;
  final Stream<GyroscopeSample> _gyroscope;

  // ---- Filter state -------------------------------------------------------
  double _eastM = 0;
  double _northM = 0;
  double _eastMps = 0;
  double _northMps = 0;

  /// Covariance, row-major `[pE, pN, vE, vN] × 4`.
  final List<double> _p = List<double>.filled(16, 0);

  double _gravityX = 0;
  double _gravityY = 0;
  double _gravityZ = 0;
  bool _gravitySeeded = false;

  double _yawRad = 0;
  double _residualRmsEma = 0;
  double _zuptStreakSeconds = 0;
  DateTime? _lastSampleAt;
  DateTime? _lastGyroAt;
  DateTime? _lastAnchorAt;

  final List<_DrAnchor> _anchors = <_DrAnchor>[];

  StreamSubscription<AccelerometerSample>? _accelerometerSubscription;
  StreamSubscription<GyroscopeSample>? _gyroscopeSubscription;

  /// True while the sensor streams are subscribed.
  bool get isRunning => _accelerometerSubscription != null;

  /// Current best estimate of the displacement since the filter started, in
  /// metres east / north of its origin (diagnostics; the engine only reads
  /// [displacementKmBetween]).
  double get estimatedEastM => _eastM;

  /// See [estimatedEastM].
  double get estimatedNorthM => _northM;

  /// Current speed estimate, m/s (diagnostics).
  double get estimatedSpeedMps => math.sqrt(_eastMps * _eastMps + _northMps * _northMps);

  /// Timestamp of the last accelerometer sample processed, or `null`.
  DateTime? get lastUpdateAt => _lastSampleAt;

  /// How many anchors the history currently holds (diagnostics/tests).
  int get anchorCount => _anchors.length;

  /// Subscribes to the sensor streams. Idempotent; never throws — a device
  /// without the channels simply produces no estimates.
  Future<void> start() async {
    if (isRunning) return;
    _resetFilter();
    try {
      _accelerometerSubscription =
          _accelerometer.listen(onAccelerometer, cancelOnError: false);
      _gyroscopeSubscription = _gyroscope.listen(onGyroscope);
    } catch (_) {
      // Stream unavailable: keep inert instead of failing the tracker.
    }
  }

  /// Unsubscribes from both sensors and forgets the filter state, so a later
  /// [start] begins from a clean origin (see AGENT_SKILLS: every sensor
  /// stream must be cancelled on stop/dispose).
  Future<void> stop() async {
    final StreamSubscription<AccelerometerSample>? accelerometerSubscription =
        _accelerometerSubscription;
    final StreamSubscription<GyroscopeSample>? gyroscopeSubscription =
        _gyroscopeSubscription;
    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;
    await accelerometerSubscription?.cancel();
    await gyroscopeSubscription?.cancel();
    _resetFilter();
  }

  @override
  double displacementKmBetween(DateTime from, DateTime to) {
    if (_anchors.isEmpty || to.isBefore(from)) return 0;
    // No evidence covering the window start: refuse to invent a trajectory.
    if (from.isBefore(_anchors.first.at)) return 0;
    final _DrAnchor a = _anchorAt(from);
    final _DrAnchor b = _anchorAt(to);
    final double east = b.eastM - a.eastM;
    final double north = b.northM - a.northM;
    return math.sqrt(east * east + north * north) / 1000;
  }

  /// Integrates the yaw rate into the world heading. Runs on the gyroscope
  /// stream's own cadence.
  void onGyroscope(GyroscopeSample sample) {
    final DateTime? lastGyroAt = _lastGyroAt;
    _lastGyroAt = sample.at;
    if (lastGyroAt == null) return;
    final double dt = sample.at.difference(lastGyroAt).inMicroseconds / 1e6;
    if (dt <= 0 || dt > 1) return; // out-of-order or stalled sensor
    _yawRad += sample.z * dt;
  }

  /// Predicts the state forward with one accelerometer sample and fuses a
  /// zero-velocity update when the device has settled.
  void onAccelerometer(AccelerometerSample sample) {
    final DateTime? lastSampleAt = _lastSampleAt;
    _lastSampleAt = sample.at;
    if (!_gravitySeeded) {
      _gravityX = sample.x;
      _gravityY = sample.y;
      _gravityZ = sample.z;
      _gravitySeeded = true;
    } else {
      final double dtForGravity =
          lastSampleAt == null ? gravityTauSeconds : _secondsSince(lastSampleAt, sample.at);
      final double alpha = dtForGravity / (gravityTauSeconds + dtForGravity);
      _gravityX += (sample.x - _gravityX) * alpha;
      _gravityY += (sample.y - _gravityY) * alpha;
      _gravityZ += (sample.z - _gravityZ) * alpha;
    }

    final double residualX = sample.x - _gravityX;
    final double residualY = sample.y - _gravityY;
    final double residualZ = sample.z - _gravityZ;
    final double residualNorm = math.sqrt(residualX * residualX +
        residualY * residualY +
        residualZ * residualZ);

    if (lastSampleAt != null) {
      final double dt = _secondsSince(lastSampleAt, sample.at);
      if (dt <= 0) return; // out-of-order sample: nothing to integrate
      if (dt <= maxPredictSeconds) {
        // Rotate the horizontal residual into the world frame by the
        // gyroscope-integrated yaw (phone-flat approximation).
        final double cosYaw = math.cos(_yawRad);
        final double sinYaw = math.sin(_yawRad);
        final double accelEast = residualX * cosYaw - residualY * sinYaw;
        final double accelNorth = residualX * sinYaw + residualY * cosYaw;
        _predict(accelEast, accelNorth, dt);
      }
      _trackStillness(residualNorm, dt);
    }
    _writeAnchor(sample.at);
  }

  double get gravityTauSeconds => gravityTau.inMicroseconds / 1e6;

  static const double maxPredictSeconds = 1;

  double _secondsSince(DateTime from, DateTime to) =>
      to.difference(from).inMicroseconds / 1e6;

  /// One EKF predict step with input acceleration (m/s²) over [dt] seconds.
  void _predict(double accelEast, double accelNorth, double dt) {
    _eastM += _eastMps * dt + 0.5 * accelEast * dt * dt;
    _northM += _northMps * dt + 0.5 * accelNorth * dt * dt;
    _eastMps += accelEast * dt;
    _northMps += accelNorth * dt;

    // P = F P Fᵀ + Q with F the constant-velocity model (F[0][2] = F[1][3]
    // = dt, identity elsewhere) and Q the discrete white-noise-acceleration
    // covariance. Written out structurally instead of as a general product.
    final List<double> p = _p;
    final double q = accelNoise * accelNoise;
    final double dt2 = dt * dt;
    final double dt3 = dt2 * dt;
    final List<double> fp = List<double>.filled(16, 0);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        double v = p[i * 4 + j];
        if (i == 0) v += dt * p[2 * 4 + j];
        if (i == 1) v += dt * p[3 * 4 + j];
        fp[i * 4 + j] = v;
      }
    }
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        double v = fp[i * 4 + j];
        if (j == 0) v += dt * fp[i * 4 + 2];
        if (j == 1) v += dt * fp[i * 4 + 3];
        p[i * 4 + j] = v;
      }
    }
    p[0 * 4 + 0] += q * dt3 / 3;
    p[1 * 4 + 1] += q * dt3 / 3;
    p[2 * 4 + 2] += q * dt;
    p[3 * 4 + 3] += q * dt;
    p[0 * 4 + 2] += q * dt2 / 2;
    p[2 * 4 + 0] += q * dt2 / 2;
    p[1 * 4 + 3] += q * dt2 / 2;
    p[3 * 4 + 1] += q * dt2 / 2;
  }

  /// Tracks how long the device has been still and fuses a zero-velocity
  /// measurement once [zuptHold] elapses (repeatedly thereafter — a parked
  /// phone keeps its velocity pinned to zero).
  void _trackStillness(double residualNorm, double dt) {
    final double alpha = dt / (stillnessTauSeconds + dt);
    _residualRmsEma += (residualNorm * residualNorm - _residualRmsEma) * alpha;
    if (math.sqrt(_residualRmsEma) < zuptThreshold) {
      _zuptStreakSeconds += dt;
      if (_zuptStreakSeconds >= zuptHold.inMicroseconds / 1e6) {
        _applyZupt();
      }
    } else {
      _zuptStreakSeconds = 0;
    }
  }

  static const double stillnessTauSeconds = 0.25;

  /// Fuses a zero-velocity measurement on the velocity states. The 2×2
  /// measurement submatrix (velocity block of P plus R) is inverted in closed
  /// form; position states are corrected too through the cross-covariance,
  /// exactly as the full Kalman update prescribes. Gains and the covariance
  /// update are all computed from the *pre-update* P (rows 2 and 3 are
  /// snapshotted first), as the Joseph-form update requires.
  void _applyZupt() {
    final List<double> p = _p;
    final double s11 = p[2 * 4 + 2] + zuptMeasurementNoise;
    final double s12 = p[2 * 4 + 3];
    final double s21 = p[3 * 4 + 2];
    final double s22 = p[3 * 4 + 3] + zuptMeasurementNoise;
    final double det = s11 * s22 - s12 * s21;
    if (!det.isFinite || det.abs() < 1e-9) return;

    final double innovationEast = -_eastMps;
    final double innovationNorth = -_northMps;

    // K = P Hᵀ S⁻¹, one row per state; H picks the two velocity rows.
    final List<double> k = List<double>.filled(8, 0);
    for (int i = 0; i < 4; i++) {
      final double pi2 = p[i * 4 + 2];
      final double pi3 = p[i * 4 + 3];
      k[i * 2 + 0] = (pi2 * s22 - pi3 * s21) / det;
      k[i * 2 + 1] = (-pi2 * s12 + pi3 * s11) / det;
    }

    // x += K·innovation, state by state (row 0 corrects east position,
    // row 1 north position, rows 2/3 the velocities).
    _eastM += k[0] * innovationEast + k[1] * innovationNorth;
    _northM += k[2] * innovationEast + k[3] * innovationNorth;
    _eastMps += k[4] * innovationEast + k[5] * innovationNorth;
    _northMps += k[6] * innovationEast + k[7] * innovationNorth;

    // P = (I − K·H)·P with the original velocity rows 2/3.
    final List<double> row2 = p.sublist(2 * 4, 2 * 4 + 4);
    final List<double> row3 = p.sublist(3 * 4, 3 * 4 + 4);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        p[i * 4 + j] -= k[i * 2] * row2[j] + k[i * 2 + 1] * row3[j];
      }
    }
  }

  static const double zuptMeasurementNoise = 0.02;

  /// Records the filter's position in the bounded anchor history.
  void _writeAnchor(DateTime at) {
    final DateTime? lastAnchorAt = _lastAnchorAt;
    if (lastAnchorAt != null &&
        at.difference(lastAnchorAt) < anchorEvery) {
      return;
    }
    _lastAnchorAt = at;
    _anchors.add(_DrAnchor(at, _eastM, _northM));
    final DateTime cutoff = at.subtract(maxHistory);
    while (_anchors.length > 2 && _anchors.first.at.isBefore(cutoff)) {
      _anchors.removeAt(0);
    }
  }

  /// Interpolates the anchored trajectory at [t]; clamps to the oldest /
  /// newest anchor outside the retained range.
  _DrAnchor _anchorAt(DateTime t) {
    final _DrAnchor first = _anchors.first;
    if (!t.isAfter(first.at)) return first;
    final _DrAnchor last = _anchors.last;
    if (!t.isBefore(last.at)) return last;
    int low = 0;
    int high = _anchors.length - 1;
    while (high - low > 1) {
      final int mid = (low + high) >> 1;
      if (_anchors[mid].at.isBefore(t)) {
        low = mid;
      } else {
        high = mid;
      }
    }
    final _DrAnchor a = _anchors[low];
    final _DrAnchor b = _anchors[high];
    final double span = b.at.difference(a.at).inMicroseconds.toDouble();
    if (span <= 0) return a;
    final double f = t.difference(a.at).inMicroseconds / span;
    return _DrAnchor(
      t,
      a.eastM + (b.eastM - a.eastM) * f,
      a.northM + (b.northM - a.northM) * f,
    );
  }

  /// Forgets every filter artefact; called on [start]/[stop] so each session
  /// begins from a clean origin with a freshly seeded covariance.
  void _resetFilter() {
    _eastM = 0;
    _northM = 0;
    _eastMps = 0;
    _northMps = 0;
    _gravitySeeded = false;
    _gravityX = 0;
    _gravityY = 0;
    _gravityZ = 0;
    _yawRad = 0;
    _residualRmsEma = 0;
    _zuptStreakSeconds = 0;
    _lastSampleAt = null;
    _lastGyroAt = null;
    _lastAnchorAt = null;
    _anchors.clear();
    final List<double> p = _p;
    for (int i = 0; i < 16; i++) {
      p[i] = 0;
    }
    p[0 * 4 + 0] = initialPositionVariance;
    p[1 * 4 + 1] = initialPositionVariance;
    p[2 * 4 + 2] = initialVelocityVariance;
    p[3 * 4 + 3] = initialVelocityVariance;
  }

  /// 1σ uncertainty of the starting position (10 m).
  static const double initialPositionVariance = 100;

  /// 1σ uncertainty of the starting velocity (5 m/s).
  static const double initialVelocityVariance = 25;
}

/// One point of the anchored inertial trajectory.
class _DrAnchor {
  const _DrAnchor(this.at, this.eastM, this.northM);

  final DateTime at;
  final double eastM;
  final double northM;
}
