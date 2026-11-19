import '../../core/utils/plus_code.dart';

/// A saved location. This is the core domain entity of MapNote.
///
/// The JSON shape matches the documented backup format:
/// ```json
/// {
///   "id": "uuid-v4-string",
///   "name": "Target Name",
///   "notes": "Optional details",
///   "latitude": 30.12345,
///   "longitude": 31.12345,
///   "timestamp": "2026-10-09T15:30:00Z",
///   "isPinned": false,
///   "isHidden": false,
///   "isLocked": false,
///   "isVaulted": false
/// }
/// ```
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.notes,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.isPinned = false,
    this.isHidden = false,
    this.isLocked = false,
    this.isVaulted = false,
    this.updatedAt,
    this.syncVersion = 0,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String notes;
  final double latitude;
  final double longitude;

  /// Creation time, stored in UTC.
  final DateTime timestamp;

  /// Pinned places are kept at the top of the home list.
  final bool isPinned;

  /// Hidden places are removed from the home list and only appear inside the
  /// biometric-protected "Hidden Vault" in Settings.
  final bool isHidden;

  /// Locked places require biometric/device-credential verification before
  /// navigating or editing.
  final bool isLocked;

  /// Vaulted places are kept in the encrypted vault store.
  final bool isVaulted;

  /// Last local modification time (UTC). Legacy rows have no value; their
  /// [timestamp] is used as the effective revision time.
  final DateTime? updatedAt;

  /// Monotonically increasing local revision counter. It breaks ties when two
  /// devices edit a record within the same millisecond.
  final int syncVersion;

  /// Soft-delete marker (UTC). A deleted record is retained so the deletion can
  /// be merged across devices instead of silently resurrecting the place.
  final DateTime? deletedAt;

  /// True when this record is a tombstone and must be hidden from the user.
  bool get isDeleted => deletedAt != null;

  /// Revision time used by the sync merger. Never null, even for legacy rows.
  DateTime get effectiveUpdatedAt => (updatedAt ?? timestamp).toUtc();

  /// Returns a copy stamped as a local edit. The caller must not mutate a
  /// record in place: Hive rows are immutable maps.
  Place withLocalEdit({DateTime? now}) {
    final DateTime stamp = (now ?? DateTime.now()).toUtc();
    return copyWith(
      updatedAt: stamp,
      deletedAt: null,
      syncVersion: syncVersion + 1,
    );
  }

  /// Returns a copy stamped as a local soft delete.
  Place withLocalDelete({DateTime? now}) {
    final DateTime stamp = (now ?? DateTime.now()).toUtc();
    return copyWith(
      updatedAt: stamp,
      deletedAt: stamp,
      syncVersion: syncVersion + 1,
    );
  }

  Place copyWith({
    String? id,
    String? name,
    String? notes,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    bool? isPinned,
    bool? isHidden,
    bool? isLocked,
    bool? isVaulted,
    DateTime? updatedAt,
    int? syncVersion,
    DateTime? deletedAt,
    bool clearUpdatedAt = false,
    bool clearDeletedAt = false,
  }) {
    return Place(
      id: id ?? this.id,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      isPinned: isPinned ?? this.isPinned,
      isHidden: isHidden ?? this.isHidden,
      isLocked: isLocked ?? this.isLocked,
      isVaulted: isVaulted ?? this.isVaulted,
      updatedAt: clearUpdatedAt ? null : (updatedAt ?? this.updatedAt),
      syncVersion: syncVersion ?? this.syncVersion,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }

  /// A compact single-line label used to preview coordinates.
  String get formattedCoordinates =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  /// The global Open Location Code (a.k.a. "Plus Code") for these coordinates,
  /// e.g. `8FVC9G8F+6W`.
  ///
  /// Derived on demand so it can never drift from [latitude]/[longitude].
  String get plusCode => PlusCode.encode(latitude, longitude);

  /// A universal Google Maps link that opens the location in any maps app.
  String get mapsLink =>
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'notes': notes,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'isPinned': isPinned,
      'isHidden': isHidden,
      'isLocked': isLocked,
      'isVaulted': isVaulted,
      'updatedAt': updatedAt?.toUtc().toIso8601String(),
      'syncVersion': syncVersion,
      'deletedAt': deletedAt?.toUtc().toIso8601String(),
    };
  }

  /// Exported shape (Drive backup). The stored [toMap] keeps only the source of
  /// truth; the Plus Code is added here so exports carry it without it ever
  /// becoming a stale stored copy.
  Map<String, dynamic> toJson() => <String, dynamic>{
    ...toMap(),
    'plusCode': plusCode,
    'isVaulted': isVaulted,
  };

  factory Place.fromMap(Map<String, dynamic> map) {
    return Place(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      notes: map['notes']?.toString() ?? '',
      latitude: _toDouble(map['latitude']),
      longitude: _toDouble(map['longitude']),
      timestamp: _toDateTime(map['timestamp']),
      isPinned: _toBool(map['isPinned']),
      isHidden: _toBool(map['isHidden']),
      isLocked: _toBool(map['isLocked']),
      isVaulted: _toBool(map['isVaulted']),
      updatedAt: _toOptionalDateTime(map['updatedAt']),
      syncVersion: _toRevision(map['syncVersion']),
      deletedAt: _toOptionalDateTime(map['deletedAt']),
    );
  }

  factory Place.fromJson(Map<String, dynamic> json) => Place.fromMap(json);

  static double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static bool _toBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  static DateTime _toDateTime(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) {
      return DateTime.tryParse(value)?.toUtc() ?? DateTime.now().toUtc();
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    return DateTime.now().toUtc();
  }

  /// Optional timestamps degrade to null rather than to "now": inventing a
  /// revision time for a legacy row would let it win a merge against a real
  /// edit. [effectiveUpdatedAt] supplies the creation time as the fallback.
  static DateTime? _toOptionalDateTime(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    if (value is num && value.isFinite) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    return null;
  }

  static int _toRevision(Object? value) {
    if (value is int && value >= 0) return value;
    if (value is num && value.isFinite && value >= 0) return value.toInt();
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      other is Place &&
      other.id == id &&
      other.name == name &&
      other.notes == notes &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.timestamp == timestamp &&
      other.isPinned == isPinned &&
      other.isHidden == isHidden &&
      other.isLocked == isLocked &&
      other.isVaulted == isVaulted &&
      other.updatedAt == updatedAt &&
      other.syncVersion == syncVersion &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    notes,
    latitude,
    longitude,
    timestamp,
    isPinned,
    isHidden,
    isLocked,
    isVaulted,
    updatedAt,
    syncVersion,
    deletedAt,
  );

  @override
  String toString() =>
      'Place($id, $name, $latitude, $longitude, '
      'pinned: $isPinned, hidden: $isHidden, locked: $isLocked, vaulted: $isVaulted, '
      'rev: $syncVersion, deleted: $isDeleted)';
}
