import '../local/place_local_data_source.dart';
import '../models/place.dart';

/// Application-level persistence operations for places.
class PlaceRepository {
  PlaceRepository(this._local);

  final PlaceLocalDataSource _local;

  Future<List<Place>> getAll() => _local.getAll();

  /// Includes tombstones. Only the sync/recovery layer may call this.
  Future<List<Place>> getAllIncludingDeleted() => _local.getAllIncludingDeleted();

  Future<Place?> getById(String id) => _local.getById(id);

  /// Raw upsert, used by import/restore and tests. User edits should go through
  /// [saveLocalEdit] so they carry a fresh revision for conflict resolution.
  Future<void> save(Place place) => _local.put(place);

  Future<void> saveLocalEdit(Place place, {DateTime? now}) =>
      _local.put(place.withLocalEdit(now: now));

  Future<void> delete(String id) => _local.delete(id);

  Future<void> replaceAll(Iterable<Place> places) => _local.replaceAll(places);

  Future<RestoreApplyResult> applyBackup({
    required Iterable<Place> backupPlaces,
    required Set<String> baselineIds,
    required bool requireEmptyLocal,
  }) =>
      _local.applyBackup(
        backupPlaces: backupPlaces,
        baselineIds: baselineIds,
        requireEmptyLocal: requireEmptyLocal,
      );

  Future<void> applyMerged({
    required Iterable<Place> resolved,
    required Set<String> baselineIds,
  }) =>
      _local.applyMerged(resolved: resolved, baselineIds: baselineIds);
}
