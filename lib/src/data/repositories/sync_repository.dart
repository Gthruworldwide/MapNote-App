import 'dart:convert';

import '../local/place_local_data_source.dart';
import '../local/settings_repository.dart';
import '../models/backup_data.dart';
import '../models/backup_validator.dart';
import '../models/place.dart';
import '../remote/auth_service.dart';
import '../remote/drive_service.dart';
import 'place_repository.dart';

/// Result of a sync attempt.
enum SyncOutcome {
  /// No Google account, nothing was (and could be) done.
  skippedNotSignedIn,

  /// Local data overwrote the Drive backup (the WhatsApp model: device wins).
  uploaded,

  /// Device was empty, the Drive backup was restored into local storage.
  restored,
}

/// Orchestrates the local database <-> Google Drive backup flows.
///
/// Policy (matches the product spec):
/// * On launch: if the device has data it *overrides* the Drive backup.
/// * On a fresh device (empty local DB) with an existing backup, the backup is
///   restored into the local database.
/// * There is exactly one JSON file in the Drive app-data folder.
class SyncRepository {
  SyncRepository({
    required PlaceRepository placeRepository,
    required DriveService driveService,
    required SettingsRepository settingsRepository,
    required AuthService authService,
  }) : _places = placeRepository,
       _drive = driveService,
       _settings = settingsRepository,
       _auth = authService;

  final PlaceRepository _places;
  final DriveService _drive;
  final SettingsRepository _settings;
  final AuthService _auth;

  /// Runs the "sync on open" flow described above.
  Future<SyncOutcome> syncNow() async {
    if (!_auth.isSignedIn) return SyncOutcome.skippedNotSignedIn;

    final List<Place> local = await _places.getAll();
    if (local.isNotEmpty) {
      await backupToDrive();
      return SyncOutcome.uploaded;
    }

    // One download only. The local-empty precondition is re-checked inside
    // applyBackup, after every await, so a place saved while the network was
    // busy is never erased by a stale decision.
    final _RestoreApplication application = await _downloadAndApply(
      baselineIds: const <String>{},
      requireEmptyLocal: true,
    );
    if (application.result == RestoreApplyResult.applied) {
      await _stampLocalSyncEvidence();
      return SyncOutcome.restored;
    }

    // Local data appeared mid-download: the device wins and gets backed up.
    await backupToDrive();
    return SyncOutcome.uploaded;
  }

  /// Serializes the local database to JSON and overwrites the Drive backup.
  Future<void> backupToDrive() async {
    final List<Place> local = await _places.getAll();
    final DateTime now = DateTime.now().toUtc();
    final BackupData data = BackupData(lastSynced: now, places: local);
    await _drive.uploadBackup(jsonEncode(data.toJson()));
    await _settings.setLastSynced(now);
  }

  /// Downloads, validates and applies a Drive backup. Returns the number of
  /// restored places. Existing content is only replaced by an explicitly
  /// confirmed restore, and concurrent additions are preserved.
  Future<int> restoreFromDrive() async {
    final Set<String> baseline =
        (await _places.getAll()).map((Place place) => place.id).toSet();
    final _RestoreApplication application = await _downloadAndApply(
      baselineIds: baseline,
      requireEmptyLocal: false,
    );
    if (application.result == RestoreApplyResult.applied) {
      await _stampLocalSyncEvidence();
    }
    return application.places.length;
  }

  Future<_RestoreApplication> _downloadAndApply({
    required Set<String> baselineIds,
    required bool requireEmptyLocal,
  }) async {
    final String? raw = await _drive.downloadBackup();
    if (raw == null || raw.isEmpty) {
      return _RestoreApplication(const <Place>[], null);
    }

    // Strict external-input validation happens before any Hive write. The
    // backup's own `last_synced` is ignored: it is attacker-controlled and must
    // never become session-trust evidence.
    final List<Place> places = parseBackup(raw);
    final RestoreApplyResult result = await _places.applyBackup(
      backupPlaces: places,
      baselineIds: baselineIds,
      requireEmptyLocal: requireEmptyLocal,
    );
    return _RestoreApplication(places, result);
  }

  Future<void> _stampLocalSyncEvidence() =>
      _settings.setLastSynced(DateTime.now().toUtc());
}

class _RestoreApplication {
  const _RestoreApplication(this.places, this.result);

  final List<Place> places;
  final RestoreApplyResult? result;
}
