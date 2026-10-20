import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:routenote/src/core/motion/activity_state_manager.dart';
import 'package:routenote/src/core/orchestrator/adaptive_engine_orchestrator.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/sampling_target.dart';

/// Records the exact sampling profile it was handed, so the single translation
/// point between the orchestrator's FSM and a tracker's live stream can be
/// asserted without any platform channel.
class _FakeSamplingTarget implements SamplingTarget {
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];

  @override
  Future<void> applySampling({
    Duration? interval,
    LocationAccuracy? accuracy,
    int? distanceFilter,
    bool transportSpeed = false,
    bool paused = false,
  }) async {
    calls.add(<String, Object?>{
      'interval': interval,
      'accuracy': accuracy,
      'distanceFilter': distanceFilter,
      'transportSpeed': transportSpeed,
      'paused': paused,
    });
  }
}

void main() {
  group('applyEngineProfile', () {
    test('idleStandby pauses the stream and asks for the passive tier',
        () async {
      final _FakeSamplingTarget target = _FakeSamplingTarget();
      final AdaptiveEngineOrchestrator orchestrator =
          AdaptiveEngineOrchestrator();

      final EngineProfile idle =
          orchestrator.observe(const EngineEvidence(trackingActive: false));
      await applyEngineProfile(target, idle);

      final Map<String, Object?> call = target.calls.single;
      expect(call['paused'], isTrue);
      expect(call['accuracy'], LocationAccuracy.lowest);
      expect(call['distanceFilter'], greaterThanOrEqualTo(200));
      expect(call['interval'], const Duration(minutes: 10));
      // The parked-phone bug: a hardcoded transportSpeed flag used to hand out
      // GPS-grade fixes while idle. It must be off here.
      expect(call['transportSpeed'], isFalse);
    });

    test('lowPowerTracking opens the stream at a coarse tier without GPS grade',
        () async {
      final _FakeSamplingTarget target = _FakeSamplingTarget();
      final AdaptiveEngineOrchestrator orchestrator =
          AdaptiveEngineOrchestrator();

      final EngineProfile tracking =
          orchestrator.observe(const EngineEvidence(trackingActive: true));
      await applyEngineProfile(target, tracking);

      final Map<String, Object?> call = target.calls.single;
      expect(call['paused'], isFalse);
      expect(call['transportSpeed'], isFalse);
      expect(
        (call['accuracy']! as LocationAccuracy).index,
        lessThanOrEqualTo(LocationAccuracy.low.index),
      );
    });

    test('activeDriveAnalytics asks for GPS grade with the tight filter',
        () async {
      final _FakeSamplingTarget target = _FakeSamplingTarget();
      final AdaptiveEngineOrchestrator orchestrator =
          AdaptiveEngineOrchestrator();

      final EngineProfile driving = orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
        ),
      );
      await applyEngineProfile(target, driving);

      final Map<String, Object?> call = target.calls.single;
      expect(call['paused'], isFalse);
      expect(call['transportSpeed'], isTrue);
      expect(call['accuracy'], LocationAccuracy.high);
      expect(call['distanceFilter'], 5);
      expect(call['interval'], const Duration(seconds: 1));
    });

    test('the tunnel profile keeps the stream open at a backed-off accuracy',
        () async {
      final _FakeSamplingTarget target = _FakeSamplingTarget();
      final AdaptiveEngineOrchestrator orchestrator =
          AdaptiveEngineOrchestrator();

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
      await applyEngineProfile(target, tunnel);

      final Map<String, Object?> call = target.calls.single;
      expect(tunnel.state, EngineState.tunnelDeadReckoning);
      expect(call['paused'], isFalse);
      // Only a confirmed drive may lift the background accuracy cap.
      expect(call['transportSpeed'], isFalse);
    });

    test('leaving idle re-opens the stream that idle closed', () async {
      final _FakeSamplingTarget target = _FakeSamplingTarget();
      final AdaptiveEngineOrchestrator orchestrator =
          AdaptiveEngineOrchestrator();

      await applyEngineProfile(
        target,
        orchestrator.observe(const EngineEvidence(trackingActive: false)),
      );
      await applyEngineProfile(
        target,
        orchestrator.observe(
          const EngineEvidence(
            trackingActive: true,
            activityState: ActivityState.vehicleDriving,
          ),
        ),
      );

      expect(target.calls.first['paused'], isTrue);
      expect(target.calls.last['paused'], isFalse);
      expect(target.calls.last['transportSpeed'], isTrue);
    });
  });
}
