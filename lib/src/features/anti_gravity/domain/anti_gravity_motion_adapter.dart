import 'dart:async';
import 'dart:math' as math;
import 'package:motion_smooth/motion_smooth.dart';
import 'anti_gravity_models.dart';
import 'vector3d.dart';

/// Adapter service that ingests telemetry from AutoMotion (`motion_smooth`),
/// processes the kinematics, applies the Anti-Gravity compensation layer,
/// and computes the net force $\mathbf{F}_{\text{net}} = m \cdot (\mathbf{a}_{\text{motion}} - \mathbf{g}_{\text{anti}})$.
class AntiGravityMotionAdapter {
  AntiGravityConfig _config;
  final MotionBehaviorAnalyzer _behaviorAnalyzer;
  final GeoMath _geoMath = const GeoMath();

  RoutePoint? _lastSmoothedPoint;
  DateTime? _lastTimestamp;
  Vector3D _lastVelocity = Vector3D.zero;
  double _currentHeading = 0.0;
  Vector3D _displacement = Vector3D.zero;

  // Recent detected maneuvers
  final List<DrivingEventType> _recentManeuvers = [];

  AntiGravityMotionAdapter({
    AntiGravityConfig? config,
    MotionBehaviorAnalyzer? behaviorAnalyzer,
  })  : _config = config ?? const AntiGravityConfig(),
        _behaviorAnalyzer = behaviorAnalyzer ??
            MotionBehaviorAnalyzer(
              harshAccelerationThresholdMps2: 3.5,
              harshBrakingThresholdMps2: 4.0,
              harshCorneringThresholdDegPerSec: 35.0,
            );

  AntiGravityConfig get config => _config;

  void updateConfig(AntiGravityConfig newConfig) {
    _config = newConfig;
  }

  void reset() {
    _lastSmoothedPoint = null;
    _lastTimestamp = null;
    _lastVelocity = Vector3D.zero;
    _currentHeading = 0.0;
    _displacement = Vector3D.zero;
    _recentManeuvers.clear();
  }

  /// Processes a single [rawPoint] through the AutoMotion + Anti-Gravity pipeline.
  AntiGravityState processPoint(
    RoutePoint rawPoint, {
    double? overrideSpeedMps,
    double? overrideHeadingDeg,
  }) {
    final now = rawPoint.at ?? DateTime.now();

    // 1. Polyline Smoothing using motion_smooth EMA logic
    final RoutePoint smoothedPoint;
    if (_lastSmoothedPoint == null) {
      smoothedPoint = rawPoint;
    } else {
      final double alpha = _config.smoothingAlpha.clamp(0.05, 1.0);
      final double lat = _lastSmoothedPoint!.latitude +
          (rawPoint.latitude - _lastSmoothedPoint!.latitude) * alpha;
      final double lng = _lastSmoothedPoint!.longitude +
          (rawPoint.longitude - _lastSmoothedPoint!.longitude) * alpha;
      smoothedPoint = RoutePoint(latitude: lat, longitude: lng, at: now);
    }

    // 2. Kinematic calculation (dt, dx, dy, velocity, heading)
    double dt = 1.0;
    if (_lastTimestamp != null) {
      dt = now.difference(_lastTimestamp!).inMicroseconds / 1000000.0;
      if (dt <= 0.0001) dt = 0.05; // Guard against zero/negative delta time
    }

    Vector3D velocity = Vector3D.zero;
    double heading = _currentHeading;

    if (_lastSmoothedPoint != null) {
      // Local tangent plane projection using GeoMath
      final enu = _geoMath.latLngToLocalXY(
        smoothedPoint.latitude,
        smoothedPoint.longitude,
        _lastSmoothedPoint!.latitude,
        _lastSmoothedPoint!.longitude,
      );
      final double dx = enu.first; // Easting (m)
      final double dy = enu.second; // Northing (m)

      final double computedSpeed = math.sqrt(dx * dx + dy * dy) / dt;
      final double speedMps = overrideSpeedMps ?? computedSpeed;

      if (overrideHeadingDeg != null) {
        heading = PolylineSmoother.smoothHeading(
          _currentHeading,
          overrideHeadingDeg,
          0.3,
        );
      } else if (dx.abs() > 0.001 || dy.abs() > 0.001) {
        final double rawBearing = PolylineSmoother.calculateBearing(
          _lastSmoothedPoint!.latitude,
          _lastSmoothedPoint!.longitude,
          smoothedPoint.latitude,
          smoothedPoint.longitude,
        );
        heading = PolylineSmoother.smoothHeading(
          _currentHeading,
          rawBearing,
          0.3,
        );
      }

      final double headingRad = heading * math.pi / 180.0;
      final double vx = speedMps * math.sin(headingRad);
      final double vy = speedMps * math.cos(headingRad);
      velocity = Vector3D(vx, vy, 0.0);
    } else {
      if (overrideSpeedMps != null) {
        velocity = Vector3D(0.0, overrideSpeedMps, 0.0);
      }
    }
    _currentHeading = heading;

    // 3. Acceleration Vector $\mathbf{a}_{\text{motion}}$
    final Vector3D acceleration = (velocity - _lastVelocity) / dt;

    // 4. Maneuver Detection via MotionBehaviorAnalyzer
    final activeManeuvers = _detectManeuvers(velocity.length, acceleration, dt, now);

    // 5. Gravity Compensation Layer
    final antiGravityVector = _computeAntiGravityVector(
      velocity: velocity,
      acceleration: acceleration,
      maneuvers: activeManeuvers,
    );

    // 6. Kinematic Transform: $F_{net} = m \cdot (a_{motion} - g_{anti})$
    final netForce = (acceleration - antiGravityVector) * _config.massKg;

    // Apparent gravity & apparent weight calculation
    // Effective vertical downward gravity perceived: g_eff,z = g_earth - |g_anti,z|
    final double effectiveVerticalG =
        (_config.baseGravityMps2 + antiGravityVector.z).abs();
    final double apparentWeightKg =
        _config.massKg * (effectiveVerticalG / _config.baseGravityMps2);

    final earthGVector = Vector3D(0.0, 0.0, -_config.baseGravityMps2);
    final effectiveG = earthGVector - antiGravityVector;
    final apparentGForce = effectiveG.length / _config.baseGravityMps2;

    // Virtual 3D Displacement (Anti-Gravity levitation/offset)
    final double verticalLiftMps = antiGravityVector.z * 0.15;
    final double newZ = (_displacement.z + verticalLiftMps * dt).clamp(0.0, 50.0);
    _displacement = Vector3D(_displacement.x, _displacement.y, newZ);

    // Project displaced point to geographic coordinates
    final displacedLatLng = _geoMath.localXYToLatLng(
      0.0,
      _displacement.z * 0.05, // Slight visual parallax
      smoothedPoint.latitude,
      smoothedPoint.longitude,
    );
    final antiGravityPoint = RoutePoint(
      latitude: displacedLatLng.first,
      longitude: displacedLatLng.second,
      at: now,
    );

    // Update state cache
    _lastSmoothedPoint = smoothedPoint;
    _lastTimestamp = now;
    _lastVelocity = velocity;

    return AntiGravityState(
      rawPoint: rawPoint,
      smoothedPoint: smoothedPoint,
      antiGravityPoint: antiGravityPoint,
      timestamp: now,
      velocityMps: velocity.length,
      velocityVector: velocity,
      accelerationVector: acceleration,
      antiGravityVector: antiGravityVector,
      netForce: netForce,
      apparentWeightKg: apparentWeightKg,
      gForce: apparentGForce,
      displacementM: _displacement,
      heading: heading,
      activeManeuvers: activeManeuvers,
    );
  }

  /// Transforms an entire stream of [RoutePoint]s into real-time [AntiGravityState]s.
  Stream<AntiGravityState> transformStream(Stream<RoutePoint> rawPoints) {
    return rawPoints.map(processPoint);
  }

  /// Detects active driving maneuvers from speed and lateral/longitudinal acceleration.
  List<DrivingEventType> _detectManeuvers(
    double speedMps,
    Vector3D accel,
    double dt,
    DateTime timestamp,
  ) {
    final List<DrivingEventType> maneuvers = [];

    // Observe speed in motion_smooth analyzer
    _behaviorAnalyzer.observeSpeed(speedMps, timestamp);

    // Longitudinal acceleration/braking check
    if (accel.y > _behaviorAnalyzer.harshAccelerationThresholdMps2) {
      maneuvers.add(DrivingEventType.harshAcceleration);
    } else if (accel.y < -_behaviorAnalyzer.harshBrakingThresholdMps2) {
      maneuvers.add(DrivingEventType.harshBraking);
    }

    // Lateral acceleration check for sharp turn
    if (accel.x.abs() > 3.0) {
      maneuvers.add(DrivingEventType.sharpTurn);
    }

    return maneuvers;
  }

  /// Non-linear Gravity Compensation calculation.
  Vector3D _computeAntiGravityVector({
    required Vector3D velocity,
    required Vector3D acceleration,
    required List<DrivingEventType> maneuvers,
  }) {
    final double g0 = _config.baseGravityMps2;
    double antiGZ = 0.0;
    Vector3D stabilization = Vector3D.zero;

    switch (_config.mode) {
      case AntiGravityMode.earthNormal:
        antiGZ = 0.0;
        break;

      case AntiGravityMode.microGravity:
        // 95% gravity cancellation
        antiGZ = -0.95 * g0;
        break;

      case AntiGravityMode.velocityLift:
        // Non-linear response curve: tanh(v / 18.0) * liftGain
        final double speed = velocity.length;
        final double liftRatio = math.min(1.0, _tanh(speed / 18.0) * _config.liftGain);
        antiGZ = -liftRatio * g0;
        break;

      case AntiGravityMode.hyperLift:
        // Inverted effective gravity (causes upward acceleration)
        antiGZ = -1.30 * g0;
        break;

      case AntiGravityMode.lunar:
        // Moon: effective downward g is 1.62 m/s²
        antiGZ = -(g0 - 1.62);
        break;

      case AntiGravityMode.martian:
        // Mars: effective downward g is 3.72 m/s²
        antiGZ = -(g0 - 3.72);
        break;
    }

    // Dynamic maneuver stabilization (counters abrupt lateral & longitudinal forces)
    if (_config.maneuverDamping > 0.0) {
      stabilization = Vector3D(
        -acceleration.x * _config.maneuverDamping * 0.8,
        -acceleration.y * _config.maneuverDamping * 0.5,
        0.0,
      );
    }

    return Vector3D(stabilization.x, stabilization.y, antiGZ);
  }

  /// Helper to compute hyperbolic tangent tanh(x) in pure Dart.
  double _tanh(double x) {
    if (x > 20.0) return 1.0;
    if (x < -20.0) return -1.0;
    final exp2x = math.exp(2 * x);
    return (exp2x - 1.0) / (exp2x + 1.0);
  }
}
