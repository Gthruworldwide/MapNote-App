import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../core/config/app_config.dart';
import '../data/local/hive_database.dart';
import '../data/local/place_local_data_source.dart';
import '../data/local/settings_repository.dart';
import '../data/remote/auth_service.dart';
import '../data/remote/google_auth_service.dart';
import '../data/remote/drive_service.dart';
import '../data/repositories/place_repository.dart';
import '../data/repositories/sync_repository.dart';

/// Top-level entry point invoked by the OS in a *separate background isolate*.
///
/// This must stay a top-level function annotated with `@pragma('vm:entry-point')`
/// so the VM keeps it reachable from native code. It re-initialises Hive and
/// builds the dependency graph manually (no provider scope exists here).
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((
    String taskName,
    Map<String, dynamic>? inputData,
  ) async {
    try {
      await Hive.initFlutter();
      final HiveDatabase database = HiveDatabase(
        placesBox: await Hive.openBox<dynamic>(AppConfig.placesBoxName),
        settingsBox: await Hive.openBox<dynamic>(AppConfig.settingsBoxName),
      );

      final AuthService auth = GoogleAuthService();
      await auth.initialize();

      // Gate the silent restore on a *persisted* session. There is no UI to
      // drive from a headless isolate, and on Android
      // `attemptLightweightAuthentication()` is routed through Credential
      // Manager, which is allowed to launch its chooser. Signed-out means there
      // is nothing to restore *and* nothing to back up, so skip before the
      // attempt rather than after it (AGENT_SKILLS §2.1: restore is silent and
      // only re-establishes a session that already existed).
      final SettingsRepository settings = SettingsRepository(
        database.settingsBox,
      );
      if (!settings.isLoggedIn) return true; // Nothing to do offline.

      await auth.signInSilently();
      if (!auth.isSignedIn) return true; // Session could not be restored.

      final SyncRepository sync = SyncRepository(
        placeRepository: PlaceRepository(PlaceLocalDataSource(database)),
        driveService: GoogleDriveService(auth),
        settingsRepository: settings,
        authService: auth,
      );
      await sync.backupToDrive();
      return true;
    } catch (_) {
      return false;
    }
  });
}

/// Schedules the periodic midnight-style backup with `workmanager`.
class BackgroundSyncScheduler {
  const BackgroundSyncScheduler();

  /// Must be called from `main()` once. Wrapped in try/catch because
  /// `workmanager` is a no-op / throws on unsupported platforms.
  Future<void> initialize() async {
    try {
      await Workmanager().initialize(backgroundSyncDispatcher);
    } catch (_) {
      // Background sync is best-effort and not available on every platform.
    }
  }

  /// Registers a 24h periodic task aligned to the next midnight.
  Future<void> schedulePeriodicBackup() async {
    try {
      await Workmanager().registerPeriodicTask(
        AppConfig.backgroundSyncUniqueName,
        AppConfig.backgroundSyncUniqueName,
        frequency: AppConfig.backgroundSyncFrequency,
        initialDelay: _untilNextMidnight(),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<void> cancel() async {
    try {
      await Workmanager().cancelByUniqueName(
        AppConfig.backgroundSyncUniqueName,
      );
    } catch (_) {
      // Best-effort only.
    }
  }

  Duration _untilNextMidnight() {
    final DateTime now = DateTime.now();
    final DateTime nextMidnight = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1));
    return nextMidnight.difference(now);
  }
}
