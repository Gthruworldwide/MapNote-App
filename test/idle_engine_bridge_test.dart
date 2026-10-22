import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routenote/src/core/motion/activity_state_manager.dart';
import 'package:routenote/src/core/motion/stationary_idle_detector.dart';
import 'package:routenote/src/core/orchestrator/adaptive_engine_orchestrator.dart';
import 'package:routenote/src/providers/app_providers.dart';

/// The idle half of the background-polling work: a parked device must close
/// the position stream outright, and the accelerometer must be able to wake it
/// again. This pins the bridge between the two owners:
///
/// ```
/// TransportClassifier.residualStream
///   → StationaryIdleDetector
///   → idleOrchestratorBridgeProvider
///   → AdaptiveEngineOrchestrator.observeIdle
///   → EngineProfile(locationPaused: true)
/// ```
void main() {
  group('idle detector → adaptive engine bridge', () {
    test('a parked device pauses the stream and a wake-up re-opens it', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final AdaptiveEngineOrchestrator orchestrator =
          container.read(adaptiveEngineOrchestratorProvider);
      final StationaryIdleDetector detector =
          container.read(stationaryIdleDetectorProvider);
      // Reading the bridge is what subscribes it (one subscription for the
      // whole app, shared by both tracker controllers).
      container.read(idleOrchestratorBridgeProvider);

      orchestrator.observe(const EngineEvidence(trackingActive: true));
      expect(orchestrator.state, EngineState.lowPowerTracking);
      expect(orchestrator.profile.locationPaused, isFalse);

      // The detector's verdict is the only thing that changes: the trip stays
      // live, but the platform subscription must be closed.
      detector.setState(MotionState.stationary);
      expect(orchestrator.state, EngineState.idleStandby);
      expect(orchestrator.profile.locationPaused, isTrue);
      expect(orchestrator.evidence.trackingActive, isTrue);

      // The accelerometer sees movement again (the classifier published a
      // residual above the bar), so the stream re-opens.
      detector.setState(MotionState.active);
      expect(orchestrator.state, EngineState.lowPowerTracking);
      expect(orchestrator.profile.locationPaused, isFalse);
    });

    test('the detector cannot deadlock: waking never exceeds falling asleep',
        () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final StationaryIdleDetector detector =
          container.read(stationaryIdleDetectorProvider);

      // A device is only judged parked when its residual sits *below* the
      // motion threshold. If waking needed a *stronger* signal than that, a
      // residual in between would keep the device parked forever — and a
      // parked stream has no GPS to rescue it.
      expect(detector.wakeupThreshold, lessThanOrEqualTo(detector.motionThreshold));
      // The thresholds match the classifier's own "still" bar, which is what
      // is actually fed to the detector.
      expect(detector.motionThreshold, 0.28);
    });

    test('one detector instance is shared by every reader', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        identical(
          container.read(stationaryIdleDetectorProvider),
          container.read(stationaryIdleDetectorProvider),
        ),
        isTrue,
      );
    });

    test('the bridge does not touch the activity evidence', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final AdaptiveEngineOrchestrator orchestrator =
          container.read(adaptiveEngineOrchestratorProvider);
      final StationaryIdleDetector detector =
          container.read(stationaryIdleDetectorProvider);
      container.read(idleOrchestratorBridgeProvider);

      // A confirmed drive, then a stale idle verdict: the car keeps its
      // analytics. The bridge carries only the idle flag, so the activity
      // evidence is never wiped by an idle event.
      orchestrator.observe(
        const EngineEvidence(
          trackingActive: true,
          activityState: ActivityState.vehicleDriving,
        ),
      );
      detector.setState(MotionState.stationary);

      expect(orchestrator.state, EngineState.activeDriveAnalytics);
      expect(orchestrator.evidence.activityState, ActivityState.vehicleDriving);
    });
  });
}
