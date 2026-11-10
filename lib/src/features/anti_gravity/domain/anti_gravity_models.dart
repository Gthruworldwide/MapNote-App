import 'package:motion_smooth/motion_smooth.dart';
import 'vector3d.dart';

/// Available simulation modes for the Anti-Gravity environment.
enum AntiGravityMode {
  /// Standard 1.0G Earth baseline (no anti-gravity compensation).
  earthNormal,

  /// Near weightlessness (95% gravity cancellation).
  microGravity,

  /// Velocity-dependent dynamic lift: higher speed produces greater upward lift.
  velocityLift,

  /// Full levitation / hyper-lift with negative effective gravity.
  hyperLift,

  /// Lunar simulation (1.62 m/s² effective downward gravity).
  lunar,

  /// Martian simulation (3.72 m/s² effective downward gravity).
  martian;

  String get displayName {
    switch (this) {
      case AntiGravityMode.earthNormal:
        return 'Earth 1.0G';
      case AntiGravityMode.microGravity:
        return 'Micro-Gravity (0.05G)';
      case AntiGravityMode.velocityLift:
        return 'Velocity Lift';
      case AntiGravityMode.hyperLift:
        return 'Hyper-Lift (-0.3G)';
      case AntiGravityMode.lunar:
        return 'Lunar (0.16G)';
      case AntiGravityMode.martian:
        return 'Martian (0.38G)';
    }
  }
}

/// Configuration parameters for the Anti-Gravity engine.
class AntiGravityConfig {
  /// Mass of the vehicle/object in kilograms ($m$). Default 1200.0 kg.
  final double massKg;

  /// Baseline Earth gravity in m/s². Default 9.80665 m/s².
  final double baseGravityMps2;

  /// Active simulation mode.
  final AntiGravityMode mode;

  /// Polyline smoothing factor for `motion_smooth` (0.0 < alpha <= 1.0).
  final double smoothingAlpha;

  /// Non-linear lift sensitivity multiplier.
  final double liftGain;

  /// Inertial damping coefficient applied to maneuvers (0.0 to 1.0).
  final double maneuverDamping;

  const AntiGravityConfig({
    this.massKg = 1200.0,
    this.baseGravityMps2 = 9.80665,
    this.mode = AntiGravityMode.velocityLift,
    this.smoothingAlpha = 0.3,
    this.liftGain = 1.0,
    this.maneuverDamping = 0.5,
  });

  AntiGravityConfig copyWith({
    double? massKg,
    double? baseGravityMps2,
    AntiGravityMode? mode,
    double? smoothingAlpha,
    double? liftGain,
    double? maneuverDamping,
  }) {
    return AntiGravityConfig(
      massKg: massKg ?? this.massKg,
      baseGravityMps2: baseGravityMps2 ?? this.baseGravityMps2,
      mode: mode ?? this.mode,
      smoothingAlpha: smoothingAlpha ?? this.smoothingAlpha,
      liftGain: liftGain ?? this.liftGain,
      maneuverDamping: maneuverDamping ?? this.maneuverDamping,
    );
  }
}

/// Snapshot of kinematic and anti-gravity parameters for a single telemetry tick.
class AntiGravityState {
  /// The raw GPS/coordinate point before smoothing.
  final RoutePoint rawPoint;

  /// The filtered point after `motion_smooth` polyline smoothing.
  final RoutePoint smoothedPoint;

  /// Virtual 3D coordinate point after anti-gravity displacement.
  final RoutePoint antiGravityPoint;

  /// Exact timestamp of this telemetry tick.
  final DateTime timestamp;

  /// Scalar forward velocity in m/s.
  final double velocityMps;

  /// Velocity vector in 3D local tangent plane (m/s).
  final Vector3D velocityVector;

  /// Motion acceleration vector $\mathbf{a}_{\text{motion}}$ (m/s²).
  final Vector3D accelerationVector;

  /// Anti-gravity compensation vector $\mathbf{g}_{\text{anti}}$ (m/s²).
  final Vector3D antiGravityVector;

  /// Net force vector: $\mathbf{F}_{\text{net}} = m \cdot (\mathbf{a}_{\text{motion}} - \mathbf{g}_{\text{anti}})$.
  final Vector3D netForce;

  /// Apparent weight of the vehicle in kilograms: $W = m \cdot \frac{|\mathbf{g}_{\text{earth}} - \mathbf{g}_{\text{anti}}|}{g_0}$.
  final double apparentWeightKg;

  /// Apparent G-Force experienced by occupants (scalar Gs).
  final double gForce;

  /// Dynamic 3D displacement offset (meters) relative to ground track.
  final Vector3D displacementM;

  /// Compass heading in degrees [0, 360).
  final double heading;

  /// Maneuvers active during this frame (e.g. harsh braking, sharp turn).
  final List<DrivingEventType> activeManeuvers;

  const AntiGravityState({
    required this.rawPoint,
    required this.smoothedPoint,
    required this.antiGravityPoint,
    required this.timestamp,
    required this.velocityMps,
    required this.velocityVector,
    required this.accelerationVector,
    required this.antiGravityVector,
    required this.netForce,
    required this.apparentWeightKg,
    required this.gForce,
    required this.displacementM,
    required this.heading,
    required this.activeManeuvers,
  });

  /// Speed in km/h.
  double get speedKmh => velocityMps * 3.6;

  /// Net force magnitude in Kilonewtons (kN).
  double get netForceKn => netForce.length / 1000.0;

  /// Percentage of normal weight retained (100% = normal, 0% = weightless).
  double get weightRatio =>
      apparentWeightKg > 0 ? (apparentWeightKg / 1200.0) * 100.0 : 0.0;
}
