import 'dart:async';
import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../data/local/hive_database.dart';
import '../data/local/auto_motion_data_source.dart';
import '../data/local/gps_daily_data_source.dart';
import '../data/local/place_local_data_source.dart';
import '../data/local/settings_repository.dart';
import '../data/models/agent_insight.dart';
import '../data/models/daily_gps_summary.dart';
import '../data/models/place.dart';
import '../data/remote/auth_service.dart';
import '../data/remote/drive_service.dart';
import '../data/remote/google_auth_service.dart';
import '../data/repositories/place_repository.dart';
import '../data/repositories/sync_repository.dart';
import '../features/motion_analytics/data/ml_classifier_isolate.dart';
import '../features/motion_analytics/data/motion_event_mapper.dart';
import '../features/motion_analytics/domain/entities/motion_event.dart';
import '../core/config/app_config.dart';
import '../core/config/preferred_nav_app.dart';
import '../core/memory/adaptive_profile_key_store.dart';
import '../core/memory/adaptive_profile_repository.dart';
import '../core/memory/self_diagnostic_monitor.dart';
import '../core/motion/activity_state_manager.dart';
import '../core/motion/motion_gate.dart';
import '../core/orchestrator/adaptive_engine_orchestrator.dart';
import '../core/security/device_lock_detector.dart';
import '../core/security/session_guard.dart';
import '../core/security/secure_session_token_store.dart';
import '../services/adaptive_sampling_manager.dart';
import '../services/agent_service.dart';
import '../services/analytics_service.dart';
import '../services/app_health_logger.dart';
import '../services/app_logger.dart';
import '../services/app_observer_service.dart';
import '../services/auto_motion_service.dart';
import '../services/background_sync_scheduler.dart';
import '../services/biometric_service.dart';
import '../services/dead_reckoning_service.dart';
import '../services/dynamic_icon_service.dart';
import '../services/foreground_tracking_service.dart';
import '../services/fused_location_service.dart';
import '../services/gap_recovery_service.dart';
import '../services/gemini_client.dart';
import '../services/geocoding_service.dart';
import '../services/gps_tracker_service.dart';
import '../services/home_shortcut_service.dart';
import '../services/key_rotation_service.dart';
import '../services/local_insight_engine.dart';
import '../services/location_hub.dart';
import '../services/location_service.dart';
import '../services/milestone_name_resolver.dart';
import '../services/motion_profiler.dart';
import '../services/motion_sensor_hub.dart';
import '../services/motion_signal.dart';
import '../services/sampling_target.dart';
import '../services/navigation_service.dart';
import '../services/route_milestones.dart';
import '../services/share_intent_service.dart';
import '../services/smart_clipboard_service.dart';
import '../services/transport_classifier.dart';

// ---------------------------------------------------------------------------
// Storage & repositories
// ---------------------------------------------------------------------------

/// Opened in `main()` and overridden there; never used before the app runs.
final Provider<HiveDatabase> hiveDatabaseProvider = Provider<HiveDatabase>((
  Ref ref,
) {
  throw StateError('hiveDatabaseProvider must be overridden in main()');
});

final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>((Ref ref) {
      return SettingsRepository(ref.watch(hiveDatabaseProvider).settingsBox);
    });

final Provider<PlaceLocalDataSource> placeLocalDataSourceProvider =
    Provider<PlaceLocalDataSource>((Ref ref) {
      return PlaceLocalDataSource(ref.watch(hiveDatabaseProvider));
    });

final Provider<PlaceRepository> placeRepositoryProvider =
    Provider<PlaceRepository>((Ref ref) {
      return PlaceRepository(ref.watch(placeLocalDataSourceProvider));
    });

/// Per-day GPS tracking summaries (dates → km / max speed), stored in Hive.
final Provider<GpsDailyDataSource> gpsDailyDataSourceProvider =
    Provider<GpsDailyDataSource>((Ref ref) {
      return GpsDailyDataSource(ref.watch(hiveDatabaseProvider).gpsDailyBox);
    });

/// Per-day AutoMotion metrics (dates → km / max speed), stored in Hive under
/// `auto_motion_box` keyed by `YYYY-MM-DD`.
final Provider<AutoMotionDataSource> autoMotionDataSourceProvider =
    Provider<AutoMotionDataSource>((Ref ref) {
      return AutoMotionDataSource(
        ref.watch(hiveDatabaseProvider).autoMotionBox,
      );
    });

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

final Provider<LocationService> locationServiceProvider =
    Provider<LocationService>((Ref ref) => const LocationService());

/// The single owner of MapNote's live OS location subscription.
///
/// Everything that wants position fixes — the two daily trackers and the Qibla
/// compass — acquires this hub instead of calling `getPositionStream` itself,
/// so the app registers **one** `FusedLocationProvider` client rather than one
/// per consumer. It is reference-counted: the moment the last consumer releases
/// (a tracked stop, or an idle pause) the handle is cancelled outright and the
/// receiver can sleep. See [LocationHub] and `AGENT_SKILLS.md` §6.
final Provider<LocationHub> locationHubProvider = Provider<LocationHub>(
  (Ref ref) {
    final LocationHub hub = LocationHub(
      locations: ref.watch(locationServiceProvider),
    );
    ref.onDispose(hub.dispose);
    return hub;
  },
);

/// The single subscriber to the native motion channel: it fans sensor samples
/// out to the trackers' movement signal, the transport-mode classifier and
/// the dead-reckoning engine, reference-counting the one platform stream so
/// the hardware only samples while at least one consumer runs.
final Provider<MotionSensorHub> motionSensorHubProvider =
    Provider<MotionSensorHub>((Ref ref) {
      final MotionSensorHub hub = MotionSensorHub();
      ref.onDispose(hub.dispose);
      return hub;
    });

/// Movement evidence shared by the two daily trackers: an accelerometer-backed
/// sensor bridge on Android, inert elsewhere. The trackers refcount it, so the
/// accelerometer only samples while one of them is actually running. Draws
/// from [motionSensorHubProvider] so the shared hardware feed is never opened
/// twice.
final Provider<MotionSignal> motionSignalProvider =
    Provider<MotionSignal>(
  (Ref ref) => SensorMotionSignal(hub: ref.watch(motionSensorHubProvider)),
);

/// The gap-recovery rule (pure arithmetic, no streams): judged separately for
/// each outage span, so both trackers share one implementation.
final Provider<GapRecoveryService> gapRecoveryServiceProvider =
    Provider<GapRecoveryService>((Ref ref) => const GapRecoveryService());

/// Transport-mode classifier over the shared accelerometer feed.
final Provider<TransportClassifier> transportClassifierProvider =
    Provider<TransportClassifier>((Ref ref) {
      return TransportClassifier(
        accelerometer: ref.watch(motionSensorHubProvider).accelerometer,
      );
    });

/// On-device motion analytics: the vehicle-frame classifier that turns the
/// accelerometer into hard brakes, harsh launches, sharp turns, speed bumps and
/// potholes.
///
/// Inference runs on a **dedicated background isolate**
/// (`IsolateMotionInferenceRunner`), rebuilt from `buildHeuristicMotionModel` —
/// the deterministic feature model that ships today. Point this provider at a
/// builder that loads a trained `.tflite` asset and the whole pipeline follows,
/// with no other change (see `MotionModel` for the tensor contract).
///
/// Its accelerometer feed is [motionGateProvider]'s **gated** stream, not the
/// raw hub: while the activity gate says "still or walking", no sample reaches
/// this classifier, so its 128-sample ring buffer never fills and the inference
/// isolate is never asked to run. Its lifecycle otherwise mirrors
/// [motionBehaviorAnalyzerProvider]: started and stopped with AutoMotion
/// tracking, and its stream is bridged into the analyzer.
final Provider<MLClassifierIsolate> mlClassifierIsolateProvider =
    Provider<MLClassifierIsolate>((Ref ref) {
      final MLClassifierIsolate classifier = MLClassifierIsolate.standard(
        accelerometer: ref.watch(motionGateProvider).gated,
      );
      ref.onDispose(classifier.dispose);
      return classifier;
    });

/// Driving-behavior profiler (harsh acceleration / hard braking) over the
/// same gated accelerometer feed, mirroring the classifier's construction.
///
/// GPS speed reaches the analyzer through the AutoMotion tracker's engine
/// (the engine fuses each fix's speed next to the motion signal), and the
/// vehicle gate through the classifier verdicts `AutoMotionController`
/// already distributes. Lifecycle ([MotionBehaviorAnalyzer.start]/[stop]) is
/// owned by that controller alongside the classifier's; [reset] happens when
/// a new trip starts, via [drivingEventsProvider].
///
/// The calibrated-frame classifier is fused in here: every maneuver
/// [mlClassifierIsolateProvider] classifies joins the analyzer's log through
/// [MotionBehaviorAnalyzer.observeDrivingEvent], which is what puts lateral and
/// vertical dynamics (turns, bumps, potholes) on the same list as the
/// longitudinal ones the speed timeline signs.
final Provider<MotionBehaviorAnalyzer> motionBehaviorAnalyzerProvider =
    Provider<MotionBehaviorAnalyzer>((Ref ref) {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer(
        accelerometer: ref.watch(motionGateProvider).gated,
      );
      final StreamSubscription<MotionEvent> classified = ref
          .watch(mlClassifierIsolateProvider)
          .onEvent
          .listen((MotionEvent event) {
            if (!ref.mounted) return;
            final DrivingEvent? driving = toDrivingEvent(event);
            // Smooth driving is a state, not a maneuver: it has no place in a
            // log of things that happened.
            if (driving != null) analyzer.observeDrivingEvent(driving);
          });
      ref.onDispose(classified.cancel);
      ref.onDispose(analyzer.stop);
      return analyzer;
    });

/// Inertial dead reckoning over the shared accelerometer/gyroscope feeds —
/// the fallback witness for outage spans the Haversine crossing cannot vouch
/// for.
final Provider<DeadReckoningService> deadReckoningServiceProvider =
    Provider<DeadReckoningService>((Ref ref) {
      final MotionSensorHub hub = ref.watch(motionSensorHubProvider);
      return DeadReckoningService(
        accelerometer: hub.accelerometer,
        gyroscope: hub.gyroscope,
      );
    });

/// Fused high-accuracy ⇄ low-power-network fallback for the trackers' live
/// platform streams.
final Provider<FusedLocationService> fusedLocationServiceProvider =
    Provider<FusedLocationService>((Ref ref) {
      return FusedLocationService(locationService: ref.watch(locationServiceProvider));
    });

/// Phase-1 daily GPS tracker (distance + max speed while the app is open).
final Provider<GpsTrackerService> gpsTrackerProvider =
    Provider<GpsTrackerService>((Ref ref) {
      return GpsTrackerService(
        dailyStore: ref.watch(gpsDailyDataSourceProvider),
        motion: ref.watch(motionSignalProvider),
        gapRecovery: ref.watch(gapRecoveryServiceProvider),
        deadReckoning: ref.watch(deadReckoningServiceProvider),
        fused: ref.watch(fusedLocationServiceProvider),
        hub: ref.watch(locationHubProvider),
      );
    });

/// Phase-1 AutoMotion tracker (distance + max speed while the app is open).
final Provider<AutoMotionService> autoMotionServiceProvider =
    Provider<AutoMotionService>((Ref ref) {
      return AutoMotionService(
        dailyStore: ref.watch(autoMotionDataSourceProvider),
        motion: ref.watch(motionSignalProvider),
        gapRecovery: ref.watch(gapRecoveryServiceProvider),
        deadReckoning: ref.watch(deadReckoningServiceProvider),
        behavior: ref.watch(motionBehaviorAnalyzerProvider),
        fused: ref.watch(fusedLocationServiceProvider),
        hub: ref.watch(locationHubProvider),
      );
    });

/// Android foreground service + runtime permissions that keep the daily
/// trackers alive while MapNote is backgrounded.
final Provider<ForegroundTrackingService> foregroundTrackingServiceProvider =
    Provider<ForegroundTrackingService>(
  (Ref ref) => ForegroundTrackingService(),
);

/// Sensor-driven sampling stack: the shared accelerometer feed, the transport
/// classifier whose verdicts drive the adaptive sampling profile, the
/// dead-reckoning engine and the slow battery poll.
///
/// Exactly one instance runs while **either** daily tracker records (the same
/// rule the foreground service follows), so a stationary phone never keeps the
/// accelerometer hardware or a 1 s GPS request alive merely because a toggle
/// is on: the classifier's "stationary" verdict stretches the interval to
/// 60 s behind a 50 m movement filter. The driving-behavior analyzer is
/// deliberately *not* part of this stack — its lifecycle stays owned by
/// `AutoMotionController`, because its events surface on the AutoMotion
/// dashboard.
class AdaptiveTrackingStack {
  bool _running = false;
  StreamSubscription<TransportMode>? _modes;

  /// Whether the stack is currently running (diagnostics/tests).
  bool get isRunning => _running;

  /// Brings the stack in line with [needed]: starts it when needed and down,
  /// stops it when it is running and no longer needed. Idempotent, so both
  /// tracker controllers can fire it after every start/stop — a call that
  /// finds the desired state already reached does nothing.
  Future<void> sync({
    required bool needed,
    required MotionSensorHub hub,
    required TransportClassifier classifier,
    required DeadReckoningService deadReckoning,
    required AdaptiveSamplingNotifier sampling,
  }) async {
    if (needed == _running) return;
    _running = needed;
    if (needed) {
      // Hub first: the classifier and dead reckoning listen to its fan-out,
      // which buffers nothing while unlistened.
      await hub.start();
      await classifier.start();
      await deadReckoning.start();
      // Classifier verdicts drive the shared profile (battery arrives through
      // the poll); a disposed stack stops consuming them.
      _modes = classifier.modes.listen(sampling.observeTransport);
      sampling.startPolling();
      return;
    }
    await _modes?.cancel();
    _modes = null;
    await classifier.stop();
    await deadReckoning.stop();
    sampling.stopPolling();
    await hub.stop();
  }

  /// Tears down the subscription without touching the (provider-scoped)
  /// services themselves — used when the provider is disposed.
  void cancel() {
    _running = false;
    unawaited(_modes?.cancel());
    _modes = null;
  }
}

/// The shared sensor-driven sampling stack (see [AdaptiveTrackingStack]).
final Provider<AdaptiveTrackingStack> adaptiveTrackingStackProvider =
    Provider<AdaptiveTrackingStack>((Ref ref) {
  final AdaptiveTrackingStack stack = AdaptiveTrackingStack();
  ref.onDispose(stack.cancel);
  return stack;
});

final Provider<NavigationService> navigationServiceProvider =
    Provider<NavigationService>((Ref ref) {
      // Rebuilt whenever the preferred-app setting changes, so every
      // `nav.navigate(...)` call site picks the new app automatically.
      return NavigationService(
        preferredApp: ref.watch(preferredNavAppProvider),
      );
    });

final Provider<ShareIntentService> shareIntentServiceProvider =
    Provider<ShareIntentService>((Ref ref) => const ShareIntentService());

/// Spots raw Plus Codes in the clipboard so the app can offer a one-tap import.
final Provider<SmartClipboardService> smartClipboardServiceProvider =
    Provider<SmartClipboardService>((Ref ref) => const SmartClipboardService());

/// Reverse/forward geocoding used to suggest a name and notes for a location.
///
/// Constructed lazily and best-effort: [GeocodingService] never touches the
/// platform geocoder until it is asked to, and returns `null` offline.
final Provider<GeocodingService> geocodingServiceProvider =
    Provider<GeocodingService>((Ref ref) => GeocodingService());

final Provider<BiometricService> biometricServiceProvider =
    Provider<BiometricService>((Ref ref) => const BiometricService());

final Provider<HomeShortcutService> homeShortcutServiceProvider =
    Provider<HomeShortcutService>((Ref ref) {
      final HomeShortcutService service = HomeShortcutService();
      ref.onDispose(service.dispose);
      return service;
    });

/// Keeps the launcher icon's light/dark variant in sync with the theme.
final Provider<DynamicIconService> dynamicIconServiceProvider =
    Provider<DynamicIconService>((Ref ref) => const DynamicIconService());

final Provider<AuthService> authServiceProvider = Provider<AuthService>(
  (Ref ref) => GoogleAuthService(),
);

final Provider<DriveService> driveServiceProvider = Provider<DriveService>((
  Ref ref,
) {
  return GoogleDriveService(ref.watch(authServiceProvider));
});

final Provider<SyncRepository> syncRepositoryProvider =
    Provider<SyncRepository>((Ref ref) {
      return SyncRepository(
        placeRepository: ref.watch(placeRepositoryProvider),
        driveService: ref.watch(driveServiceProvider),
        settingsRepository: ref.watch(settingsRepositoryProvider),
        authService: ref.watch(authServiceProvider),
      );
    });

final Provider<BackgroundSyncScheduler> backgroundSyncSchedulerProvider =
    Provider<BackgroundSyncScheduler>(
      (Ref ref) => const BackgroundSyncScheduler(),
    );

// ---------------------------------------------------------------------------
// Monitoring & recommendation agent
// ---------------------------------------------------------------------------

/// Local, privacy-safe event/health log (lifecycle, sync, parse, latency).
final Provider<AppHealthLogger> appHealthLoggerProvider =
    Provider<AppHealthLogger>((Ref ref) {
      return AppHealthLogger(
        ref.watch(hiveDatabaseProvider).settingsBox,
        capacity: AppConfig.healthLogCapacity,
      );
    });

/// Sanitized issue-reporting facade layered over the health log.
final Provider<AppObserverService> appObserverServiceProvider =
    Provider<AppObserverService>((Ref ref) {
      return AppObserverService(ref.watch(appHealthLoggerProvider));
    });

// ---------------------------------------------------------------------------
// Adaptive engine: orchestrator, activity gate and adaptive memory
// ---------------------------------------------------------------------------

/// The central FSM coordinating every adaptive subsystem. Pure and cheap to
/// build; it holds no resources, so nothing needs disposing.
final Provider<AdaptiveEngineOrchestrator> adaptiveEngineOrchestratorProvider =
    Provider<AdaptiveEngineOrchestrator>(
  (Ref ref) => AdaptiveEngineOrchestrator(),
);

/// The activity gate: still/walking vs a confirmed road vehicle.
///
/// Owns the only cheap always-on window judgement in the app, and is the single
/// authority on whether the expensive motion pipeline may run at all.
final Provider<ActivityStateManager> activityStateManagerProvider =
    Provider<ActivityStateManager>((Ref ref) {
      final ActivityStateManager manager = ActivityStateManager();
      ref.onDispose(manager.dispose);
      return manager;
    });

/// The gate in front of the analysis pipeline.
///
/// Its [MotionGate.gated] stream — not the raw hub — is what
/// [mlClassifierIsolateProvider] and [motionBehaviorAnalyzerProvider] consume,
/// so while the user is indoors nothing reaches them: no ring buffer, no
/// gravity EMA, no isolate request. That is the battery/thermal saving the
/// whole gate exists for.
final Provider<MotionGate> motionGateProvider = Provider<MotionGate>((Ref ref) {
  final MotionGate gate = MotionGate(
    manager: ref.watch(activityStateManagerProvider),
    hub: ref.watch(motionSensorHubProvider),
  );
  ref.onDispose(gate.dispose);
  return gate;
});

/// AES-256 key for the adaptive-profile box, kept in the platform keystore.
final Provider<AdaptiveProfileKeyStore> adaptiveProfileKeyStoreProvider =
    Provider<AdaptiveProfileKeyStore>(
  (Ref ref) => const AdaptiveProfileKeyStore(
    read: _readSecret,
    write: _writeSecret,
  ),
);

/// The learned per-device motion profile (vibration baselines, thresholds).
///
/// Holds only numbers — no user content — so it needs no biometric gate, and
/// every failure degrades to the documented defaults rather than disabling
/// classification.
final Provider<AdaptiveProfileRepository> adaptiveProfileRepositoryProvider =
    Provider<AdaptiveProfileRepository>((Ref ref) {
      final AdaptiveProfileRepository repository = AdaptiveProfileRepository(
        keyStore: ref.watch(adaptiveProfileKeyStoreProvider),
      );
      ref.onDispose(repository.close);
      return repository;
    });

/// Locally-observed app health: frame pacing, memory, background time.
///
/// Entirely offline — the snapshot only ever feeds the local health log.
final Provider<SelfDiagnosticMonitor> selfDiagnosticMonitorProvider =
    Provider<SelfDiagnosticMonitor>((Ref ref) {
      return SelfDiagnosticMonitor(readMemoryBytes: _readProcessMemory);
    });

/// Owns the authenticated session that keeps the encrypted vault unlocked.
///
/// The single place that decides when the vault must re-prompt: the device lock
/// screen, backgrounding past the grace period, inactivity past the timeout, or
/// an explicit end. Its stream is what the app root listens to in order to
/// actually lock the vault.
///
/// The timeout and the device-lock behaviour come from [SettingsRepository], so
/// the user's choice in Settings is honoured from the very first session. The
/// settings read is *best-effort*: a container without a Hive box (widget tests,
/// or a corrupt box) must still get a working guard with the safe defaults rather
/// than throwing, because the guard is on the vault's critical path.
final Provider<SessionGuard> sessionGuardProvider = Provider<SessionGuard>(
  (Ref ref) {
    final SettingsRepository? settings = _tryReadSettings(ref);
    final SessionGuard guard = SessionGuard(
      tokenStore: ref.watch(sessionTokenStoreProvider),
      inactivityTimeout: Duration(
        minutes: settings?.sessionTimeoutMinutes ??
            SessionGuard.defaultInactivityTimeout.inMinutes,
      ),
      lockOnDeviceLock: settings?.isLockOnDeviceLockEnabled ?? true,
    );
    ref.onDispose(guard.dispose);
    return guard;
  },
);

/// Reads [settingsRepositoryProvider], or `null` when it is unavailable.
///
/// Reading a provider that throws (no Hive box) would poison this provider's
/// state permanently in Riverpod, so the failure is contained here.
SettingsRepository? _tryReadSettings(Ref ref) {
  try {
    return ref.watch(settingsRepositoryProvider);
  } catch (_) {
    return null;
  }
}

/// How long the encrypted vault may stay unlocked without interaction, in
/// minutes, as chosen in Settings.
///
/// Changing it also applies it to the already-built [sessionGuardProvider] so the
/// new window takes effect on the next tick rather than on the next launch.
class SessionTimeoutController extends Notifier<int> {
  @override
  int build() => ref.watch(settingsRepositoryProvider).sessionTimeoutMinutes;

  Future<void> setMinutes(int minutes) async {
    await ref.read(settingsRepositoryProvider).setSessionTimeoutMinutes(minutes);
    ref.read(sessionGuardProvider).setInactivityTimeout(
          Duration(minutes: minutes),
        );
    state = minutes;
  }
}

/// The user's choice of inactivity window (minutes).
final NotifierProvider<SessionTimeoutController, int> sessionTimeoutProvider =
    NotifierProvider<SessionTimeoutController, int>(
      SessionTimeoutController.new,
    );

/// Whether reaching the device lock screen ends the vault session immediately.
///
/// Changing it also updates the live [sessionGuardProvider] so the switch takes
/// effect without a restart.
class LockOnDeviceLockController extends Notifier<bool> {
  @override
  bool build() => ref.watch(settingsRepositoryProvider).isLockOnDeviceLockEnabled;

  Future<void> setEnabled(bool value) async {
    await ref
        .read(settingsRepositoryProvider)
        .setLockOnDeviceLockEnabled(value);
    ref.read(sessionGuardProvider).setLockOnDeviceLock(value);
    state = value;
  }
}

/// Whether the vault locks the moment the device does.
final NotifierProvider<LockOnDeviceLockController, bool>
    lockOnDeviceLockProvider =
    NotifierProvider<LockOnDeviceLockController, bool>(
      LockOnDeviceLockController.new,
    );

/// Distinguishes a hand-held device from one lying still on a surface, from
/// accelerometer micro-movements.
///
/// Feeds the [SessionGuard]'s surface-idle verdict, which shortens the vault's
/// inactivity window when the phone has been abandoned on a table. The stream is
/// opened only when a session is worth protecting; a stopped detector leaves the
/// verdict `unknown`, which the guard treats as hand-held (the longer clock), so
/// a missing sensor can never lock a session early.
final Provider<DeviceLockDetector> deviceLockDetectorProvider =
    Provider<DeviceLockDetector>((Ref ref) {
      final DeviceLockDetector detector = DeviceLockDetector(
        hub: ref.watch(motionSensorHubProvider),
      );
      ref.onDispose(detector.dispose);
      return detector;
    });

/// The current hand-held / surface-idle verdict, as reactive state.
///
/// A stream over [DeviceLockDetector.contextChanges]: the detector publishes a
/// value only when the verdict actually changes, so this costs nothing between
/// transitions and needs no polling timer. The current value is emitted first,
/// so a screen that opens mid-stillness dims at once rather than waiting for the
/// next transition.
final StreamProvider<InteractionContext> interactionContextProvider =
    StreamProvider<InteractionContext>((Ref ref) {
  final DeviceLockDetector detector = ref.watch(deviceLockDetectorProvider);
  return _contextStream(detector);
});

Stream<InteractionContext> _contextStream(DeviceLockDetector detector) async* {
  yield detector.context;
  yield* detector.contextChanges;
}

/// Platform-keystore-backed store for the opaque session token.
final Provider<SessionTokenStore> sessionTokenStoreProvider =
    Provider<SessionTokenStore>(
  (Ref ref) => const SecureSessionTokenStore(),
);

/// Reads a secret from the platform keystore (adapter for the profile key).
Future<String?> _readSecret(String key) =>
    const SecureSessionTokenStore().read(key);

/// Writes a secret to the platform keystore (adapter for the profile key).
Future<void> _writeSecret(String key, String value) =>
    const SecureSessionTokenStore().write(key, value);

/// Reads the process resident set size in bytes.
///
/// Returns 0 when `dart:io` has no answer (a platform without `/proc`, or a
/// test environment): the diagnostic monitor treats 0 as "unknown", and a
/// health metric must never be the reason something throws.
int _readProcessMemory() {
  try {
    return ProcessInfo.currentRss;
  } catch (_) {
    return 0;
  }
}

// ---------------------------------------------------------------------------
// Analytics
// ---------------------------------------------------------------------------

/// Firebase Analytics facade.
///
/// Null-backed when Firebase never initialised (offline-first: a missing
/// `google-services.json` must not break launch), in which case every event
/// degrades to a silent no-op. Resolved once, right after `main()`'s
/// best-effort `Firebase.initializeApp()`.
final Provider<AnalyticsService> analyticsServiceProvider =
    Provider<AnalyticsService>((Ref ref) {
      FirebaseAnalytics? analytics;
      try {
        if (Firebase.apps.isNotEmpty) {
          analytics = FirebaseAnalytics.instance;
        }
      } catch (_) {
        // Firebase is unavailable: fall back to the no-op service.
        analytics = null;
      }
      return AnalyticsService(analytics: analytics);
    });

/// [FirebaseAnalyticsObserver] wired into [MaterialApp.navigatorObservers] for
/// automatic `screen_view` events.
///
/// Empty when Firebase is unavailable, so navigation never depends on it.
final Provider<List<NavigatorObserver>> analyticsNavigatorObserversProvider =
    Provider<List<NavigatorObserver>>((Ref ref) {
      final FirebaseAnalytics? analytics = ref
          .watch(analyticsServiceProvider)
          .analytics;
      if (analytics == null) return const <NavigatorObserver>[];
      return <NavigatorObserver>[
        FirebaseAnalyticsObserver(analytics: analytics),
      ];
    });

/// Pure, offline rule engine.
final Provider<LocalInsightEngine> localInsightEngineProvider =
    Provider<LocalInsightEngine>((Ref ref) => const LocalInsightEngine());

/// Build-time Gemini API-key pool with cooldown-based rotation.
///
/// Empty when no key was compiled in, which keeps the cloud agent disabled.
final Provider<KeyRotationService> keyRotationServiceProvider =
    Provider<KeyRotationService>(
      (Ref ref) => KeyRotationService(keys: AppConfig.geminiApiKeys),
    );

/// Optional Gemini client (only active when an API key is configured).
final Provider<GeminiClient> geminiClientProvider = Provider<GeminiClient>((
  Ref ref,
) {
  final GeminiClient client = GeminiClient(
    keyRotation: ref.watch(keyRotationServiceProvider),
  );
  ref.onDispose(client.close);
  return client;
});

/// Facade combining the local engine with the optional cloud client.
final Provider<AgentService> agentServiceProvider = Provider<AgentService>((
  Ref ref,
) {
  return AgentService(
    logger: ref.watch(appHealthLoggerProvider),
    settings: ref.watch(settingsRepositoryProvider),
    engine: ref.watch(localInsightEngineProvider),
    cloudClient: ref.watch(geminiClientProvider),
  );
});

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// The list of saved places.
final AsyncNotifierProvider<PlacesNotifier, List<Place>> placesProvider =
    AsyncNotifierProvider<PlacesNotifier, List<Place>>(PlacesNotifier.new);

/// Authentication + account state.
final AsyncNotifierProvider<AuthNotifier, AuthUser?> authProvider =
    AsyncNotifierProvider<AuthNotifier, AuthUser?>(AuthNotifier.new);

/// Live location availability (GPS on/off + permission) for status indicators.
final AsyncNotifierProvider<LocationStatusNotifier, LocationStatus>
locationStatusProvider =
    AsyncNotifierProvider<LocationStatusNotifier, LocationStatus>(
      LocationStatusNotifier.new,
    );

/// Backup / sync status.
final NotifierProvider<SyncController, SyncState> syncControllerProvider =
    NotifierProvider<SyncController, SyncState>(SyncController.new);

/// Selected locale (null = follow the system language).
final NotifierProvider<LocaleController, Locale?> localeControllerProvider =
    NotifierProvider<LocaleController, Locale?>(LocaleController.new);

/// App theme mode, persisted.
final NotifierProvider<ThemeModeController, ThemeMode> themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// Smart Insights produced by the monitoring & recommendation agent.
final AsyncNotifierProvider<AgentNotifier, List<AgentInsight>> agentProvider =
    AsyncNotifierProvider<AgentNotifier, List<AgentInsight>>(AgentNotifier.new);

/// Whether optional cloud (Gemini) suggestions are enabled.
final NotifierProvider<CloudAiController, bool> cloudAiEnabledProvider =
    NotifierProvider<CloudAiController, bool>(CloudAiController.new);

/// The app used to launch turn-by-turn navigation from place cards.
final NotifierProvider<PreferredNavAppController, PreferredNavApp>
preferredNavAppProvider =
    NotifierProvider<PreferredNavAppController, PreferredNavApp>(
      PreferredNavAppController.new,
    );

/// Whether the Smart Insights feature is shown on the Home screen.
final NotifierProvider<SmartInsightsController, bool>
smartInsightsEnabledProvider = NotifierProvider<SmartInsightsController, bool>(
  SmartInsightsController.new,
);
final NotifierProvider<GpsTrackingEnabledController, bool>
gpsTrackingEnabledProvider =
    NotifierProvider<GpsTrackingEnabledController, bool>(
      GpsTrackingEnabledController.new,
    );

/// Live daily distance/speed summary surfaced by the Settings tile.
final NotifierProvider<GpsTrackingController, GpsTrackingState>
gpsTrackingControllerProvider =
    NotifierProvider<GpsTrackingController, GpsTrackingState>(
      GpsTrackingController.new,
    );

/// Whether AutoMotion is enabled (Settings → AutoMotion).
final NotifierProvider<AutoMotionEnabledController, bool>
autoMotionEnabledProvider =
    NotifierProvider<AutoMotionEnabledController, bool>(
      AutoMotionEnabledController.new,
    );

/// Live AutoMotion dashboard state surfaced by the Home card.
final NotifierProvider<AutoMotionController, AutoMotionState>
autoMotionControllerProvider =
    NotifierProvider<AutoMotionController, AutoMotionState>(
      AutoMotionController.new,
    );

/// AutoMotion's recorded days, newest-first, for the dashboard trip history.
final NotifierProvider<AutoMotionHistoryController, List<DailyGpsSummary>>
autoMotionHistoryProvider =
    NotifierProvider<AutoMotionHistoryController, List<DailyGpsSummary>>(
      AutoMotionHistoryController.new,
    );

/// Serialized lifecycle queue for [GpsTrackingController]. Held in a provider
/// (not a controller field) so the chain survives the controller being rebuilt
/// every time the toggle flips.
final Provider<_LifecycleQueue> _gpsLifecycleQueueProvider =
    Provider<_LifecycleQueue>((Ref ref) => _LifecycleQueue());

/// Serialized lifecycle queue for [AutoMotionController].
final Provider<_LifecycleQueue> _autoMotionLifecycleQueueProvider =
    Provider<_LifecycleQueue>((Ref ref) => _LifecycleQueue());

/// Serializes asynchronous tracker lifecycle calls.
///
/// `start()` and `stop()` both mutate the *single shared* tracker instance, so
/// they must never overlap: a `stop()` that runs concurrently with the
/// `start()` that follows it tears the freshly-attached position stream back
/// down, leaving the stream detached while the tracker still reports `true`.
/// That is the "stuck at 0.00 km" failure. Chaining every call onto one future
/// makes the interleave impossible — each action runs strictly after the one
/// before it has fully settled.
class _LifecycleQueue {
  Future<void> _tail = Future<void>.value();

  /// Runs [action] once every previously queued action has settled. The
  /// returned future completes (or errors) with [action] alone, so callers can
  /// still await their own result.
  Future<void> add(Future<void> Function() action) {
    final Future<void> next = _tail.then((_) => action());
    // Keep the chain alive when an action throws: a failed start/stop must not
    // stall every later toggle.
    _tail = next.catchError((Object _) {});
    return next;
  }
}

// ---------------------------------------------------------------------------
// Notifiers
// ---------------------------------------------------------------------------

class PlacesNotifier extends AsyncNotifier<List<Place>> {
  @override
  Future<List<Place>> build() => ref.watch(placeRepositoryProvider).getAll();

  Future<void> save(Place place) async {
    await ref.read(placeRepositoryProvider).save(place);
    ref.read(appHealthLoggerProvider).log(HealthEventType.placeSaved);
    // Single funnel for every add/edit save path: no names, notes or
    // coordinates are sent (see AnalyticsService's privacy note).
    unawaited(
      ref
          .read(analyticsServiceProvider)
          .logEvent(AnalyticsEvents.placeSaved),
    );
    await _refresh();
  }

  Future<void> delete(String id) async {
    await ref.read(placeRepositoryProvider).delete(id);
    ref.read(appHealthLoggerProvider).log(HealthEventType.placeDeleted);
    await _refresh();
  }

  /// Toggles a place's "pinned to top" flag.
  Future<void> setPinned(String id, bool pinned) =>
      _mutate(id, (Place place) => place.copyWith(isPinned: pinned));

  /// Moves a place into (or out of) the Hidden Vault.
  Future<void> setHidden(String id, bool hidden) =>
      _mutate(id, (Place place) => place.copyWith(isHidden: hidden));

  /// Locks or unlocks a place (biometric-gated navigation/editing).
  Future<void> setLocked(String id, bool locked) =>
      _mutate(id, (Place place) => place.copyWith(isLocked: locked));

  Future<void> _mutate(String id, Place Function(Place) transform) async {
    final PlaceRepository repository = ref.read(placeRepositoryProvider);
    final Place? place = await repository.getById(id);
    if (place == null) return;
    await repository.save(transform(place));
    await _refresh();
  }

  /// Re-fetches after a Drive restore triggered elsewhere.
  Future<void> reload() async {
    state = const AsyncValue<List<Place>>.loading();
    state = await AsyncValue.guard<List<Place>>(
      () => ref.read(placeRepositoryProvider).getAll(),
    );
  }

  Future<void> _refresh() async {
    final List<Place> places = await ref.read(placeRepositoryProvider).getAll();
    state = AsyncValue<List<Place>>.data(places);
  }
}

class AuthNotifier extends AsyncNotifier<AuthUser?> {
  bool _validating = false;

  @override
  FutureOr<AuthUser?> build() {
    // Render the locally cached session synchronously so the first frame is the
    // Home screen, never a "Signing in..." loader. The silent sign-in below
    // then refreshes/validates the session in the background.
    final AuthUser? cached = _cachedUser(ref.read(settingsRepositoryProvider));

    // Kick off the silent validation without blocking the initial build.
    unawaited(_signInSilentlyInBackground());
    return cached;
  }

  /// The user we persisted on the last successful sign-in, if any.
  AuthUser? _cachedUser(SettingsRepository settings) {
    final Map<String, dynamic>? raw = settings.authUser;
    if (raw == null) return null;
    final Object? id = raw['id'];
    final Object? email = raw['email'];
    if (id is! String || email is! String) return null;
    return AuthUser(
      id: id,
      email: email,
      displayName: raw['displayName'] as String?,
      photoUrl: raw['photoUrl'] as String?,
    );
  }

  /// Restores the Google session and validates the Drive token *after* the
  /// provider has already surfaced the cached session to the UI.
  Future<void> _signInSilentlyInBackground() async {
    if (_validating) return;
    _validating = true;

    final AuthService auth = ref.read(authServiceProvider);
    final SettingsRepository settings = ref.read(settingsRepositoryProvider);
    try {
      final AuthUser? user = await auth.signInSilently();
      if (!ref.mounted) return;

      if (user != null) {
        await _persist(user);
        state = AsyncValue<AuthUser?>.data(user);
      } else if (settings.isLoggedIn) {
        // The account is genuinely gone: drop the stale cached session.
        await settings.saveAuthSession(null);
        if (!ref.mounted) return;
        state = const AsyncValue<AuthUser?>.data(null);
      }
    } catch (error, stackTrace) {
      // Offline or transient failure: keep the cached session so the UI stays
      // on the Home screen. Report a coarse, sanitized issue only when a real
      // session existed but could not be validated — otherwise a signed-out
      // user going offline would spam the log.
      if (settings.isLoggedIn) {
        AppLogger.log(
          category: 'AUTH',
          message: 'Silent sign-in restore failed',
          error: error,
          stackTrace: stackTrace,
        );
        ref
            .read(appObserverServiceProvider)
            .logIssue(
              category: AppIssueCategory.sync,
              error: error.toString(),
              stackTrace: stackTrace.toString(),
            );
      }
    } finally {
      _validating = false;
    }
  }

  Future<void> _persist(AuthUser user) async {
    await ref
        .read(settingsRepositoryProvider)
        .saveAuthSession(<String, dynamic>{
          'id': user.id,
          'email': user.email,
          'displayName': user.displayName,
          'photoUrl': user.photoUrl,
        });
  }

  Future<void> signIn() async {
    state = const AsyncValue<AuthUser?>.loading();
    state = await AsyncValue.guard<AuthUser?>(
      () => ref.read(authServiceProvider).signIn(),
    );
    final AuthUser? user = state.value;
    if (user != null) {
      await _persist(user);
    }
    final Object? error = state.error;
    if (error != null) {
      debugPrint('MapNote sign-in error: $error');
    }
  }

  Future<void> signOut() async {
    await ref.read(authServiceProvider).signOut();
    await ref.read(settingsRepositoryProvider).saveAuthSession(null);
    state = const AsyncValue<AuthUser?>.data(null);
  }
}

enum SyncStatus { idle, syncing, success, error, skipped }

class SyncState {
  const SyncState({
    this.status = SyncStatus.idle,
    this.lastSynced,
    this.outcome,
    this.error,
  });

  final SyncStatus status;
  final DateTime? lastSynced;
  final SyncOutcome? outcome;
  final String? error;

  bool get isSyncing => status == SyncStatus.syncing;

  SyncState copyWith({
    SyncStatus? status,
    DateTime? lastSynced,
    SyncOutcome? outcome,
    bool clearError = false,
  }) {
    return SyncState(
      status: status ?? this.status,
      lastSynced: lastSynced ?? this.lastSynced,
      outcome: outcome ?? this.outcome,
      error: clearError ? null : error,
    );
  }
}

class SyncController extends Notifier<SyncState> {
  @override
  SyncState build() {
    return SyncState(
      lastSynced: ref.watch(settingsRepositoryProvider).lastSynced,
    );
  }

  /// Performs the "device wins" sync, keeping the UI state in sync.
  Future<void> syncNow() async {
    final AppHealthLogger health = ref.read(appHealthLoggerProvider);
    health.log(HealthEventType.syncStarted);
    state = state.copyWith(status: SyncStatus.syncing, clearError: true);
    try {
      final SyncOutcome outcome = await ref
          .read(syncRepositoryProvider)
          .syncNow();
      health.log(
        outcome == SyncOutcome.skippedNotSignedIn
            ? HealthEventType.syncSkipped
            : HealthEventType.syncSucceeded,
        data: <String, Object?>{'outcome': outcome.name},
      );
      state = SyncState(
        status: outcome == SyncOutcome.skippedNotSignedIn
            ? SyncStatus.skipped
            : SyncStatus.success,
        outcome: outcome,
        lastSynced: ref.read(settingsRepositoryProvider).lastSynced,
      );
    } catch (e) {
      health.log(HealthEventType.syncFailed, message: e.toString());
      AppLogger.log(
        category: 'SYNC',
        message: 'Drive backup sync failed',
        error: e,
      );
      state = SyncState(
        status: SyncStatus.error,
        error: e.toString(),
        lastSynced: ref.read(settingsRepositoryProvider).lastSynced,
      );
    }
    // The restored list (if any) should refresh the UI.
    await ref.read(placesProvider.notifier).reload();
  }

  /// Silent sync for app lifecycle events (e.g. returning to the foreground).
  ///
  /// Skips when a sync is already running, and throttles to at most one sync
  /// per [silentSyncMinInterval] so quick app switches stay cheap and do not
  /// hammer the Drive API.
  Future<void> syncSilently() async {
    if (state.isSyncing) return;
    final DateTime? lastSynced = state.lastSynced;
    if (lastSynced != null &&
        DateTime.now().toUtc().difference(lastSynced) < silentSyncMinInterval) {
      return;
    }
    await syncNow();
  }

  static const Duration silentSyncMinInterval = Duration(minutes: 1);

  /// Downloads the Drive backup and replaces local data.
  Future<void> restoreFromDrive() async {
    final AppHealthLogger health = ref.read(appHealthLoggerProvider);
    health.log(
      HealthEventType.syncStarted,
      data: <String, Object?>{'kind': 'restore'},
    );
    state = state.copyWith(status: SyncStatus.syncing, clearError: true);
    try {
      await ref.read(syncRepositoryProvider).restoreFromDrive();
      health.log(
        HealthEventType.syncSucceeded,
        data: <String, Object?>{'kind': 'restore'},
      );
      state = SyncState(
        status: SyncStatus.success,
        outcome: SyncOutcome.restored,
        lastSynced: ref.read(settingsRepositoryProvider).lastSynced,
      );
    } catch (e) {
      health.log(HealthEventType.syncFailed, message: e.toString());
      AppLogger.log(
        category: 'SYNC',
        message: 'Restore from Drive failed',
        error: e,
      );
      state = SyncState(
        status: SyncStatus.error,
        error: e.toString(),
        lastSynced: ref.read(settingsRepositoryProvider).lastSynced,
      );
    }
    await ref.read(placesProvider.notifier).reload();
  }
}

/// Runs the monitoring & recommendation agent.
///
/// [build] returns local, rule-based insights synchronously so no spinner is
/// ever shown; cloud (Gemini) suggestions are merged in the background, and a
/// timer re-runs the agent periodically while the app stays open.
class AgentNotifier extends AsyncNotifier<List<AgentInsight>> {
  Timer? _timer;
  DateTime? _lastCloudAttempt;

  @override
  FutureOr<List<AgentInsight>> build() {
    // Subscribe to the data the agent reasons about so it re-evaluates when
    // places, session or language change.
    ref.watch(placesProvider);
    ref.watch(settingsRepositoryProvider);
    ref.watch(authProvider);
    final Locale? locale = ref.watch(localeControllerProvider);

    _timer?.cancel();
    _timer = Timer(AppConfig.agentRefreshInterval, () {
      if (ref.mounted) ref.invalidateSelf();
    });
    ref.onDispose(() => _timer?.cancel());

    final AgentContext context = _currentContext();
    final List<AgentInsight> local = _visibleLocals(context);
    unawaited(_mergeCloud(context, locale));
    return local;
  }

  /// Re-runs the agent immediately (used by the refresh button and on resume).
  Future<void> refresh() async {
    final AgentContext context = _currentContext();
    state = AsyncValue<List<AgentInsight>>.data(_visibleLocals(context));
    _lastCloudAttempt = null;
    await _mergeCloud(context, ref.read(localeControllerProvider));
  }

  /// Persists a dismissal and removes the insight from the current list.
  Future<void> dismiss(String id) async {
    await ref.read(settingsRepositoryProvider).dismissInsight(id);
    final List<AgentInsight> current = state.value ?? const <AgentInsight>[];
    state = AsyncValue<List<AgentInsight>>.data(
      current.where((AgentInsight i) => i.id != id).toList(growable: false),
    );
  }

  AgentContext _currentContext() {
    final List<Place> places =
        ref.read(placesProvider).value ?? const <Place>[];
    final AuthUser? user = ref.read(authProvider).value;
    final SettingsRepository settings = ref.read(settingsRepositoryProvider);
    return AgentContext(
      places: places,
      health: ref.read(appHealthLoggerProvider).summary(),
      lastSynced: settings.lastSynced,
      isSignedIn: user != null,
    );
  }

  List<AgentInsight> _visibleLocals(AgentContext context) {
    final List<String> dismissed = ref
        .read(settingsRepositoryProvider)
        .dismissedInsightIds;
    return ref
        .read(agentServiceProvider)
        .localInsights(context)
        .where((AgentInsight insight) => !dismissed.contains(insight.id))
        .take(AppConfig.maxAgentInsights)
        .toList(growable: false);
  }

  Future<void> _mergeCloud(AgentContext context, Locale? locale) async {
    final AgentService service = ref.read(agentServiceProvider);
    if (!service.isCloudAvailable) return;

    // Throttle so rebuilds (e.g. list edits) don't re-hit the network.
    final DateTime now = DateTime.now();
    final DateTime? last = _lastCloudAttempt;
    if (last != null && now.difference(last) < AppConfig.agentRefreshInterval) {
      return;
    }
    _lastCloudAttempt = now;

    final Locale effective = locale ?? const Locale('en');
    final List<AgentInsight> cloud = await service.cloudInsights(
      context,
      languageCode: effective.languageCode,
      languageName: _languageName(effective.languageCode),
    );
    if (!ref.mounted || cloud.isEmpty) return;

    final List<String> dismissed = ref
        .read(settingsRepositoryProvider)
        .dismissedInsightIds;
    final List<AgentInsight> current = state.value ?? const <AgentInsight>[];
    final Map<String, AgentInsight> byId = <String, AgentInsight>{
      for (final AgentInsight insight in current) insight.id: insight,
    };
    for (final AgentInsight insight in cloud) {
      if (!dismissed.contains(insight.id)) byId[insight.id] = insight;
    }
    final List<AgentInsight> merged = byId.values
        .take(AppConfig.maxAgentInsights)
        .toList(growable: false);
    // Avoid a redundant rebuild when the visible insight ids did not change.
    if (_sameIds(current, merged)) return;
    state = AsyncValue<List<AgentInsight>>.data(merged);
  }

  static bool _sameIds(List<AgentInsight> a, List<AgentInsight> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  static String _languageName(String code) {
    return switch (code) {
      'ar' => 'Arabic',
      _ => 'English',
    };
  }
}

/// Persists the cloud-AI preference and nudges the agent to re-run.
class CloudAiController extends Notifier<bool> {
  @override
  bool build() => ref.watch(settingsRepositoryProvider).isCloudAiEnabled;

  Future<void> setEnabled(bool enabled) async {
    await ref.read(settingsRepositoryProvider).setCloudAiEnabled(enabled);
    state = enabled;
    await ref.read(agentProvider.notifier).refresh();
  }
}

/// Persists the preferred navigation app choice.
class PreferredNavAppController extends Notifier<PreferredNavApp> {
  @override
  PreferredNavApp build() =>
      ref.watch(settingsRepositoryProvider).preferredNavApp;

  Future<void> setPreferredApp(PreferredNavApp app) async {
    await ref.read(settingsRepositoryProvider).setPreferredNavApp(app);
    state = app;
  }
}

/// Persists the Smart Insights visibility toggle.
class SmartInsightsController extends Notifier<bool> {
  @override
  bool build() => ref.watch(settingsRepositoryProvider).areSmartInsightsEnabled;

  Future<void> setEnabled(bool enabled) async {
    await ref.read(settingsRepositoryProvider).setSmartInsightsEnabled(enabled);
    state = enabled;
  }
}

class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() {
    final String? code = ref.watch(settingsRepositoryProvider).localeCode;
    if (code == null || code.isEmpty) return null;
    return Locale(code);
  }

  Future<void> setLocale(Locale? locale) async {
    await ref
        .read(settingsRepositoryProvider)
        .setLocaleCode(locale?.languageCode);
    state = locale;
  }
}

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final int? index = ref.watch(settingsRepositoryProvider).themeModeIndex;
    if (index == null || index < 0 || index >= ThemeMode.values.length) {
      return ThemeMode.system;
    }
    return ThemeMode.values[index];
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await ref.read(settingsRepositoryProvider).setThemeModeIndex(mode.index);
    state = mode;
  }
}

/// Exposes the device's location availability and drives the user to the right
/// OS surface when location access is missing.
class LocationStatusNotifier extends AsyncNotifier<LocationStatus> {
  @override
  Future<LocationStatus> build() => _read();

  Future<LocationStatus> _read() async {
    final LocationService service = ref.read(locationServiceProvider);
    final bool serviceEnabled = await service.isServiceEnabled();
    final LocationPermission permission = await service.checkPermission();
    return LocationStatus(
      serviceEnabled: serviceEnabled,
      permission: permission,
    );
  }

  /// Re-reads the status without flashing a loading state (used on resume).
  Future<void> refresh() async {
    try {
      state = AsyncValue<LocationStatus>.data(await _read());
    } catch (error, stackTrace) {
      state = AsyncValue<LocationStatus>.error(error, stackTrace);
    }
  }

  /// Sends the user to the right place to grant location access:
  /// - GPS switched off → the system location settings screen.
  /// - Permission permanently denied → this app's settings screen.
  /// - Otherwise → the runtime permission dialog.
  Future<void> requestAccessFromUser() async {
    final LocationService service = ref.read(locationServiceProvider);
    final LocationStatus? status = state.value;
    if (status != null) {
      if (!status.serviceEnabled) {
        await service.openLocationSettings();
      } else if (!status.permissionGranted) {
        if (status.permission == LocationPermission.deniedForever) {
          await service.openAppSettings();
        } else {
          await service.requestPermission();
        }
      }
    }
    await refresh();
  }
}

// ---------------------------------------------------------------------------
// Daily GPS tracking
// ---------------------------------------------------------------------------

/// Persists the Settings toggle for daily GPS tracking.
class GpsTrackingEnabledController extends Notifier<bool> {
  @override
  bool build() => ref.watch(settingsRepositoryProvider).isGpsTrackingEnabled;

  Future<void> setEnabled(bool value) async {
    await ref.read(settingsRepositoryProvider).setGpsTrackingEnabled(value);
    state = value;
  }
}

/// Immutable snapshot shown by the daily GPS summary tile.
class GpsTrackingState {
  const GpsTrackingState({
    required this.enabled,
    required this.active,
    required this.totalKm,
    required this.maxSpeedKmh,
    required this.currentSpeedKmh,
    required this.unavailable,
    this.failure = TrackStartFailure.none,
  });

  /// Whether the daily GPS toggle is currently on.
  final bool enabled;

  /// Whether the position stream is live right now.
  final bool active;

  /// Distance covered today, in kilometres.
  final double totalKm;

  /// Highest speed measured today, in km/h.
  final double maxSpeedKmh;

  /// Speed of the most recent fix, in km/h.
  final double currentSpeedKmh;

  /// True when tracking could not start (GPS off / permission denied).
  final bool unavailable;

  /// Why the last start attempt failed, or [TrackStartFailure.none].
  final TrackStartFailure failure;

  GpsTrackingState copyWith({
    bool? enabled,
    bool? active,
    double? totalKm,
    double? maxSpeedKmh,
    double? currentSpeedKmh,
    bool? unavailable,
    TrackStartFailure? failure,
  }) {
    return GpsTrackingState(
      enabled: enabled ?? this.enabled,
      active: active ?? this.active,
      totalKm: totalKm ?? this.totalKm,
      maxSpeedKmh: maxSpeedKmh ?? this.maxSpeedKmh,
      currentSpeedKmh: currentSpeedKmh ?? this.currentSpeedKmh,
      unavailable: unavailable ?? this.unavailable,
      failure: failure ?? this.failure,
    );
  }
}

/// Bridges the [GpsTrackerService] stream into a widget-friendly state.
///
/// [build] watches the enabled toggle and reconciles the tracker against it
/// through a single serialized queue, so flipping the toggle can never
/// interleave a `stop()` with the `start()` that follows it.
class GpsTrackingController extends Notifier<GpsTrackingState> {
  @override
  GpsTrackingState build() {
    final bool enabled = ref.watch(gpsTrackingEnabledProvider);
    final GpsTrackerService tracker = ref.read(gpsTrackerProvider);
    final _LifecycleQueue queue = ref.read(_gpsLifecycleQueueProvider);
    // Real-time readout: every accepted fix (and the midnight rollover) lands
    // here, so distance / max speed move while tracking instead of only when
    // the toggle is flipped.
    final StreamSubscription<void> updates = tracker.changes.listen((_) {
      if (!ref.mounted) return;
      state = _snapshot(
        tracker,
        enabled: enabled,
        active: tracker.isTracking,
      ).copyWith(unavailable: state.unavailable, failure: state.failure);
    });
    ref.onDispose(updates.cancel);
    // The orchestrator's profiles drive this tracker's stream too: the GPS
    // tracker is the *other* position consumer, and before this it ignored the
    // FSM entirely, so a parked phone kept a live GPS stream open. Routing both
    // trackers through [applyEngineProfile] keeps one authority.
    final StreamSubscription<EngineProfile> engineProfiles = ref
        .read(adaptiveEngineOrchestratorProvider)
        .profiles
        .listen((EngineProfile profile) {
      if (!ref.mounted) return;
      final GpsTrackerService watched = ref.read(gpsTrackerProvider);
      if (!watched.isTracking) return;
      unawaited(queue.add(() => applyEngineProfile(watched, profile)));
    });
    ref.onDispose(engineProfiles.cancel);
    // The transport classifier's verdicts are *evidence* for the FSM, not a
    // separate authority over the stream: feeding them to the orchestrator lets
    // it decide, and its profile is what reaches the tracker. Routing them
    // straight into `applySampling` (as this used to) would silently un-pause
    // an idle stream every time the classifier emitted, which is exactly the
    // background GPS drain the FSM exists to prevent.
    ref.listen<SamplingProfile>(
      adaptiveSamplingProvider,
      (SamplingProfile? previous, SamplingProfile next) {
        if (!ref.mounted || previous == next) return;
        final GpsTrackerService watched = ref.read(gpsTrackerProvider);
        if (!watched.isTracking) return;
        ref.read(adaptiveEngineOrchestratorProvider).observe(
              EngineEvidence(
                trackingActive: true,
                speedMps: watched.currentSpeedKmh / 3.6,
                speedFresh: true,
              ),
            );
        unawaited(
          queue.add(
            () => applyEngineProfile(
              watched,
              ref.read(adaptiveEngineOrchestratorProvider).profile,
            ),
          ),
        );
      },
    );
    // Start/stop is driven purely by the enabled flag and every action is
    // chained onto the shared queue. `build` re-runs on each toggle change, so
    // an on→off→on flick queues stop-then-start and the stop always finishes
    // before the start begins.
    unawaited(queue.add(() => _applyEnabled(tracker, enabled)));
    return _snapshot(tracker, enabled: enabled);
  }

  /// Starts the tracker (called when the toggle turns on or the app opens).
  Future<void> start() =>
      ref.read(_gpsLifecycleQueueProvider).add(
        () => _startNow(ref.read(gpsTrackerProvider)),
      );

  /// Stops the tracker and persists today's summary (toggle turned off).
  Future<void> stop() =>
      ref.read(_gpsLifecycleQueueProvider).add(
        () => _stopNow(ref.read(gpsTrackerProvider)),
      );

  /// Reconciles the live tracker with [enabled]; runs on the serialized queue.
  Future<void> _applyEnabled(GpsTrackerService tracker, bool enabled) =>
      enabled ? _startNow(tracker) : _stopNow(tracker);

  Future<void> _startNow(GpsTrackerService tracker) async {
    final bool started = await tracker.start(
      locations: ref.read(locationServiceProvider),
    );
    if (!ref.mounted) return;
    state = _snapshot(tracker, enabled: true, active: started)
        .copyWith(unavailable: !started, failure: tracker.failure);
    if (started) {
      // Tell the FSM a trip is live *before* the stream is opened, so the
      // orchestrator's first profile is the one that shapes it. Without this the
      // FSM still believes nothing is tracking and answers `idleStandby` for a
      // trip that is actually running.
      ref.read(adaptiveEngineOrchestratorProvider).observe(
            EngineEvidence(
              trackingActive: true,
              speedMps: tracker.currentSpeedKmh / 3.6,
              speedFresh: true,
            ),
          );
      await _startAdaptiveSampling(tracker);
    }
    await _syncForegroundTracking();
  }

  Future<void> _stopNow(GpsTrackerService tracker) async {
    await tracker.stop();
    if (!ref.mounted) return;
    // The trip is over: the FSM must not keep a driving profile (or a live
    // location stream) alive for a session that no longer exists.
    ref.read(adaptiveEngineOrchestratorProvider).suspend();
    state = _snapshot(tracker, enabled: false);
    await _syncAdaptiveStack();
    await _syncForegroundTracking();
  }

  /// Starts the shared sensor-driven sampling stack alongside the tracker and
  /// applies the orchestrator's current profile, so the stream opens at the
  /// right cadence from the very first fix.
  ///
  /// The orchestrator's profile — not the transport profile — is authoritative
  /// here: a device that is idle when tracking begins must open *paused*, and
  /// only the FSM knows that. The transport profile would open a live
  /// GPS-grade stream and leave it open until the FSM happened to transition.
  Future<void> _startAdaptiveSampling(GpsTrackerService tracker) async {
    await _syncAdaptiveStack();
    if (!ref.mounted) return;
    await applyEngineProfile(
      tracker,
      ref.read(adaptiveEngineOrchestratorProvider).profile,
    );
  }

  /// Runs the native foreground service for exactly as long as one of the two
  /// trackers is live, so backgrounding MapNote never freezes the counters.
  Future<void> _syncForegroundTracking() async {
    if (!ref.mounted) return;
    await syncTrackingForegroundService(
      ref.read(gpsTrackerProvider),
      ref.read(autoMotionServiceProvider),
      ref.read(foregroundTrackingServiceProvider),
    );
  }

  /// Runs the sensor-driven sampling stack for exactly as long as one of the
  /// two trackers is live (see [AdaptiveTrackingStack]): classifier verdicts
  /// and the battery poll keep the adaptive profile honest without keeping
  /// the accelerometer hardware on for an idle toggle.
  Future<void> _syncAdaptiveStack() async {
    if (!ref.mounted) return;
    await ref.read(adaptiveTrackingStackProvider).sync(
          needed: ref.read(gpsTrackerProvider).isTracking ||
              ref.read(autoMotionServiceProvider).isTracking,
          hub: ref.read(motionSensorHubProvider),
          classifier: ref.read(transportClassifierProvider),
          deadReckoning: ref.read(deadReckoningServiceProvider),
          sampling: ref.read(adaptiveSamplingProvider.notifier),
        );
  }

  GpsTrackingState _snapshot(
    GpsTrackerService tracker, {
    required bool enabled,
    bool active = false,
  }) {
    return GpsTrackingState(
      enabled: enabled,
      active: active,
      totalKm: tracker.totalDistanceKm,
      maxSpeedKmh: tracker.maxSpeedKmh,
      currentSpeedKmh: tracker.currentSpeedKmh,
      unavailable: false,
    );
  }
}

/// Brings the native foreground service in line with the live trackers: it
/// runs while either engine is recording and stops once both are off.
Future<void> syncTrackingForegroundService(
  GpsTrackerService gps,
  AutoMotionService motion,
  ForegroundTrackingService service,
) {
  return service.sync(needed: gps.isTracking || motion.isTracking);
}

/// Re-asserts the foreground service from the widget layer (app resume).
///
/// Android can refuse a foreground-service start while the app is backgrounded;
/// retrying as soon as MapNote is visible keeps long trips recording with the
/// screen off instead of silently degrading to in-app-only tracking.
Future<void> resyncTrackingForegroundService(WidgetRef ref) {
  return syncTrackingForegroundService(
    ref.read(gpsTrackerProvider),
    ref.read(autoMotionServiceProvider),
    ref.read(foregroundTrackingServiceProvider),
  );
}

/// Applies the tracking accuracy mode for MapNote's visibility to both daily
/// trackers: best available while the app is on screen, `balanced` while it is
/// backgrounded (see `LocationService.backgroundTrackingLocationSettings`), so
/// the receiver's duty cycle — and the battery — drops with the screen.
///
/// Each tracker flushes today's distance to Hive before re-opening its stream,
/// so a battery-optimisation kill immediately after backgrounding cannot drop
/// an already-accepted position. Both calls run on the trackers' own
/// serialized lifecycle queues, so a power-mode switch can never interleave
/// with a concurrent `start()`/`stop()`; a tracker that is not running simply
/// ignores the switch.
Future<void> applyTrackingPowerMode(
  WidgetRef ref, {
  required bool backgrounded,
}) async {
  final GpsTrackerService gps = ref.read(gpsTrackerProvider);
  final AutoMotionService motion = ref.read(autoMotionServiceProvider);
  await ref
      .read(_gpsLifecycleQueueProvider)
      .add(() => gps.setPowerMode(backgrounded: backgrounded));
  await ref
      .read(_autoMotionLifecycleQueueProvider)
      .add(() => motion.setPowerMode(backgrounded: backgrounded));
}

/// Applies an [EngineProfile] to a tracker's live stream.
///
/// The profile is the central FSM's decision about what the location subsystem
/// should be doing, so the three levers travel together and are translated in
/// exactly one place: the request interval, the movement filter, the accuracy
/// tier and — for `idleStandby` — the outright closure of the platform stream
/// (`paused`). Passing a profile through this helper is what keeps the
/// orchestrator's verdict authoritative over the coarser transport profile.
///
/// `transportSpeed` is derived from the state rather than hardcoded: only a
/// confirmed drive may lift the background accuracy cap to GPS grade (see
/// `GpsTrackerService._effectiveAccuracy`). A hardcoded `true` would hand out
/// GPS-grade fixes to a parked phone — the "frequently checks your location"
/// OS warning.
Future<void> applyEngineProfile(
  SamplingTarget tracker,
  EngineProfile profile,
) {
  return tracker.applySampling(
    interval: profile.locationInterval,
    accuracy: profile.accuracy,
    distanceFilter: profile.distanceFilterMeters,
    transportSpeed: profile.state == EngineState.activeDriveAnalytics,
    paused: profile.locationPaused,
  );
}

// ---------------------------------------------------------------------------
// AutoMotion
// ---------------------------------------------------------------------------

/// Persists the Settings toggle for AutoMotion.
class AutoMotionEnabledController extends Notifier<bool> {
  @override
  bool build() => ref.watch(settingsRepositoryProvider).isAutoMotionEnabled;

  Future<void> setEnabled(bool value) async {
    await ref.read(settingsRepositoryProvider).setAutoMotionEnabled(value);
    state = value;
  }
}

/// Immutable snapshot shown by the AutoMotion dashboard card.
class AutoMotionState {
  const AutoMotionState({
    required this.enabled,
    required this.active,
    required this.totalKm,
    required this.maxSpeedKmh,
    required this.currentSpeedKmh,
    required this.unavailable,
    this.failure = TrackStartFailure.none,
  });

  /// Whether the AutoMotion toggle is currently on.
  final bool enabled;

  /// Whether the position stream is live right now.
  final bool active;

  /// Distance recorded today, in kilometres.
  final double totalKm;

  /// Highest speed recorded today, in km/h.
  final double maxSpeedKmh;

  /// Speed of the most recent fix, in km/h.
  final double currentSpeedKmh;

  /// True when tracking could not start (GPS off / permission denied).
  final bool unavailable;

  /// Why the last start attempt failed, or [TrackStartFailure.none].
  final TrackStartFailure failure;

  AutoMotionState copyWith({
    bool? enabled,
    bool? active,
    double? totalKm,
    double? maxSpeedKmh,
    double? currentSpeedKmh,
    bool? unavailable,
    TrackStartFailure? failure,
  }) {
    return AutoMotionState(
      enabled: enabled ?? this.enabled,
      active: active ?? this.active,
      totalKm: totalKm ?? this.totalKm,
      maxSpeedKmh: maxSpeedKmh ?? this.maxSpeedKmh,
      currentSpeedKmh: currentSpeedKmh ?? this.currentSpeedKmh,
      unavailable: unavailable ?? this.unavailable,
      failure: failure ?? this.failure,
    );
  }
}

/// Maps a transport verdict onto the orchestrator's activity vocabulary.
///
/// A `vehicle` verdict is the only one that means "road vehicle"; a train is
/// deliberately **not** mapped to driving, because the maneuver classifier's
/// tires-and-road dynamics do not apply and the orchestrator's analytics would
/// be classifying rail joints as potholes. `stationary` and `walking` both map
/// to the gate's still/walking state, which is the honest description: neither
/// is worth paying for vehicle analytics.
ActivityState _activityFrom(TransportMode mode) {
  switch (mode) {
    case TransportMode.vehicle:
      return ActivityState.vehicleDriving;
    case TransportMode.stationary:
    case TransportMode.walking:
    case TransportMode.train:
      return ActivityState.stationaryOrWalking;
  }
}

/// Bridges the [AutoMotionService] stream into a widget-friendly state.
///
/// [build] watches the enabled toggle and reconciles the tracker against it
/// through a single serialized queue, so flipping the toggle can never
/// interleave a `stop()` with the `start()` that follows it.
class AutoMotionController extends Notifier<AutoMotionState> {
  @override
  AutoMotionState build() {
    final bool enabled = ref.watch(autoMotionEnabledProvider);
    final AutoMotionService tracker = ref.read(autoMotionServiceProvider);
    final _LifecycleQueue queue = ref.read(_autoMotionLifecycleQueueProvider);
    // Real-time readout: every accepted fix (and the midnight rollover) lands
    // here, so the dashboard / Settings numbers move while tracking.
    final StreamSubscription<void> updates = tracker.changes.listen((_) {
      if (!ref.mounted) return;
      state = _snapshot(
        tracker,
        enabled: enabled,
        active: tracker.isTracking,
      ).copyWith(unavailable: state.unavailable, failure: state.failure);
    });
    ref.onDispose(updates.cancel);
    // The transport classifier's verdicts gate the driving-behavior analyzer
    // to vehicle trips; a disposed controller must stop consuming them. (The
    // verdicts reach the adaptive sampling profile through the shared
    // [AdaptiveTrackingStack], which outlives this controller while either
    // tracker records.)
    final TransportClassifier classifier =
        ref.read(transportClassifierProvider);
    final MotionBehaviorAnalyzer analyzer =
        ref.read(motionBehaviorAnalyzerProvider);
    final StreamSubscription<TransportMode> modes =
        classifier.modes.listen((TransportMode mode) {
      if (!ref.mounted) return;
      analyzer.observeTransport(mode);
      // The same verdict drives the orchestrator's FSM: a vehicle trip is what
      // lifts the app out of low-power tracking into full analytics. The gate
      // itself judges from the raw accelerometer plus GPS speed, so this only
      // steers the *profile*, never the gate's own evidence.
      ref.read(adaptiveEngineOrchestratorProvider).observe(
            EngineEvidence(
              trackingActive: tracker.isTracking,
              activityState: _activityFrom(mode),
              speedMps: tracker.currentSpeedKmh / 3.6,
              speedFresh: true,
            ),
          );
    });
    ref.onDispose(modes.cancel);
    // Orchestrator-driven cadence: when the central FSM reaches a decisive
    // state (idle, driving, tunnel) its profile *overrides* the transport-driven
    // adaptive profile, because it knows more — it has the activity gate's
    // verdict and the fix age, not just a transport mode. Idle closes the
    // stream outright (the OS "frequently checks your location" warning),
    // driving tightens it to 1 s / 5 m at GPS grade to capture turns and
    // braking, and a tunnel keeps asking at a middle cadence without hammering
    // the radio.
    final StreamSubscription<EngineProfile> engineProfiles = ref
        .read(adaptiveEngineOrchestratorProvider)
        .profiles
        .listen((EngineProfile profile) {
      if (!ref.mounted) return;
      final AutoMotionService watched = ref.read(autoMotionServiceProvider);
      if (!watched.isTracking) return;
      unawaited(queue.add(() => applyEngineProfile(watched, profile)));
    });
    ref.onDispose(engineProfiles.cancel);
    // The transport classifier's verdicts are *evidence* for the FSM, not a
    // separate authority over the stream (see the GPS controller for the full
    // rationale): applying them directly would un-pause an idle stream every
    // time the classifier emitted.
    ref.listen<SamplingProfile>(
      adaptiveSamplingProvider,
      (SamplingProfile? previous, SamplingProfile next) {
        if (!ref.mounted || previous == next) return;
        final AutoMotionService watched = ref.read(autoMotionServiceProvider);
        if (!watched.isTracking) return;
        ref.read(adaptiveEngineOrchestratorProvider).observe(
              EngineEvidence(
                trackingActive: true,
                speedMps: watched.currentSpeedKmh / 3.6,
                speedFresh: true,
              ),
            );
        unawaited(
          queue.add(
            () => applyEngineProfile(
              watched,
              ref.read(adaptiveEngineOrchestratorProvider).profile,
            ),
          ),
        );
      },
    );
    // Start/stop is driven purely by the enabled flag and every action is
    // chained onto the shared queue, so an on→off→on flick can no longer race
    // a stray stop against the next start on the one shared tracker.
    unawaited(queue.add(() => _applyEnabled(tracker, enabled)));
    return _snapshot(tracker, enabled: enabled);
  }

  /// The gate's activity verdicts, while a trip records. Lives here rather than
  /// in a provider because it must be created and cancelled with the trip.
  StreamSubscription<ActivityState>? _gateStates;

  /// Translates one gate verdict into orchestrator evidence.
  ///
  /// The gate already rejects pedestrian gaits, so a `vehicleDriving` verdict is
  /// the strongest "we are in a car" signal the app has; everything else is
  /// still-or-walking. The GPS speed is attached so the FSM's own movement test
  /// has a fresh reading.
  void _onActivityState(ActivityState state) {
    if (!ref.mounted) return;
    final AutoMotionService tracker = ref.read(autoMotionServiceProvider);
    ref.read(adaptiveEngineOrchestratorProvider).observe(
          EngineEvidence(
            trackingActive: tracker.isTracking,
            activityState: state,
            speedMps: tracker.currentSpeedKmh / 3.6,
            speedFresh: true,
          ),
        );
  }

  /// Starts the tracker (called when the toggle turns on or the app opens).
  Future<void> start() =>
      ref.read(_autoMotionLifecycleQueueProvider).add(
        () => _startNow(ref.read(autoMotionServiceProvider)),
      );

  /// Reconciles the live tracker with [enabled]; runs on the serialized queue.
  Future<void> _applyEnabled(AutoMotionService tracker, bool enabled) =>
      enabled ? _startNow(tracker) : _idleNow(tracker);

  Future<void> _startNow(AutoMotionService tracker) async {
    // `_applyEnabled` re-runs on every rebuild and `tracker.start()`
    // short-circuits when it is already live, so the off→on transition is what
    // defines a trip: without this check `automotion_trip_started` would fire
    // on every rebuild while AutoMotion is enabled.
    final bool wasTracking = tracker.isTracking;
    final bool started = await tracker.start(
      locations: ref.read(locationServiceProvider),
    );
    if (!ref.mounted) return;
    if (started && !wasTracking) {
      // A new trip starts with a clean driving-event slate; the previous
      // trip's maneuvers already live in the local health log.
      ref.read(drivingEventsProvider.notifier).clear();
      // The classifier's window belongs to the trip too: carrying it over
      // would classify the parking-lot exit together with the last 2.56 s of
      // the previous trip.
      ref.read(mlClassifierIsolateProvider).clear();
      // Tell the FSM a trip is live before the stream is shaped, so its first
      // profile is the one applied (see the GPS controller's `_startNow`).
      ref.read(adaptiveEngineOrchestratorProvider).observe(
            EngineEvidence(
              trackingActive: true,
              speedMps: tracker.currentSpeedKmh / 3.6,
              speedFresh: true,
            ),
          );
      unawaited(
        ref
            .read(analyticsServiceProvider)
            .logEvent(AnalyticsEvents.autoMotionTripStarted),
      );
      await _startIntelligentTracking(tracker);
      if (!ref.mounted) return;
    }
    state = _snapshot(tracker, enabled: true, active: started).copyWith(
      unavailable: !started,
      failure: tracker.failure,
    );
    await _syncForegroundTracking();
  }

  /// Starts the AutoMotion-owned pieces of the sensor stack alongside the
  /// tracker — the driving-behavior analyzer watches the shared
  /// accelerometer feed for harsh maneuvers, and the on-device classifier
  /// buffers that same feed through its vehicle-frame alignment — then
  /// reconciles the shared sampling stack (transport classifier, dead
  /// reckoning, battery poll; see [AdaptiveTrackingStack]) and applies the
  /// current profile so the stream opens at the right cadence from the first
  /// fix.
  Future<void> _startIntelligentTracking(AutoMotionService tracker) async {
    final MotionBehaviorAnalyzer analyzer =
        ref.read(motionBehaviorAnalyzerProvider);
    // Instantiate the events notifier before the first fix can arrive, so
    // maneuvers are captured even while the dashboard is closed.
    ref.read(drivingEventsProvider.notifier);
    // Gate first: its gated stream is what both the analyzer and the classifier
    // subscribe to, so it must be open before they start listening or their
    // first samples would arrive through the raw hub and defeat the gate.
    final MotionGate gate = ref.read(motionGateProvider);
    gate.reset();
    await gate.start();
    // Feed the orchestrator the gate's *own* verdict — the authoritative
    // activity evidence — rather than the coarser transport classifier. The
    // gate sees the raw feed and the GPS speed, so its transitions are what
    // should open or close the location stream. Subscribed here (not in build)
    // because the gate only runs while a trip is recording; it is cancelled
    // with the trip in [_stopIntelligentTracking].
    _gateStates?.cancel();
    _gateStates = gate.manager.states.listen(_onActivityState);
    await analyzer.start();
    await ref.read(mlClassifierIsolateProvider).start();
    await _syncAdaptiveStack();
    if (!ref.mounted) return;
    await applyEngineProfile(
      tracker,
      ref.read(adaptiveEngineOrchestratorProvider).profile,
    );
  }

  /// Stops the AutoMotion-owned analyzer when tracking ends and reconciles
  /// the shared sampling stack, which releases the hardware feed and the
  /// battery poll once neither tracker records any more. The detected events
  /// themselves stay on show until the next trip resets them.
  Future<void> _stopIntelligentTracking() async {
    final MotionBehaviorAnalyzer analyzer =
        ref.read(motionBehaviorAnalyzerProvider);
    await _gateStates?.cancel();
    _gateStates = null;
    await analyzer.stop();
    await ref.read(mlClassifierIsolateProvider).stop();
    // Shut the gate too, so nothing keeps judging windows once no trip records.
    await ref.read(motionGateProvider).stop();
    ref.read(adaptiveEngineOrchestratorProvider).suspend();
    await _syncAdaptiveStack();
  }

  /// Called while AutoMotion is switched off. Persists anything still in
  /// memory (if the toggle was just turned off mid-session), then loads today's
  /// stored totals so the paused card still reflects the day's motion.
  Future<void> _idleNow(AutoMotionService tracker) async {
    // Mirror of the start guard: only a live→off transition is a trip end, so
    // the idle reconciliation that runs on every rebuild while AutoMotion is
    // switched off never emits a spurious `automotion_trip_ended`.
    final bool wasTracking = tracker.isTracking;
    await tracker.stop();
    await _stopIntelligentTracking();
    await tracker.resyncFromStore();
    if (!ref.mounted) return;
    if (wasTracking) {
      unawaited(
        ref
            .read(analyticsServiceProvider)
            .logEvent(AnalyticsEvents.autoMotionTripEnded),
      );
    }
    state = _snapshot(tracker, enabled: false);
    await _syncForegroundTracking();
  }

  /// Runs the native foreground service for exactly as long as one of the two
  /// trackers is live, so backgrounding MapNote never freezes the counters.
  Future<void> _syncForegroundTracking() async {
    if (!ref.mounted) return;
    await syncTrackingForegroundService(
      ref.read(gpsTrackerProvider),
      ref.read(autoMotionServiceProvider),
      ref.read(foregroundTrackingServiceProvider),
    );
  }

  /// Runs the sensor-driven sampling stack for exactly as long as one of the
  /// two trackers is live (see [AdaptiveTrackingStack]).
  Future<void> _syncAdaptiveStack() async {
    if (!ref.mounted) return;
    await ref.read(adaptiveTrackingStackProvider).sync(
          needed: ref.read(gpsTrackerProvider).isTracking ||
              ref.read(autoMotionServiceProvider).isTracking,
          hub: ref.read(motionSensorHubProvider),
          classifier: ref.read(transportClassifierProvider),
          deadReckoning: ref.read(deadReckoningServiceProvider),
          sampling: ref.read(adaptiveSamplingProvider.notifier),
        );
  }

  AutoMotionState _snapshot(
    AutoMotionService tracker, {
    required bool enabled,
    bool active = false,
  }) {
    return AutoMotionState(
      enabled: enabled,
      active: active,
      totalKm: tracker.totalDistanceKm,
      maxSpeedKmh: tracker.maxSpeedKmh,
      currentSpeedKmh: tracker.currentSpeedKmh,
      unavailable: false,
    );
  }
}

// ---------------------------------------------------------------------------
// Driving events & route path
// ---------------------------------------------------------------------------

/// Fires after every accepted AutoMotion fix (and the midnight rollover).
///
/// The dashboard's trip-route card watches this purely as a repaint trigger:
/// the path itself is read from `autoMotionServiceProvider.smoothedPath`.
/// Each notification carries an incrementing tick because Riverpod's
/// `AsyncData<void>` states all compare equal — a bare `StreamProvider<void>`
/// would notify dependents only once (the very first event, from the
/// controller's idle reconcile) and the card would then never repaint, no
/// matter how many fixes arrived.
final StreamProvider<int> autoMotionFixesProvider = StreamProvider<int>((
  Ref ref,
) {
  int tick = 0;
  return ref.watch(autoMotionServiceProvider).changes.map((_) => tick++);
});

// ---------------------------------------------------------------------------
// Route map & milestones (AutoMotion dashboard)
// ---------------------------------------------------------------------------

/// The day's route distilled into timeline milestones (start, sustained
/// stops, end), recomputed whenever a fix lands.
///
/// Derived, not stored: the source of truth stays `AutoMotionService`'s
/// smoothed path, so this provider adds no Hive schema. Watching
/// [autoMotionFixesProvider] is what re-runs the detection on every accepted
/// fix and on the midnight rollover.
final Provider<List<RouteMilestone>> routeMilestonesProvider =
    Provider<List<RouteMilestone>>((Ref ref) {
      ref.watch(autoMotionFixesProvider);
      return detectMilestones(
        ref.read(autoMotionServiceProvider).smoothedPath,
      );
    });

/// Session-scoped reverse-geocode cache backing [routeMilestoneNamesProvider].
final Provider<MilestoneNameResolver> milestoneNameResolverProvider =
    Provider<MilestoneNameResolver>(
      (Ref ref) =>
          MilestoneNameResolver(geocoding: ref.watch(geocodingServiceProvider)),
    );

/// Resolved place names for the current route's milestones, keyed by
/// [RouteMilestone.coordinateKey].
///
/// Absent keys mean "not resolved yet (or ever — offline)" and the timeline
/// renders the milestone's kind label instead; names upgrade in place as the
/// geocoder answers. Resolution is kicked off by this notifier itself, so the
/// widget layer stays declarative and a cache hit rebuilds synchronously with
/// no loading flicker.
final NotifierProvider<RouteMilestoneNames, Map<String, String?>>
routeMilestoneNamesProvider =
    NotifierProvider<RouteMilestoneNames, Map<String, String?>>(
      RouteMilestoneNames.new,
    );

/// Watches the milestones and fills the name map from the resolver cache,
/// requesting whatever is still missing (deduplicated, serialised, and
/// negative-cached by the resolver itself).
class RouteMilestoneNames extends Notifier<Map<String, String?>> {
  @override
  Map<String, String?> build() {
    final List<RouteMilestone> milestones = ref.watch(routeMilestonesProvider);
    final MilestoneNameResolver resolver = ref.read(
      milestoneNameResolverProvider,
    );
    final Map<String, String?> known = resolver.cached(milestones);
    final List<RouteMilestone> missing = <RouteMilestone>[
      for (final RouteMilestone milestone in milestones)
        if (!known.containsKey(milestone.coordinateKey)) milestone,
    ];
    if (missing.isNotEmpty) {
      unawaited(
        resolver.resolve(missing).then((_) {
          if (!ref.mounted) return;
          // Re-read the *current* milestones: more fixes may have arrived
          // while the geocoder was answering.
          state = resolver.cached(ref.read(routeMilestonesProvider));
        }),
      );
    }
    return known;
  }
}

/// One [MapController] shared by the route map and its tests — fitting the
/// camera is imperative, so the widget and the assertions must agree on the
/// instance.
final Provider<MapController> routeMapControllerProvider =
    Provider<MapController>((Ref ref) {
      final MapController controller = MapController();
      ref.onDispose(controller.dispose);
      return controller;
    });

/// The route map's tile source. The default fetches OpenStreetMap raster
/// tiles; tests override it so no test ever reaches the network (the offline
/// fallback path is asserted through the same override).
final Provider<TileProvider> routeTileProviderProvider =
    Provider<TileProvider>((Ref ref) => NetworkTileProvider());

/// Detected maneuvers (hard braking / harsh acceleration from the speed
/// timeline, plus classified turns and road-surface events) so far in the
/// current trip, oldest-first — a mirror of the analyzer's own history.
final NotifierProvider<DrivingEventsNotifier, List<DrivingEvent>>
    drivingEventsProvider =
        NotifierProvider<DrivingEventsNotifier, List<DrivingEvent>>(
  DrivingEventsNotifier.new,
);

/// Bridges [MotionBehaviorAnalyzer.onEvent] into widget-friendly state.
///
/// The subscription lives here (not in the UI) so maneuvers are captured even
/// while the dashboard is closed; every event is also mirrored into the
/// privacy-safe local health log (kind + magnitude + duration only — never a
/// location). [clear] starts a new trip's slate and is driven by
/// `AutoMotionController` the moment a trip begins.
class DrivingEventsNotifier extends Notifier<List<DrivingEvent>> {
  @override
  List<DrivingEvent> build() {
    final MotionBehaviorAnalyzer analyzer =
        ref.read(motionBehaviorAnalyzerProvider);
    final StreamSubscription<DrivingEvent> detected =
        analyzer.onEvent.listen((DrivingEvent event) {
      if (!ref.mounted) return;
      // The analyzer adds the event to its own list before emitting, so this
      // keeps one source of truth instead of appending twice.
      ref.read(appHealthLoggerProvider).log(
        HealthEventType.drivingManeuver,
        data: <String, Object?>{
          'maneuver': event.type.name,
          'peak_mps2': event.peakMps2,
          'duration_ms': event.duration.inMilliseconds,
        },
      );
      state = List<DrivingEvent>.unmodifiable(analyzer.events);
    });
    ref.onDispose(detected.cancel);
    return List<DrivingEvent>.unmodifiable(analyzer.events);
  }

  /// Resets the trip's slate: the analyzer discards its events, armed
  /// windows and sensor windows, and the exposed list empties with it.
  void clear() {
    ref.read(motionBehaviorAnalyzerProvider).reset();
    state = const <DrivingEvent>[];
  }
}

// ---------------------------------------------------------------------------
// AutoMotion history
// ---------------------------------------------------------------------------

/// AutoMotion's recorded days, newest-first, for the dashboard trip history.
///
/// Re-reads the Hive box whenever the tracker reports an accepted fix (and at
/// the midnight rollover), so today's row tracks the live totals and a new row
/// appears the moment a day rolls over — without reopening the screen.
class AutoMotionHistoryController extends Notifier<List<DailyGpsSummary>> {
  @override
  List<DailyGpsSummary> build() {
    final AutoMotionService tracker = ref.watch(autoMotionServiceProvider);
    final AutoMotionDataSource store = ref.watch(autoMotionDataSourceProvider);
    final StreamSubscription<void> updates = tracker.changes.listen((_) {
      if (!ref.mounted) return;
      state = store.all();
    });
    ref.onDispose(updates.cancel);
    return store.all();
  }
}
