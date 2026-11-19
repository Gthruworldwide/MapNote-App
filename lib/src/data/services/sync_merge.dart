import '../models/place.dart';

/// How a conflicting record is resolved by the user.
enum SyncResolution {
  /// Keep the device copy and discard the cloud copy for this record.
  keepLocal,

  /// Use the cloud copy and discard the device copy for this record.
  useCloud,

  /// Keep one record but take non-empty fields from both sides.
  merge,
}

/// Two edits to the same place that cannot be ordered safely.
class SyncConflict {
  const SyncConflict(this.placeId, this.local, this.cloud);

  final String placeId;
  final Place local;
  final Place cloud;
}

/// The resolved record set plus any records that need a user decision.
class SyncMergeResult {
  const SyncMergeResult({
    required this.places,
    required this.conflicts,
  });

  /// All records, including tombstones. Callers filter tombstones for display.
  final List<Place> places;

  final List<SyncConflict> conflicts;

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// Deterministic, record-level three-way-ish merge for Drive backups.
///
/// The app has no shared ancestor revision, so ordering is by effective edit
/// time, then by the per-record monotonic version. A tie with different content
/// is a genuine conflict and is surfaced to the UI rather than silently
/// resolved. Tombstones participate in the same ordering, so a deletion on one
/// device is never undone by a stale copy on another.
class SyncMerger {
  const SyncMerger();

  SyncMergeResult merge({
    required Iterable<Place> local,
    required Iterable<Place> cloud,
  }) {
    final Map<String, Place> localById = <String, Place>{
      for (final Place place in local) place.id: place,
    };
    final Map<String, Place> cloudById = <String, Place>{
      for (final Place place in cloud) place.id: place,
    };
    final Set<String> ids = <String>{...localById.keys, ...cloudById.keys};

    final Map<String, Place> resolved = <String, Place>{};
    final List<SyncConflict> conflicts = <SyncConflict>[];

    for (final String id in ids) {
      final Place? device = localById[id];
      final Place? remote = cloudById[id];

      if (device == null) {
        resolved[id] = remote!;
        continue;
      }
      if (remote == null) {
        resolved[id] = device;
        continue;
      }
      if (_sameContent(device, remote)) {
        resolved[id] = _compare(device, remote) >= 0 ? device : remote;
        continue;
      }

      final int order = _compare(device, remote);
      if (order > 0) {
        resolved[id] = device;
      } else if (order < 0) {
        resolved[id] = remote;
      } else if (device.isDeleted || remote.isDeleted) {
        // Prefer the deletion on a tie: resurrecting a private place is worse
        // than losing duplicate content that is still available on one device.
        resolved[id] = device.isDeleted ? device : remote;
      } else {
        conflicts.add(SyncConflict(id, device, remote));
        // Keep the device copy until the user decides; never overwrite silently.
        resolved[id] = device;
      }
    }

    final List<Place> ordered = resolved.values.toList()
      ..sort((Place a, Place b) => b.effectiveUpdatedAt.compareTo(a.effectiveUpdatedAt));
    return SyncMergeResult(places: ordered, conflicts: conflicts);
  }

  /// Applies a user choice to one conflict. The result is stamped as a fresh
  /// local edit so it wins the next merge deterministically.
  Place resolve(
    SyncConflict conflict,
    SyncResolution choice, {
    DateTime? now,
  }) {
    switch (choice) {
      case SyncResolution.keepLocal:
        return conflict.local.withLocalEdit(now: now);
      case SyncResolution.useCloud:
        return conflict.cloud.withLocalEdit(now: now);
      case SyncResolution.merge:
        final Place base = _compare(conflict.local, conflict.cloud) >= 0
            ? conflict.local
            : conflict.cloud;
        final Place other = identical(base, conflict.local)
            ? conflict.cloud
            : conflict.local;
        final String notes = _mergeNotes(base.notes, other.notes);
        return base.copyWith(
          notes: notes,
          updatedAt: (now ?? DateTime.now()).toUtc(),
          syncVersion: base.syncVersion + 1,
          deletedAt: null,
        );
    }
  }

  int _compare(Place a, Place b) {
    final int byTime = a.effectiveUpdatedAt.compareTo(b.effectiveUpdatedAt);
    if (byTime != 0) return byTime;
    return a.syncVersion.compareTo(b.syncVersion);
  }

  bool _sameContent(Place a, Place b) =>
      a.name == b.name &&
      a.notes == b.notes &&
      a.latitude == b.latitude &&
      a.longitude == b.longitude &&
      a.isPinned == b.isPinned &&
      a.isHidden == b.isHidden &&
      a.isLocked == b.isLocked &&
      a.isVaulted == b.isVaulted &&
      a.deletedAt == b.deletedAt;

  String _mergeNotes(String a, String b) {
    if (a.isEmpty) return b;
    if (b.isEmpty || a == b) return a;
    return '$a\n$b';
  }
}
