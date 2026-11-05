import '../../core/utils/plus_code.dart';
import 'station_manager.dart';

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
    this.contactId,
    this.displayName,
    this.phoneNumber,
    this.hasDriveThru,
    this.speedLimitZone,
    this.category,
    this.isDefault,
    this.isCustom,
    this.managers = const <StationManager>[],
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
  final bool isVaulted;

  /// Indicates if this place has a drive-thru (e.g., fast food, coffee).
  /// Used for auto-motion classification and route optimization.
  final bool? hasDriveThru;

  /// Speed limit zone associated with this place (in km/h).
  /// Used for motion analytics and speed-based filtering.
  final int? speedLimitZone;

  /// Category classification for the place (e.g., 'gas_station', 'restaurant', 'home').
  /// Enables grouped filtering and localized labels.
  final String? category;

  /// Lightweight contact association metadata stored locally in Hive.
  /// When non-null, this place has a linked contact from the system address book.
  final String? contactId;
  final String? displayName;
  final String? phoneNumber;

  /// Indicates if this place was part of the default seed data (first launch).
  /// Default stations are pre-loaded from `assets/data/stations.json`; user-
  /// added or modified stations are flagged `isCustom: true` and never
  /// overwritten by subsequent seed runs.
  final bool? isDefault;

  /// Indicates if this place has been modified by the user (is not a default seed).
  /// Preserving `isCustom: true` ensures user edits survive seed re-runs and
  /// sync cycles. A place that is neither default nor custom is transient.
  final bool? isCustom;

  /// The station manager(s) shipped with the seeded catalogue, in the order the
  /// station sheet lists them (primary first). Empty for user-created places and
  /// for seeded stations whose manager could not be matched with certainty.
  ///
  /// A station may legitimately have two or three managers, so this is a list
  /// rather than a single name: the detail screen shows one contact row each,
  /// and a phone number can be added per manager without a schema change.
  final List<StationManager> managers;

  /// The primary manager's name, or null when none is known.
  String? get managerName =>
      managers.isEmpty ? null : managers.first.name;

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
    bool? hasDriveThru,
    int? speedLimitZone,
    String? category,
    String? contactId,
    String? displayName,
    String? phoneNumber,
    bool? isDefault,
    bool? isCustom,
    List<StationManager>? managers,
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
      hasDriveThru: hasDriveThru ?? this.hasDriveThru,
      speedLimitZone: speedLimitZone ?? this.speedLimitZone,
      category: category ?? this.category,
      contactId: contactId ?? this.contactId,
      displayName: displayName ?? this.displayName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isDefault: isDefault ?? this.isDefault,
      isCustom: isCustom ?? this.isCustom,
      managers: managers ?? this.managers,
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
      'hasDriveThru': hasDriveThru,
      'speedLimitZone': speedLimitZone,
      'category': category,
      'contactId': contactId,
      'displayName': displayName,
      'phoneNumber': phoneNumber,
      'isDefault': isDefault,
      'isCustom': isCustom,
      if (managers.isNotEmpty)
        'managers':
            managers.map((StationManager m) => m.toMap()).toList(growable: false),
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
      hasDriveThru: map['hasDriveThru'] != null ? map['hasDriveThru'].toString().toUpperCase() == 'TRUE' : null,
      speedLimitZone: map['speedLimitZone'] != null ? _toInt(map['speedLimitZone']) : null,
      category: map['category']?.toString(),
      contactId: map['contactId']?.toString(),
      displayName: map['displayName']?.toString(),
      phoneNumber: map['phoneNumber']?.toString(),
      isDefault: map['isDefault'] != null ? map['isDefault'] == true : null,
      isCustom: map['isCustom'] != null ? map['isCustom'] == true : null,
      managers: _toManagers(map['managers']),
    );
  }

  /// Parses the stored manager list, dropping malformed or nameless entries.
  ///
  /// Older records have no `managers` key at all, so anything that is not a
  /// list degrades to empty rather than throwing on read.
  static List<StationManager> _toManagers(Object? value) {
    if (value is! List) return const <StationManager>[];
    final List<StationManager> managers = <StationManager>[];
    for (final Object? entry in value) {
      if (entry is! Map) continue;
      final StationManager manager =
          StationManager.fromMap(Map<String, dynamic>.from(entry));
      if (manager.name.isEmpty) continue;
      managers.add(manager);
    }
    return List<StationManager>.unmodifiable(managers);
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

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
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
      other.hasDriveThru == hasDriveThru &&
      other.speedLimitZone == speedLimitZone &&
      other.category == category &&
      other.isDefault == isDefault &&
      other.isCustom == isCustom &&
      other.contactId == contactId &&
      other.displayName == displayName &&
      other.phoneNumber == phoneNumber &&
      _sameManagers(other.managers);

  /// Element-wise comparison; [List] has identity equality by default, so two
  /// places with the same managers must not compare unequal.
  bool _sameManagers(List<StationManager> other) {
    if (other.length != managers.length) return false;
    for (int i = 0; i < managers.length; i++) {
      if (managers[i] != other[i]) return false;
    }
    return true;
  }

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
    hasDriveThru,
    speedLimitZone,
    category,
    isDefault,
    isCustom,
    contactId,
    displayName,
    phoneNumber,
    Object.hashAll(managers),
  );

  @override
  String toString() =>
      'Place($id, $name, $latitude, $longitude, '
      'pinned: $isPinned, hidden: $isHidden, locked: $isLocked, vaulted: $isVaulted, contactId: $contactId, displayName: $displayName, hasDriveThru: $hasDriveThru, speedLimitZone: $speedLimitZone, isDefault: $isDefault, isCustom: $isCustom, managers: $managers)';
}
