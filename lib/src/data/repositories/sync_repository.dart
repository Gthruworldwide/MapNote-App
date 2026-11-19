import '../local/settings_repository.dart';
import '../models/backup_data.dart';
import '../models/backup_validator.dart';
import '../models/place.dart';
import '../remote/auth_service.dart';
import '../remote/drive_service.dart';
import '../services/sync_merge.dart';
import 'place_repository.dart';

/// Result of a sync attempt.
enum SyncOutcome {
  /// No Google account, nothing was (could be) done.
  skippedNotSignedIn,

  /// Local data was uploaded because no backup existed yet.
  uploaded,

  /// A backup was merged into an empty device.
  restored,

  /// Local and cloud records were merged and the result was backed up.
  merged,

  /// Some records need a user decision before the merge can be backed up.
  conflictsDetected,
}

/// Full result of a sync attempt, including records that need a decision.
class SyncExecution {
  const SyncExecution(this.outcome, this.merge);

  final SyncOutcome outcome;
  final SyncMergeResult? merge;

  bool get hasConflicts => merge?.hasConflicts ?? false;
}

/// Orchestrates the local database <-> Google Drive backup flows.
///
/// The device is still the offline source of truth, but a non-empty local
/// database no longer overwrites a backup wholesale. Both sides are merged per
/// record using edit time, revision counter and tombstones. Only a clean merge
/// is uploaded; a conflicting merge stays local until the user resolves it.
class SyncRepository {
  SyncRepository({
    required PlaceRepository placeRepository,
    required DriveService driveService,
    required SettingsRepository settingsRepository,
    required AuthService authService,
  })   : _places = placeRepository,
        _drive = driveService,
        _settings = settingsRepository,
        _auth = authService;

  final PlaceRepository _places;
  final DriveService _drive;
  final SettingsRepository _settings;
  final AuthService _auth;

  final SyncMerger _merger = const SyncMerger();

  /// Backwards-compatible entry point used by the automatic sync callers.
  Future<SyncOutcome> syncNow() async => (await synchronize()).outcome;

  /// Merges the local database with the single Drive backup.
  ///
  /// Exactly one bounded download is performed. All external input is strictly
  /// validated (including the v2 checksum) before any Hive write. The local
  /// record set is captured before the download and re-checked inside the write
  /// critical section, so a place saved while the network was busy is never
  /// lost.
  Future<SyncExecution> synchronize() async {
    if (!_auth.isSignedIn) {
      return const SyncExecution(SyncOutcome.skippedNotSignedIn, null);
    }

    final List<Place> local = await _places.getAllIncludingDeleted();
    final Set<String> baselineIds = local.map((Place place) => place.id).toSet();
    final String? raw = await _drive.downloadBackup();
    if (raw == null || raw.isEmpty) {
      await backupToDrive();
      return const SyncExecution(SyncOutcome.uploaded, null);
    }

    final BackupEnvelope envelope = parseBackupEnvelope(raw);
    final SyncMergeResult merge = _merger.merge(
      local: local,
      cloud: envelope.places,
    );
    await _places.applyMerged(
      resolved: merge.places,
      baselineIds: baselineIds,
    );

    if (merge.hasConflicts) {
      // Do not upload or stamp trust evidence while a decision is pending:
      // the backup must never claim a state the user has not confirmed.
      return SyncExecution(SyncOutcome.conflictsDetected, merge);
    }

    await _upload(merge.places);
    return SyncExecution(SyncOutcome.merged, merge);
  }

  /// Explicit restore from Drive. It also merges, so a user who added places
  /// since the backup was made never loses them.
  Future<SyncExecution> restore() async {
    final SyncExecution execution = await synchronize();
    if (execution.outcome == SyncOutcome.uploaded) {
      return const SyncExecution(SyncOutcome.restored, null);
    }
    return execution;
  }

  /// Serialises the local database into a versioned, checksummed v2 envelope
  /// and overwrites the Drive backup. Used by the headless backup job and by
  /// conflict resolution after the user has decided.
  Future<void> backupToDrive() async {
    final List<Place> local = await _places.getAllIncludingDeleted();
    await _upload(local);
  }

  /// Number of places restored, kept for the existing UI call sites.
  Future<int> restoreFromDrive() async {
    final SyncExecution execution = await restore();
    return execution.merge?.places.length ?? 0;
  }

  /// Imports a manual `.mapnote` payload without ever clearing local data.
  ///
  /// The same strict parser (including the checksum) and the same record-level
  /// merger are used as for Drive. Conflicts are returned to the UI instead of
  /// being resolved silently. This path is fully offline: nothing is uploaded.
  Future<SyncExecution> importRecoveryBackup(String raw) async {
    final BackupEnvelope envelope = parseBackupEnvelope(raw);
    final List<Place> local = await _places.getAllIncludingDeleted();
    final Set<String> baselineIds = local.map((Place place) => place.id).toSet();
    final SyncMergeResult merge = _merger.merge(
      local: local,
      cloud: envelope.places,
    );
    await _places.applyMerged(
      resolved: merge.places,
      baselineIds: baselineIds,
    );
    return SyncExecution(
      merge.hasConflicts ? SyncOutcome.conflictsDetected : SyncOutcome.merged,
      merge,
    );
  }

  /// Applies the user's decision for one conflict, then backs up the clean
  /// result. [resolve] is supplied by the caller so this layer stays pure.
  Future<SyncExecution> resolveConflict(
    SyncConflict conflict,
    SyncResolution resolution, {
    required Place Function(SyncConflict, SyncResolution) resolve,
  }) async {
    final Place decided = resolve(conflict, resolution);
    final List<Place> records = (await _places.getAllIncludingDeleted()).map(
      (Place place) => place.id == conflict.placeId ? decided : place,
    ).toList();
    final Set<String> ids = records.map((Place place) => place.id).toSet();
    await _places.applyMerged(resolved: records, baselineIds: ids);

    final List<Place> local = await _places.getAllIncludingDeleted();
    final SyncMergeResult remaining = _merger.merge(local: local, cloud: local);
    if (remaining.hasConflicts) {
      return SyncExecution(SyncOutcome.conflictsDetected, remaining);
    }
    await _upload(local);
    return SyncExecution(SyncOutcome.merged, remaining);
  }

  Future<void> _upload(Iterable<Place> places) async {
    final DateTime now = DateTime.now().toUtc();
    final BackupData data = BackupData(lastSynced: now, places: places.toList());
    await _drive.uploadBackup(data.toRaw());
    // Trust evidence is stamped only after a successful Drive round-trip.
    await _settings.setLastSynced(now);
  }
}
