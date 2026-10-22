import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:routenote/src/core/motion/activity_state_manager.dart';
import 'package:routenote/src/core/orchestrator/adaptive_engine_orchestrator.dart';

void main() {
  group('cold start', () {
    test('starts idle with everything expensive switched off', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      expect(orchestrator.state, EngineState.idleStandby);
      expect(orchestrator.transitionCount, 0);
      expect(orchestrator.profile.motionAnalysisEnabled, isFalse);
      expect(orchestrator.profile.deadReckoningEnabled, isFalse);
    });

    test('evidence with no tracking stays idle', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observe(const EngineEvidence(trackingActive: false));

      expect(orchestrator.state, EngineState.idleStandby);
      expect(orchestrator.transitionCount, 0);
    });
  });

  group('tracking without a vehicle', () {
    test('starts low-power tracking with analysis paused', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      final EngineProfile profile = orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.stationaryOrWalking,
          speedMps: 0,
          speedFresh: true,
        ),
      );

      expect(profile.state, EngineState.lowPowerTracking);
      // The whole point: walking/still never pays for the analytics pipeline.
      expect(profile.motionAnalysisEnabled, isFalse);
      expect(profile.sensorRateHz, 0);
      expect(profile.deadReckoningEnabled, isFalse);
    });

    test('walking with a fresh slow speed is still low-power', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.stationaryOrWalking,
          speedMps: 1.2, // 4.3 km/h — a walk
          speedFresh: true,
        ),
      );

      expect(orchestrator.state, EngineState.lowPowerTracking);
    });

    test('a transitioning gate verdict is still low-power, not analytics', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.transitioning,
        ),
      );

      expect(orchestrator.state, EngineState.lowPowerTracking);
      expect(orchestrator.profile.motionAnalysisEnabled, isFalse);
    });

    test('a null activity verdict (gate has not reported) is not driving', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observe(const EngineEvidence(trackingActive: true));

      expect(orchestrator.state, EngineState.lowPowerTracking);
    });
  });

  group('confirmed driving', () {
    test('the gate verdict alone opens full analytics', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      final EngineProfile profile = orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
        ),
      );

      expect(profile.state, EngineState.activeDriveAnalytics);
      expect(profile.motionAnalysisEnabled, isTrue);
      expect(profile.deadReckoningEnabled, isTrue);
      expect(profile.sensorRateHz, 50);
      expect(profile.locationInterval, const Duration(seconds: 1));
    });

    test('a red light (speed 0, still a vehicle) keeps analytics on', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
        ),
      );
      final EngineProfile stopped = orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
          speedMps: 0,
          speedFresh: true,
        ),
      );

      expect(stopped.state, EngineState.activeDriveAnalytics);
      expect(stopped.motionAnalysisEnabled, isTrue);
      expect(orchestrator.transitionCount, 1);
    });

    test('losing the gate demotes to low-power tracking', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
        ),
      );
      orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.stationaryOrWalking,
        ),
      );

      expect(orchestrator.state, EngineState.lowPowerTracking);
      expect(orchestrator.profile.motionAnalysisEnabled, isFalse);
      expect(orchestrator.transitionCount, 2);
    });
  });

  group('tunnel dead reckoning', () {
    test('a stale fix while driving switches to dead reckoning', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
        ),
      );
      final EngineProfile tunnel = orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
          speedMps: 20,
          speedFresh: true,
          fixAge: Duration(seconds: 12),
          tunnelSuspect: true,
        ),
      );

      expect(tunnel.state, EngineState.tunnelDeadReckoning);
      // Analytics keep running underground: the accelerometer is the only
      // witness left, so switching it off would defeat the purpose.
      expect(tunnel.motionAnalysisEnabled, isTrue);
      expect(tunnel.deadReckoningEnabled, isTrue);
      expect(tunnel.locationInterval, const Duration(seconds: 5));
    });

    test('a fresh fix is not a tunnel even when flagged', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
          fixAge: Duration(seconds: 1),
          tunnelSuspect: true,
        ),
      );

      expect(orchestrator.state, EngineState.activeDriveAnalytics);
    });

    test('a tunnel suspicion without movement is not dead reckoning', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      // Parked in a garage with no fixes: still, so simply low-power tracking
      // rather than integrating an inertial position that goes nowhere.
      orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.stationaryOrWalking,
          speedMps: 0,
          speedFresh: true,
          fixAge: Duration(minutes: 2),
          tunnelSuspect: true,
        ),
      );

      expect(orchestrator.state, EngineState.lowPowerTracking);
    });

    test('a received fix ends dead reckoning', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
          speedMps: 20,
          speedFresh: true,
          fixAge: Duration(seconds: 30),
          tunnelSuspect: true,
        ),
      );
      expect(orchestrator.state, EngineState.tunnelDeadReckoning);

      orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
          speedMps: 20,
          speedFresh: true,
          fixAge: Duration(seconds: 1),
          tunnelSuspect: false,
        ),
      );

      expect(orchestrator.state, EngineState.activeDriveAnalytics);
    });

    test('a tunnel is only entered once the fix is older than the threshold', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator(
        tunnelFixAge: const Duration(seconds: 8),
      );

      orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
          speedMps: 20,
          speedFresh: true,
          fixAge: Duration(seconds: 7),
          tunnelSuspect: true,
        ),
      );
      expect(orchestrator.state, EngineState.activeDriveAnalytics);

      orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
          speedMps: 20,
          speedFresh: true,
          fixAge: Duration(seconds: 9),
          tunnelSuspect: true,
        ),
      );
      expect(orchestrator.state, EngineState.tunnelDeadReckoning);
    });
  });

  group('session end', () {
    test('clearing tracking returns to idle', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
        ),
      );
      orchestrator.observe(const EngineEvidence(trackingActive: false));

      expect(orchestrator.state, EngineState.idleStandby);
      expect(orchestrator.profile.motionAnalysisEnabled, isFalse);
      expect(orchestrator.profile.locationInterval,
          orchestrator.idleLocationInterval);
    });

    test('suspend stops everything immediately and forgets the evidence', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
        ),
      );
      orchestrator.suspend();

      expect(orchestrator.state, EngineState.idleStandby);
      expect(orchestrator.evidence.trackingActive, isFalse);
      expect(orchestrator.profile.motionAnalysisEnabled, isFalse);
    });

    test('suspend is idempotent', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.suspend();
      orchestrator.suspend();

      expect(orchestrator.state, EngineState.idleStandby);
      expect(orchestrator.transitionCount, 0);
    });
  });

  group('idle verdict (the accelerometer sees a parked device)', () {
    test('an idle verdict parks the stream while the trip is still live', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observe(const EngineEvidence(trackingActive: true));
      expect(orchestrator.state, EngineState.lowPowerTracking);

      orchestrator.observeIdle(true);

      expect(orchestrator.state, EngineState.idleStandby);
      expect(orchestrator.profile.locationPaused, isTrue);
      // The session survives: the trip is still being recorded, only the
      // position request is closed.
      expect(orchestrator.evidence.trackingActive, isTrue);
      expect(orchestrator.idle, isTrue);
    });

    test('a confirmed drive wins over the idle verdict', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
        ),
      );
      orchestrator.observeIdle(true);

      // A car that pulls away must never be silenced by a stale idle verdict.
      expect(orchestrator.state, EngineState.activeDriveAnalytics);
      expect(orchestrator.profile.locationPaused, isFalse);
    });

    test('the verdict is latched against unrelated evidence', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observe(const EngineEvidence(trackingActive: true));
      orchestrator.observeIdle(true);

      // A caller that only knows about speed must not wipe the verdict: it
      // lives on its own channel.
      orchestrator.observe(
        const EngineEvidence(trackingActive: true, speedMps: 1.2, speedFresh: true),
      );

      expect(orchestrator.state, EngineState.idleStandby);
      expect(orchestrator.idle, isTrue);
    });

    test('waking up re-opens the stream', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observe(const EngineEvidence(trackingActive: true));
      orchestrator.observeIdle(true);
      final int before = orchestrator.transitionCount;

      orchestrator.observeIdle(false);

      expect(orchestrator.state, EngineState.lowPowerTracking);
      expect(orchestrator.profile.locationPaused, isFalse);
      expect(orchestrator.transitionCount, before + 1);
    });

    test('repeating the same verdict changes nothing', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observe(const EngineEvidence(trackingActive: true));
      orchestrator.observeIdle(true);
      final int before = orchestrator.transitionCount;

      orchestrator.observeIdle(true);
      orchestrator.observeIdle(true);

      expect(orchestrator.transitionCount, before);
    });

    test('suspend forgets the verdict', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observe(const EngineEvidence(trackingActive: true));
      orchestrator.observeIdle(true);
      orchestrator.suspend();

      expect(orchestrator.idle, isFalse);
      expect(orchestrator.state, EngineState.idleStandby);
    });

    test('an idle verdict without a live trip changes nothing', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observeIdle(true);

      expect(orchestrator.state, EngineState.idleStandby);
      expect(orchestrator.transitionCount, 0);
    });
  });

  group('idempotence and the stream', () {
    test('unchanged evidence does not re-emit or count a transition', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      const EngineEvidence evidence = EngineEvidence(
        trackingActive: true,
        activityState: ActivityState.vehicleDriving,
      );
      orchestrator.observe(evidence);
      orchestrator.observe(evidence);
      orchestrator.observe(evidence);

      expect(orchestrator.transitionCount, 1);
    });

    test('emits each state change once, in order', () async {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();
      final List<EngineState> seen = <EngineState>[];
      final subscription = orchestrator.profiles.listen(
        (EngineProfile profile) => seen.add(profile.state),
      );

      orchestrator.observe(const EngineEvidence(trackingActive: true));
      orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
        ),
      );
      orchestrator.suspend();
      await Future<void>.delayed(Duration.zero);

      expect(seen, <EngineState>[
        EngineState.lowPowerTracking,
        EngineState.activeDriveAnalytics,
        EngineState.idleStandby,
      ]);
      await subscription.cancel();
    });

    test('dispose closes the stream', () async {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();
      await orchestrator.dispose();

      await orchestrator.profiles.listen((_) {}).asFuture<void>();
    });
  });

  group('profiles are complete for every state', () {
    test('every state has a profile with the documented invariants', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      final Map<EngineState, EngineProfile> profiles = <EngineState, EngineProfile>{
        EngineState.idleStandby:
            orchestrator.observe(const EngineEvidence(trackingActive: false)),
        EngineState.lowPowerTracking:
            orchestrator.observe(const EngineEvidence(trackingActive: true)),
        EngineState.activeDriveAnalytics: orchestrator.observe(
          const EngineEvidence(
            trackingActive: true,
            activityState: ActivityState.vehicleDriving,
          ),
        ),
        EngineState.tunnelDeadReckoning: orchestrator.observe(
          const EngineEvidence(
            trackingActive: true,
            activityState: ActivityState.vehicleDriving,
            speedMps: 20,
            speedFresh: true,
            fixAge: Duration(seconds: 20),
            tunnelSuspect: true,
          ),
        ),
      };

      for (final MapEntry<EngineState, EngineProfile> entry in profiles.entries) {
        expect(entry.value.state, entry.key);
        // Analysis on exactly when we are driving (including underground)...
        expect(
          entry.value.motionAnalysisEnabled,
          entry.key == EngineState.activeDriveAnalytics ||
              entry.key == EngineState.tunnelDeadReckoning,
          reason: 'analysis flag wrong for ${entry.key}',
        );
        // ...and a faster fix only when driving.
        if (entry.key == EngineState.activeDriveAnalytics) {
          expect(entry.value.locationInterval, const Duration(seconds: 1));
        } else {
          expect(entry.value.locationInterval, greaterThan(const Duration(seconds: 1)));
        }
        expect(entry.value.distanceFilterMeters, greaterThan(0));
      }
    });

    test('driving uses a tighter fix than standby', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      final EngineProfile idle =
          orchestrator.observe(const EngineEvidence(trackingActive: false));
      final EngineProfile driving = orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
        ),
      );

      expect(driving.locationInterval, lessThan(idle.locationInterval));
      expect(driving.distanceFilterMeters, lessThan(idle.distanceFilterMeters));
    });
  });

  group('location power management', () {
    test('standby closes the position stream outright', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      final EngineProfile idle =
          orchestrator.observe(const EngineEvidence(trackingActive: false));

      expect(idle.state, EngineState.idleStandby);
      // A paused profile is what suppresses the OS "frequently checks your
      // location" warning: the stream is unsubscribed, not merely slowed.
      expect(idle.locationPaused, isTrue);
      expect(idle.accuracy, LocationAccuracy.lowest);
      expect(idle.distanceFilterMeters, greaterThanOrEqualTo(200));
    });

    test('every driving-capable state keeps the stream open', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      final EngineProfile tracking =
          orchestrator.observe(const EngineEvidence(trackingActive: true));
      expect(tracking.locationPaused, isFalse);

      final EngineProfile driving = orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
        ),
      );
      expect(driving.state, EngineState.activeDriveAnalytics);
      expect(driving.locationPaused, isFalse);
      expect(driving.accuracy, LocationAccuracy.high);
      expect(driving.distanceFilterMeters, lessThanOrEqualTo(5));
      expect(driving.locationInterval, const Duration(seconds: 1));
    });

    test('only a confirmed drive asks for GPS-grade accuracy', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      final EngineProfile tracking =
          orchestrator.observe(const EngineEvidence(trackingActive: true));
      final EngineProfile driving = orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
        ),
      );

      expect(driving.accuracy.index, greaterThan(tracking.accuracy.index));
      // GPS grade is reserved for the confirmed drive: the tracking tier sits
      // at the balanced-power tier (geolocator's `medium` *is* Android's
      // `PRIORITY_BALANCED_POWER_ACCURACY`), never at `high`.
      expect(tracking.accuracy.index, lessThan(LocationAccuracy.high.index));
    });

    test('a tunnel backs the accuracy off from GPS grade', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      final EngineProfile tunnel = orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
          speedMps: 20,
          speedFresh: true,
          fixAge: Duration(seconds: 20),
          tunnelSuspect: true,
        ),
      );

      expect(tunnel.state, EngineState.tunnelDeadReckoning);
      expect(tunnel.locationPaused, isFalse);
      expect(tunnel.accuracy.index, lessThan(LocationAccuracy.high.index));
    });
  });

  group('moving heuristic', () {
    test('fresh fast speed without a gate verdict can still be a tunnel', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          speedMps: 25,
          speedFresh: true,
          fixAge: Duration(seconds: 30),
          tunnelSuspect: true,
        ),
      );

      expect(orchestrator.state, EngineState.tunnelDeadReckoning);
    });

    test('a stale fast speed does not count as moving', () {
      final AdaptiveEngineOrchestrator orchestrator = AdaptiveEngineOrchestrator();

      orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          speedMps: 25,
          speedFresh: false,
          fixAge: Duration(seconds: 30),
          tunnelSuspect: true,
        ),
      );

      expect(orchestrator.state, EngineState.lowPowerTracking);
    });

    test('the speed threshold is configurable', () {
      final AdaptiveEngineOrchestrator slow =
          AdaptiveEngineOrchestrator(speedThresholdKmh: 5);

      slow.observe(
        const EngineEvidence(
          trackingActive: true,
          speedMps: 2, // 7.2 km/h — above the lowered threshold
          speedFresh: true,
          fixAge: Duration(seconds: 30),
          tunnelSuspect: true,
        ),
      );

      expect(slow.state, EngineState.tunnelDeadReckoning);
    });
  });

  group('evidence copyWith', () {
    test('overrides only what is given', () {
      const EngineEvidence base = EngineEvidence(
        trackingActive: true,
        speedMps: 10,
        speedFresh: true,
      );

      final EngineEvidence updated = base.copyWith(
        activityState: ActivityState.vehicleDriving,
        fixAge: const Duration(seconds: 3),
      );

      expect(updated.trackingActive, isTrue);
      expect(updated.speedMps, 10);
      expect(updated.speedFresh, isTrue);
      expect(updated.activityState, ActivityState.vehicleDriving);
      expect(updated.fixAge, const Duration(seconds: 3));
    });
  });
}
