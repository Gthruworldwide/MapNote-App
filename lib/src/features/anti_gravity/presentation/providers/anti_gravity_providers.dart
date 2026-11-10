import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motion_smooth/motion_smooth.dart';
import '../../domain/anti_gravity_models.dart';
import '../../domain/anti_gravity_motion_adapter.dart';

/// Available test scenarios for interactive simulation.
enum AntiGravityScenario {
  urbanCircuit('Urban Circuit', 'City driving with stops, turns, and acceleration'),
  highSpeedHighway('High-Speed Highway', 'Rapid acceleration reaching 120+ km/h'),
  hairpinSlalom('Hairpin Slalom', 'Aggressive cornering and lateral G maneuvers'),
  emergencyBrake('Emergency Stop', 'High-speed cruise followed by hard braking');

  final String title;
  final String description;
  const AntiGravityScenario(this.title, this.description);
}

/// Simulation snapshot state held by Riverpod.
class AntiGravitySimulationState {
  final AntiGravityState? currentTelemetry;
  final List<RoutePoint> rawHistory;
  final List<RoutePoint> smoothedHistory;
  final List<RoutePoint> antiGravityHistory;
  final bool isPlaying;
  final double playbackSpeed;
  final AntiGravityScenario scenario;
  final double peakGForce;
  final double totalDistanceM;
  final Map<DrivingEventType, int> maneuverCounts;

  const AntiGravitySimulationState({
    this.currentTelemetry,
    this.rawHistory = const [],
    this.smoothedHistory = const [],
    this.antiGravityHistory = const [],
    this.isPlaying = true,
    this.playbackSpeed = 1.0,
    this.scenario = AntiGravityScenario.urbanCircuit,
    this.peakGForce = 1.0,
    this.totalDistanceM = 0.0,
    this.maneuverCounts = const {},
  });

  AntiGravitySimulationState copyWith({
    AntiGravityState? currentTelemetry,
    List<RoutePoint>? rawHistory,
    List<RoutePoint>? smoothedHistory,
    List<RoutePoint>? antiGravityHistory,
    bool? isPlaying,
    double? playbackSpeed,
    AntiGravityScenario? scenario,
    double? peakGForce,
    double? totalDistanceM,
    Map<DrivingEventType, int>? maneuverCounts,
  }) {
    return AntiGravitySimulationState(
      currentTelemetry: currentTelemetry ?? this.currentTelemetry,
      rawHistory: rawHistory ?? this.rawHistory,
      smoothedHistory: smoothedHistory ?? this.smoothedHistory,
      antiGravityHistory: antiGravityHistory ?? this.antiGravityHistory,
      isPlaying: isPlaying ?? this.isPlaying,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      scenario: scenario ?? this.scenario,
      peakGForce: peakGForce ?? this.peakGForce,
      totalDistanceM: totalDistanceM ?? this.totalDistanceM,
      maneuverCounts: maneuverCounts ?? this.maneuverCounts,
    );
  }
}

/// Controller managing the Anti-Gravity configuration parameters.
class AntiGravityConfigController extends Notifier<AntiGravityConfig> {
  @override
  AntiGravityConfig build() {
    return const AntiGravityConfig();
  }

  void setMass(double massKg) {
    state = state.copyWith(massKg: massKg);
  }

  void setMode(AntiGravityMode mode) {
    state = state.copyWith(mode: mode);
  }

  void setSmoothingAlpha(double alpha) {
    state = state.copyWith(smoothingAlpha: alpha);
  }

  void setLiftGain(double gain) {
    state = state.copyWith(liftGain: gain);
  }

  void setManeuverDamping(double damping) {
    state = state.copyWith(maneuverDamping: damping);
  }
}

/// Provider for Anti-Gravity configuration.
final antiGravityConfigProvider =
    NotifierProvider<AntiGravityConfigController, AntiGravityConfig>(
  AntiGravityConfigController.new,
);

/// Controller managing the simulation loop and real-time state.
class AntiGravitySimulationController
    extends Notifier<AntiGravitySimulationState> {
  late AntiGravityMotionAdapter _adapter;
  Timer? _ticker;
  double _simulationTick = 0.0;
  static const int _maxHistoryLength = 120;

  @override
  AntiGravitySimulationState build() {
    final config = ref.watch(antiGravityConfigProvider);
    _adapter = AntiGravityMotionAdapter(config: config);

    ref.onDispose(() {
      _ticker?.cancel();
    });

    _startSimulationLoop();
    return const AntiGravitySimulationState();
  }

  void togglePlay() {
    if (state.isPlaying) {
      _ticker?.cancel();
      state = state.copyWith(isPlaying: false);
    } else {
      state = state.copyWith(isPlaying: true);
      _startSimulationLoop();
    }
  }

  void setPlaybackSpeed(double speed) {
    state = state.copyWith(playbackSpeed: speed);
    if (state.isPlaying) {
      _ticker?.cancel();
      _startSimulationLoop();
    }
  }

  void setScenario(AntiGravityScenario scenario) {
    _simulationTick = 0.0;
    _adapter.reset();
    state = state.copyWith(
      scenario: scenario,
      rawHistory: [],
      smoothedHistory: [],
      antiGravityHistory: [],
      peakGForce: 1.0,
      totalDistanceM: 0.0,
      maneuverCounts: {},
    );
  }

  void reset() {
    _simulationTick = 0.0;
    _adapter.reset();
    state = state.copyWith(
      rawHistory: [],
      smoothedHistory: [],
      antiGravityHistory: [],
      peakGForce: 1.0,
      totalDistanceM: 0.0,
      maneuverCounts: {},
    );
  }

  void _startSimulationLoop() {
    _ticker?.cancel();
    // ~30 FPS tick
    final intervalMs = (33 / state.playbackSpeed).clamp(10, 100).round();
    _ticker = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _stepSimulation();
    });
  }

  void _stepSimulation() {
    _simulationTick += 0.05 * state.playbackSpeed;
    final now = DateTime.now();

    // Generate scenario trajectory point with realistic noise
    final pointData = _generateScenarioPoint(_simulationTick, state.scenario);
    final rawPoint = RoutePoint(
      latitude: pointData.lat,
      longitude: pointData.lng,
      at: now,
    );

    // Process through AntiGravityMotionAdapter pipeline
    final telemetry = _adapter.processPoint(
      rawPoint,
      overrideSpeedMps: pointData.speedMps,
      overrideHeadingDeg: pointData.headingDeg,
    );

    // Accumulate history
    final newRaw = [...state.rawHistory, rawPoint];
    final newSmoothed = [...state.smoothedHistory, telemetry.smoothedPoint];
    final newAntiG = [...state.antiGravityHistory, telemetry.antiGravityPoint];

    if (newRaw.length > _maxHistoryLength) {
      newRaw.removeRange(0, newRaw.length - _maxHistoryLength);
      newSmoothed.removeRange(0, newSmoothed.length - _maxHistoryLength);
      newAntiG.removeRange(0, newAntiG.length - _maxHistoryLength);
    }

    // Update peak G-force
    final double peakG = math.max(state.peakGForce, telemetry.gForce);

    // Update maneuvers
    final updatedCounts = Map<DrivingEventType, int>.from(state.maneuverCounts);
    for (final m in telemetry.activeManeuvers) {
      updatedCounts[m] = (updatedCounts[m] ?? 0) + 1;
    }

    state = state.copyWith(
      currentTelemetry: telemetry,
      rawHistory: newRaw,
      smoothedHistory: newSmoothed,
      antiGravityHistory: newAntiG,
      peakGForce: peakG,
      totalDistanceM: state.totalDistanceM + (telemetry.velocityMps * 0.05),
      maneuverCounts: updatedCounts,
    );
  }

  _ScenarioPoint _generateScenarioPoint(double t, AntiGravityScenario scenario) {
    const double centerLat = 30.0444; // Reference coordinate
    const double centerLng = 31.2357;

    double lat = centerLat;
    double lng = centerLng;
    double speedMps = 15.0;
    double heading = 0.0;

    // Pseudo-random GPS jitter (+/- 0.00003 deg ~ 3 meters)
    final double jitterLat = math.sin(t * 19.3) * 0.00004;
    final double jitterLng = math.cos(t * 17.7) * 0.00004;

    switch (scenario) {
      case AntiGravityScenario.urbanCircuit:
        const radius = 0.005;
        lat = centerLat + radius * math.sin(t * 0.4);
        lng = centerLng + radius * math.cos(t * 0.4) * 1.2;
        heading = ((t * 0.4 * 180 / math.pi) + 90) % 360;
        speedMps = 12.0 + 8.0 * math.sin(t * 0.8).abs();
        break;

      case AntiGravityScenario.highSpeedHighway:
        lat = centerLat + (t * 0.0003);
        lng = centerLng + (t * 0.0001);
        heading = 25.0;
        speedMps = math.min(38.0, 5.0 + t * 1.5);
        break;

      case AntiGravityScenario.hairpinSlalom:
        lat = centerLat + (t * 0.0002);
        lng = centerLng + 0.002 * math.sin(t * 1.2);
        heading = 45.0 + 40.0 * math.cos(t * 1.2);
        speedMps = 18.0;
        break;

      case AntiGravityScenario.emergencyBrake:
        final cycle = t % 15.0;
        lat = centerLat + (t * 0.0002);
        lng = centerLng;
        heading = 0.0;
        if (cycle < 7.0) {
          speedMps = 28.0;
        } else if (cycle < 10.0) {
          speedMps = math.max(0.0, 28.0 - (cycle - 7.0) * 9.5);
        } else {
          speedMps = 0.0;
        }
        break;
    }

    return _ScenarioPoint(
      lat: lat + jitterLat,
      lng: lng + jitterLng,
      speedMps: speedMps,
      headingDeg: heading,
    );
  }
}

/// Provider for the simulation controller.
final antiGravitySimulationProvider = NotifierProvider<
    AntiGravitySimulationController, AntiGravitySimulationState>(
  AntiGravitySimulationController.new,
);

class _ScenarioPoint {
  final double lat;
  final double lng;
  final double speedMps;
  final double headingDeg;

  const _ScenarioPoint({
    required this.lat,
    required this.lng,
    required this.speedMps,
    required this.headingDeg,
  });
}
