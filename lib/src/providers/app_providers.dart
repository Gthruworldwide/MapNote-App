import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../data/local/hive_database.dart';
import '../data/local/place_local_data_source.dart';
import '../data/local/settings_repository.dart';
import '../data/models/agent_insight.dart';
import '../data/models/place.dart';
import '../data/remote/auth_service.dart';
import '../data/remote/drive_service.dart';
import '../data/remote/google_auth_service.dart';
import '../data/repositories/place_repository.dart';
import '../data/repositories/sync_repository.dart';
import '../core/config/app_config.dart';
import '../core/config/preferred_nav_app.dart';
import '../services/agent_service.dart';
import '../services/app_health_logger.dart';
import '../services/app_logger.dart';
import '../services/app_observer_service.dart';
import '../services/background_sync_scheduler.dart';
import '../services/biometric_service.dart';
import '../services/dynamic_icon_service.dart';
import '../services/gemini_client.dart';
import '../services/home_shortcut_service.dart';
import '../services/local_insight_engine.dart';
import '../services/location_service.dart';
import '../services/navigation_service.dart';
import '../services/share_intent_service.dart';

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

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

final Provider<LocationService> locationServiceProvider =
    Provider<LocationService>((Ref ref) => const LocationService());

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

/// Pure, offline rule engine.
final Provider<LocalInsightEngine> localInsightEngineProvider =
    Provider<LocalInsightEngine>((Ref ref) => const LocalInsightEngine());

/// Optional Gemini client (only active when an API key is configured).
final Provider<GeminiClient> geminiClientProvider = Provider<GeminiClient>((
  Ref ref,
) {
  final GeminiClient client = GeminiClient();
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

// ---------------------------------------------------------------------------
// Notifiers
// ---------------------------------------------------------------------------

class PlacesNotifier extends AsyncNotifier<List<Place>> {
  @override
  Future<List<Place>> build() => ref.watch(placeRepositoryProvider).getAll();

  Future<void> save(Place place) async {
    await ref.read(placeRepositoryProvider).save(place);
    ref.read(appHealthLoggerProvider).log(HealthEventType.placeSaved);
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
      debugPrint('RouteNote sign-in error: $error');
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
