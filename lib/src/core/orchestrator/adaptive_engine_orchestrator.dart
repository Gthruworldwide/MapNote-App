import 'dart:async';

import '../motion/activity_state_manager.dart';

/// The single system-level operating mode, owned by [AdaptiveEngineOrchestrator].
///
/// Everything expensive in the app — the 50 Hz accelerometer feed, the vehicle
/// frame, the background inference isolate, the GPS request interval and the
/// dead-reckoning integrator — is a function of exactly one of these states.
/// Centralising the decision is what makes the whole pipeline predictable: there
/// is one place that answers "what are we doing right now", instead of four
/// subsystems each deciding for themselves whether they are needed.
enum EngineState {
  /// Nothing is happening: no confirmed movement, no active trip. Almost every
  /// subsystem sleeps and the location request is stretched to its longest
  /// interval.
  idleStandby,

  /// A trip is being recorded, on foot or in slow traffic. The location feed is
  /// alive but relaxed, and the expensive motion analytics stay **paused**:
  /// pedestrian gaits can never be classified as maneuvers.
  lowPowerTracking,

  /// Confirmed road vehicle with a trustworthy fix: full analytics. Sensors run
  /// at their highest rate, motion analysis and inference are on, and the GPS
  /// interval tightens so turns and braking are captured sharply.
  activeDriveAnalytics,

  /// The fix has gone — a tunnel, an underpass, a parking garage. The location
  /// feed is kept asking (cheaply) but the position is carried by inertial dead
  /// reckoning instead, so the recorded track does not develop a hole.
  tunnelDeadReckoning,
}

/// What each subsystem should do, as commanded by the orchestrator.
///
/// This is a *description*, not an action: the orchestrator publishes these and
/// the composition root applies them. Keeping it declarative is what lets the
/// whole FSM be unit-tested with no sensor, no GPS, no isolate and no Hive —
/// a test asserts the profile, not the side effects.
class EngineProfile {
  const EngineProfile({
    required this.state,
    required this.motionAnalysisEnabled,
    required this.deadReckoningEnabled,
    required this.locationInterval,
    required this.distanceFilterMeters,
    required this.sensorRateHz,
  });

  /// The state this profile was derived from.
  final EngineState state;

  /// Whether the high-frequency motion pipeline (vehicle frame + classifier +
  /// inference isolate) may consume accelerometer samples at all.
  final bool motionAnalysisEnabled;

  /// Whether inertial dead reckoning should be integrating to fill a GPS gap.
  final bool deadReckoningEnabled;

  /// Minimum interval between location requests in this mode.
  final Duration locationInterval;

  /// Metres the device must move between delivered fixes.
  final int distanceFilterMeters;

  /// Nominal accelerometer analysis rate. Informational: the hardware rate is
  /// fixed by the platform channel, but this documents the rate the pipeline is
  /// expected to operate at in each mode (0 when paused).
  final double sensorRateHz;

  @override
  String toString() => 'EngineProfile(${state.name}, analysis: '
      '$motionAnalysisEnabled, dr: $deadReckoningEnabled, '
      'gps: ${locationInterval.inSeconds}s/${distanceFilterMeters}m)';

  @override
  bool operator ==(Object other) =>
      other is EngineProfile &&
      other.state == state &&
      other.motionAnalysisEnabled == motionAnalysisEnabled &&
      other.deadReckoningEnabled == deadReckoningEnabled &&
      other.locationInterval == locationInterval &&
      other.distanceFilterMeters == distanceFilterMeters &&
      other.sensorRateHz == sensorRateHz;

  @override
  int get hashCode => Object.hash(
        state,
        motionAnalysisEnabled,
        deadReckoningEnabled,
        locationInterval,
        distanceFilterMeters,
        sensorRateHz,
      );
}

/// Evidence the orchestrator reacts to, in the order it is usually learned.
///
/// Every field is optional because the sources are asynchronous and may never
/// arrive at all (no GPS permission, no accelerometer, a stationary phone).
/// "Unknown" is a real value here, and the FSM is written to stay in the safe
/// state when a signal is missing rather than guessing.
class EngineEvidence {
  const EngineEvidence({
    this.activityState,
    this.speedMps,
    this.speedFresh = false,
    this.trackingActive = false,
    this.fixAge,
    this.tunnelSuspect = false,
  });

  /// Verdict of the activity gate, which already rejects pedestrian gaits.
  /// `null` means the gate has not reported yet — treated as *not* driving.
  final ActivityState? activityState;

  /// Latest Doppler speed in m/s, or `null` when never observed.
  final double? speedMps;

  /// Whether the speed reading is recent enough to steer a decision.
  final bool speedFresh;

  /// Whether a trip is being recorded at all.
  final bool trackingActive;

  /// How long since the last location fix, or `null` when none has arrived.
  /// Large values are the tunnel signal.
  final Duration? fixAge;

  /// Explicit "we are probably underground" hint (the fix is stale *and* the
  /// device is still moving), used to prefer dead reckoning over a flat gap.
  final bool tunnelSuspect;

  EngineEvidence copyWith({
    ActivityState? activityState,
    double? speedMps,
    bool? speedFresh,
    bool? trackingActive,
    Duration? fixAge,
    bool? tunnelSuspect,
  }) =>
      EngineEvidence(
        activityState: activityState ?? this.activityState,
        speedMps: speedMps ?? this.speedMps,
        speedFresh: speedFresh ?? this.speedFresh,
        trackingActive: trackingActive ?? this.trackingActive,
        fixAge: fixAge ?? this.fixAge,
        tunnelSuspect: tunnelSuspect ?? this.tunnelSuspect,
      );
}

/// Central finite state machine coordinating every adaptive subsystem.
///
/// It is deliberately **pure and synchronous**: [observe] takes evidence and
/// returns the new [EngineProfile], so the whole decision surface is testable
/// with no sensor, no timer and no isolate. Time enters only through the values
/// carried in the evidence (`fixAge`), never through a wall clock read here —
/// which is also what keeps the FSM honest under injected/replayed timelines.
///
/// The FSM transitions:
///
/// ```
///   idleStandby ──tracking──────────────► lowPowerTracking
///        ▲                                     │  ▲
///        │  no tracking + still                │  │  vehicle lost / pedestrians
///        │                                     ▼  │
///        └──────────────────────────── activeDriveAnalytics
///                                                  │  fix stale & still moving
///                                                  ▼
///                                          tunnelDeadReckoning
/// ```
///
/// Entering `activeDriveAnalytics` requires the activity gate's own
/// `vehicleDriving` verdict, so the orchestrator inherits the gate's
/// anti-false-positive work (speed + held vibration + step rejection) rather
/// than re-deriving it.
class AdaptiveEngineOrchestrator {
  AdaptiveEngineOrchestrator({
    this.speedThresholdKmh = 15,
    this.tunnelFixAge = const Duration(seconds: 8),
    this.idleLocationInterval = const Duration(seconds: 10),
    this.trackingLocationInterval = const Duration(seconds: 10),
    this.drivingLocationInterval = const Duration(seconds: 1),
    this.tunnelLocationInterval = const Duration(seconds: 5),
    this.idleDistanceFilterMeters = 50,
    this.trackingDistanceFilterMeters = 25,
    this.drivingDistanceFilterMeters = 10,
    this.tunnelDistanceFilterMeters = 30,
  })  : assert(speedThresholdKmh >= 0),
        assert(idleLocationInterval > Duration.zero),
        assert(trackingLocationInterval > Duration.zero),
        assert(drivingLocationInterval > Duration.zero),
        assert(tunnelLocationInterval > Duration.zero);

  /// Speed (km/h) at or above which the orchestrator will *consider* driving —
  /// the gate still has the final say.
  final double speedThresholdKmh;

  /// How stale the last fix must be, while the device is still moving, before
  /// the orchestrator assumes a tunnel and switches to dead reckoning.
  final Duration tunnelFixAge;

  final Duration idleLocationInterval;
  final Duration trackingLocationInterval;
  final Duration drivingLocationInterval;
  final Duration tunnelLocationInterval;

  final int idleDistanceFilterMeters;
  final int trackingDistanceFilterMeters;
  final int drivingDistanceFilterMeters;
  final int tunnelDistanceFilterMeters;

  final StreamController<EngineProfile> _profiles =
      StreamController<EngineProfile>.broadcast();

  EngineState _state = EngineState.idleStandby;
  EngineEvidence _evidence = const EngineEvidence();
  int _transitions = 0;

  /// Current state. [EngineState.idleStandby] until evidence says otherwise:
  /// nothing expensive runs unless something proves it should.
  EngineState get state => _state;

  /// Emits the new profile on every state change (broadcast; buffers nothing).
  Stream<EngineProfile> get profiles => _profiles.stream;

  /// How many state changes have happened (diagnostics).
  int get transitionCount => _transitions;

  /// The last evidence observed.
  EngineEvidence get evidence => _evidence;

  /// The profile the current state commands.
  EngineProfile get profile => _profileFor(_state);

  /// Ingests evidence and returns the resulting profile.
  ///
  /// Idempotent for unchanged evidence: feeding the same situation twice does
  /// not re-emit on [profiles] and does not count as a transition.
  EngineProfile observe(EngineEvidence evidence) {
    _evidence = evidence;
    final EngineState next = _resolve(evidence);
    if (next != _state) {
      _state = next;
      _transitions += 1;
      final EngineProfile profile = _profileFor(next);
      if (!_profiles.isClosed) _profiles.add(profile);
      return profile;
    }
    return _profileFor(next);
  }

  /// Forces the machine back to [EngineState.idleStandby] and forgets the
  /// evidence — the trip ended, the user switched the feature off, or the app
  /// is shutting the stack down. Everything expensive stops *now*.
  void suspend() {
    _evidence = const EngineEvidence();
    _force(EngineState.idleStandby);
  }

  /// Releases the profile stream. The orchestrator is unusable afterwards.
  Future<void> dispose() async => _profiles.close();

  /// The transition function. Deliberately exhaustive and total: every input
  /// combination yields a state, and ambiguity resolves toward the *cheapest*
  /// defensible mode rather than leaving a pipeline running on a guess.
  EngineState _resolve(EngineEvidence evidence) {
    if (!evidence.trackingActive) return EngineState.idleStandby;

    final bool moving = _isMoving(evidence);

    // A tunnel is only meaningful if we are actually moving; a parked car in a
    // garage is idle tracking, not dead reckoning.
    if (moving && evidence.tunnelSuspect) {
      final Duration? age = evidence.fixAge;
      if (age == null || age >= tunnelFixAge) {
        return EngineState.tunnelDeadReckoning;
      }
    }

    final bool driving = evidence.activityState == ActivityState.vehicleDriving;

    if (driving) {
      // In the vehicle state the only demotion is a dead fix *with* movement —
      // handled above. Otherwise analytics stay on: a red light is not a reason
      // to stop analysing braking.
      return EngineState.activeDriveAnalytics;
    }

    // Tracking, but not confirmed driving, and not in a tunnel: relaxed mode.
    return EngineState.lowPowerTracking;
  }

  /// Whether the device appears to be in motion. Uses fresh speed when there is
  /// one, and otherwise falls back to the activity verdict, so a lost GPS feed
  /// does not silently demote a confirmed drive.
  bool _isMoving(EngineEvidence evidence) {
    if (evidence.activityState == ActivityState.vehicleDriving) return true;
    if (evidence.speedFresh && evidence.speedMps != null) {
      return evidence.speedMps! * 3.6 >= speedThresholdKmh;
    }
    return evidence.activityState == ActivityState.transitioning;
  }

  EngineProfile _profileFor(EngineState state) {
    switch (state) {
      case EngineState.idleStandby:
        return EngineProfile(
          state: state,
          motionAnalysisEnabled: false,
          deadReckoningEnabled: false,
          locationInterval: idleLocationInterval,
          distanceFilterMeters: idleDistanceFilterMeters,
          sensorRateHz: 0,
        );
      case EngineState.lowPowerTracking:
        return EngineProfile(
          state: state,
          motionAnalysisEnabled: false,
          deadReckoningEnabled: false,
          locationInterval: trackingLocationInterval,
          distanceFilterMeters: trackingDistanceFilterMeters,
          sensorRateHz: 0,
        );
      case EngineState.activeDriveAnalytics:
        return EngineProfile(
          state: state,
          motionAnalysisEnabled: true,
          deadReckoningEnabled: true,
          locationInterval: drivingLocationInterval,
          distanceFilterMeters: drivingDistanceFilterMeters,
          sensorRateHz: 50,
        );
      case EngineState.tunnelDeadReckoning:
        return EngineProfile(
          state: state,
          motionAnalysisEnabled: true,
          deadReckoningEnabled: true,
          locationInterval: tunnelLocationInterval,
          distanceFilterMeters: tunnelDistanceFilterMeters,
          sensorRateHz: 50,
        );
    }
  }

  void _force(EngineState state) {
    if (state == _state) return;
    _state = state;
    _transitions += 1;
    final EngineProfile profile = _profileFor(state);
    if (!_profiles.isClosed) _profiles.add(profile);
  }
}
