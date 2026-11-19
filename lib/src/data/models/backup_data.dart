import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'place.dart';

/// Stable names and version for the on-disk / Drive backup envelope.
///
/// The envelope is shared by Google Drive sync and the manual `.mapnote`
/// recovery file. Keeping the keys here (rather than string-duplicated in the
/// parser and the writer) means a new field cannot be written by one side and
/// rejected by the other.
class BackupFormat {
  const BackupFormat._();

  /// v1 had only `last_synced` and `places`. v2 adds a schema marker, a
  /// checksum and per-record sync metadata (revision, version, tombstone).
  static const int schemaVersion = 2;

  static const String schemaVersionKey = 'schema_version';
  static const String checksumKey = 'checksum';
  static const String lastSyncedKey = 'last_synced';
  static const String placesKey = 'places';
  static const String recoveryFileExtension = 'mapnote';

  /// Canonical bytes covered by [checksum].
  ///
  /// `last_synced` is deliberately excluded: it is local evidence, re-stamped
  /// by [SettingsRepository] after a successful round-trip, and must never
  /// become trust evidence just because a remote file claimed it.
  static List<int> canonicalBytes(Iterable<Place> places) => utf8.encode(
        jsonEncode(<String, Object>{
          schemaVersionKey: schemaVersion,
          placesKey: places.map((Place place) => place.toJson()).toList(),
        }),
      );

  static String checksum(Iterable<Place> places) =>
      sha256.convert(canonicalBytes(places)).toString();
}

/// The serialised payload uploaded to Google Drive and written to a
/// `.mapnote` recovery file.
///
/// ```json
/// {
///   "schema_version": 2,
///   "checksum": "<sha256 of the canonical payload>",
///   "last_synced": "2026-10-09T00:00:00Z",
///   "places": [ ... ]
/// }
/// ```
class BackupData {
  const BackupData({
    required this.places,
    this.lastSynced,
    this.schemaVersion = BackupFormat.schemaVersion,
    this.checksum,
  });

  final DateTime? lastSynced;
  final List<Place> places;
  final int schemaVersion;

  /// Hex SHA-256 of the canonical payload. Null only for a legacy v1 record.
  final String? checksum;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      BackupFormat.schemaVersionKey: schemaVersion,
      BackupFormat.checksumKey: checksum ?? BackupFormat.checksum(places),
      BackupFormat.lastSyncedKey: lastSynced?.toUtc().toIso8601String(),
      BackupFormat.placesKey: places.map((Place place) => place.toJson()).toList(),
    };
  }

  String toRaw() => jsonEncode(toJson());

  factory BackupData.fromJson(Map<String, dynamic> json) {
    final Object? rawPlaces = json[BackupFormat.placesKey];
    final List<Place> places = <Place>[];
    if (rawPlaces is List) {
      for (final Object? item in rawPlaces) {
        if (item is Map) {
          places.add(Place.fromMap(Map<String, dynamic>.from(item)));
        }
      }
    }
    return BackupData(
      places: places,
      lastSynced: _parseDate(json[BackupFormat.lastSyncedKey]),
      schemaVersion: json[BackupFormat.schemaVersionKey] is int
          ? json[BackupFormat.schemaVersionKey] as int
          : 1,
      checksum: json[BackupFormat.checksumKey]?.toString(),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    if (value is num && value.isFinite) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    return null;
  }
}
