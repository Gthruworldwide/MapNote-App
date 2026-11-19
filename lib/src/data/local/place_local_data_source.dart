import '../models/place.dart';
import 'hive_database.dart';

/// Outcome of applying a validated backup after its download.
enum RestoreApplyResult {
  /// The validated backup was written to Hive.
  applied,

  /// Local data appeared while the download was in flight; the automatic
  /// restore precondition no longer holds and nothing was written.
  abortedLocalNotEmpty,
}

/// Local persistence for [Place] records. All reads/writes go through Hive,
/// making the app fully offline-first.
class PlaceLocalDataSource {
  PlaceLocalDataSource(this._database);

  final HiveDatabase _database;

  /// Returns active places, newest first. Tombstones are retained in Hive for
  /// sync but never shown to the user.
  Future<List<Place>> getAll() async {
    final List<Place> places = (await getAllIncludingDeleted())
        .where((Place place) => !place.isDeleted)
        .toList();
    return places;
  }

  /// Returns every record, including tombstones. Only the sync layer may use
  /// this: a deleted place must stay hidden everywhere else.
  Future<List<Place>> getAllIncludingDeleted() async {
    final List<Place> places = _database.placesBox.values
        .whereType<Map>()
        .map((Map raw) => Place.fromMap(Map<String, dynamic>.from(raw)))
        .toList();
    places.sort((Place a, Place b) => b.effectiveUpdatedAt.compareTo(a.effectiveUpdatedAt));
    return places;
  }

  Future<Place?> getById(String id) async {
    final Object? raw = _database.placesBox.get(id);
    if (raw is Map) return Place.fromMap(Map<String, dynamic>.from(raw));
    return null;
  }

  /// Inserts or updates a place (keyed by its id).
  ///
  /// The Hive box is explicitly [flush]ed afterwards: `put` alone only
  /// commits to Hive's in-memory cache and writes the file back lazily, so a
  /// force-stop or crash right after a lock/unlock could silently revert
  /// `place.isLocked` on the next launch. Flushing pins the change to disk.
  Future<void> put(Place place) async {
    await _database.placesBox.put(place.id, place.toMap());
    await _database.placesBox.flush();
  }

  /// Soft delete: keeps a tombstone so the deletion can merge across devices
  /// instead of the place being resurrected by an older backup.
  Future<void> delete(String id) async {
    final Place? place = await getById(id);
    if (place == null) return;
    await put(place.withLocalDelete());
  }

  /// Permanent removal of a tombstone. Not exposed in the UI: it would allow a
  /// stale backup to resurrect the record on the next sync.
  Future<void> purge(String id) async {
    await _database.placesBox.delete(id);
    await _database.placesBox.flush();
  }

  /// Legacy full replace. New restore paths use [applyBackup], which re-checks
  /// the local-empty precondition and preserves places added during download.
  Future<void> replaceAll(Iterable<Place> places) async {
    final Map<String, Map<String, dynamic>> entries =
        <String, Map<String, dynamic>>{
          for (final Place place in places) place.id: place.toMap(),
        };
    await _database.placesBox.clear();
    await _database.placesBox.putAll(entries);
    await _database.placesBox.flush();
  }

  /// Applies [backupPlaces] after the network download has completed.
  ///
  /// The precondition is checked against the box immediately before the write.
  /// From the first synchronous read to the `putAll` enqueue there is no
  /// `await`, so no other save can interleave on this isolate. Places created
  /// after [baselineIds] was captured are merged back instead of being erased.
  Future<RestoreApplyResult> applyBackup({
    required Iterable<Place> backupPlaces,
    required Set<String> baselineIds,
    required bool requireEmptyLocal,
  }) async {
    final box = _database.placesBox;
    final Set<String> currentIds = box.keys.whereType<String>().toSet();
    if (requireEmptyLocal && currentIds.isNotEmpty) {
      return RestoreApplyResult.abortedLocalNotEmpty;
    }

    final Map<String, Map<String, dynamic>> entries =
        <String, Map<String, dynamic>>{
          for (final Place place in backupPlaces) place.id: place.toMap(),
        };

    // Preserve rows added by the user while the backup was being downloaded.
    for (final String id in currentIds.difference(baselineIds)) {
      final Object? raw = box.get(id);
      if (raw is Map) {
        entries[id] = Map<String, dynamic>.from(raw);
      }
    }

    final Set<String> stale = baselineIds.difference(entries.keys.toSet());

    // Put first, delete second: a crash between them leaves stale rows rather
    // than losing anything the user added. Both calls are enqueued without an
    // await so the whole critical section is one Hive write batch.
    if (entries.isNotEmpty) {
      box.putAll(entries);
    }
    if (stale.isNotEmpty) {
      box.deleteAll(stale);
    }
    await box.flush();
    return RestoreApplyResult.applied;
  }

  /// Writes a record-level merge result after a network download.
  ///
  /// Like [applyBackup], the precondition and the write share one synchronous
  /// critical section, so a place saved while the download was in flight is
  /// preserved. Unlike the legacy path, nothing is hard-deleted: removals are
  /// represented by tombstones inside [resolved].
  Future<void> applyMerged({
    required Iterable<Place> resolved,
    required Set<String> baselineIds,
  }) async {
    final box = _database.placesBox;
    final Set<String> currentIds = box.keys.whereType<String>().toSet();
    final Map<String, Map<String, dynamic>> entries =
        <String, Map<String, dynamic>>{
          for (final Place place in resolved) place.id: place.toMap(),
        };

    for (final String id in currentIds.difference(baselineIds)) {
      final Object? raw = box.get(id);
      if (raw is Map) {
        entries.putIfAbsent(id, () => Map<String, dynamic>.from(raw));
      }
    }

    if (entries.isNotEmpty) {
      box.putAll(entries);
    }
    await box.flush();
  }
}
