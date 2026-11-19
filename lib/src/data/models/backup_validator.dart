import 'dart:convert';

import '../../core/config/app_config.dart';
import 'backup_data.dart';
import 'place.dart';

/// Opaque validation failure for a downloaded backup.
///
/// The [code] is a fixed identifier: neither it nor [toString] ever includes a
/// field value, so a malformed or hostile payload cannot put private data into
/// logs through an exception message.
class BackupValidationException implements Exception {
  const BackupValidationException(this.code);

  static const String tooLarge = 'backup_too_large';
  static const String tooDeep = 'backup_too_deep';
  static const String malformed = 'backup_malformed';
  static const String wrongRoot = 'backup_wrong_root';
  static const String unknownKey = 'backup_unknown_key';
  static const String wrongPlaces = 'backup_wrong_places';
  static const String tooManyPlaces = 'backup_too_many_places';
  static const String badId = 'backup_bad_id';
  static const String duplicateId = 'backup_duplicate_id';
  static const String badName = 'backup_bad_name';
  static const String badNotes = 'backup_bad_notes';
  static const String badCoordinate = 'backup_bad_coordinate';
  static const String badTimestamp = 'backup_bad_timestamp';
  static const String badFlag = 'backup_bad_flag';
  static const String badPlusCode = 'backup_bad_plus_code';
  static const String unsupportedSchema = 'backup_unsupported_schema';
  static const String badChecksum = 'backup_bad_checksum';
  static const String badRevision = 'backup_bad_revision';

  final String code;

  @override
  String toString() => 'BackupValidationException($code)';
}

const Set<String> _rootKeys = <String>{
  BackupFormat.schemaVersionKey,
  BackupFormat.checksumKey,
  BackupFormat.lastSyncedKey,
  BackupFormat.placesKey,
};

const Set<String> _placeKeys = <String>{
  'id',
  'name',
  'notes',
  'latitude',
  'longitude',
  'timestamp',
  'isPinned',
  'isHidden',
  'isLocked',
  'isVaulted',
  'plusCode',
  'updatedAt',
  'syncVersion',
  'deletedAt',
};

/// A strictly parsed backup envelope. [schemaVersion] is 1 for a legacy file
/// without a version marker, otherwise the declared version.
class BackupEnvelope {
  const BackupEnvelope({
    required this.places,
    required this.schemaVersion,
    required this.hasChecksum,
  });

  final List<Place> places;
  final int schemaVersion;
  final bool hasChecksum;
}

final RegExp _safeId = RegExp(r'^[A-Za-z0-9._-]+$');

/// Strictly parses a downloaded Drive backup into [Place] records.
///
/// This is deliberately separate from [Place.fromMap], which must keep
/// coercing legacy Hive rows. A backup is external input: unknown keys, wrong
/// types, non-finite numbers, duplicate ids and impossible timestamps are all
/// rejected before any destructive local write can happen.
///
/// `last_synced` is accepted for older clients but **ignored**: only a
/// successful local apply may stamp it, via `SettingsRepository`.
List<Place> parseBackup(
  String raw, {
  DateTime Function()? now,
}) =>
    parseBackupEnvelope(raw, now: now).places;

/// Strict parser that also returns envelope metadata needed by the sync
/// merger. See [parseBackup] for the validation contract.
BackupEnvelope parseBackupEnvelope(
  String raw, {
  DateTime Function()? now,
}) {
  if (raw.length > AppConfig.maxBackupBytes) {
    throw const BackupValidationException(BackupValidationException.tooLarge);
  }
  if (_jsonDepth(raw) > AppConfig.maxBackupJsonDepth) {
    throw const BackupValidationException(BackupValidationException.tooDeep);
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw const BackupValidationException(BackupValidationException.malformed);
  }
  if (decoded is! Map) {
    throw const BackupValidationException(BackupValidationException.wrongRoot);
  }

  final Map<String, dynamic> root;
  try {
    root = Map<String, dynamic>.from(decoded);
  } on TypeError {
    throw const BackupValidationException(BackupValidationException.wrongRoot);
  }
  for (final String key in root.keys) {
    if (!_rootKeys.contains(key)) {
      throw const BackupValidationException(BackupValidationException.unknownKey);
    }
  }

  final int schemaVersion = _readSchemaVersion(root[BackupFormat.schemaVersionKey]);
  final Object? rawChecksum = root[BackupFormat.checksumKey];
  if (rawChecksum != null && rawChecksum is! String) {
    throw const BackupValidationException(BackupValidationException.badChecksum);
  }
  if (schemaVersion >= 2 && rawChecksum == null) {
    throw const BackupValidationException(BackupValidationException.badChecksum);
  }

  final Object? rawPlaces = root[BackupFormat.placesKey];
  if (rawPlaces is! List) {
    throw const BackupValidationException(BackupValidationException.wrongPlaces);
  }
  if (rawPlaces.length > AppConfig.maxBackupPlaces) {
    throw const BackupValidationException(
      BackupValidationException.tooManyPlaces,
    );
  }

  final DateTime nowUtc = (now ?? DateTime.now)().toUtc();
  final DateTime maxTimestamp = nowUtc.add(AppConfig.maxBackupTimestampSkew);
  final Set<String> seenIds = <String>{};
  final List<Place> places = <Place>[];

  for (final Object? item in rawPlaces) {
    if (item is! Map) {
      throw const BackupValidationException(
        BackupValidationException.wrongPlaces,
      );
    }
    final Map<String, dynamic> record;
    try {
      record = Map<String, dynamic>.from(item);
    } on TypeError {
      throw const BackupValidationException(
        BackupValidationException.wrongPlaces,
      );
    }
    for (final String key in record.keys) {
      if (!_placeKeys.contains(key)) {
        throw const BackupValidationException(
          BackupValidationException.unknownKey,
        );
      }
    }

    final String id = _readId(record['id']);
    if (!seenIds.add(id)) {
      throw const BackupValidationException(
        BackupValidationException.duplicateId,
      );
    }

    final Object? name = record['name'];
    if (name is! String || name.length > AppConfig.maxPlaceNameLength) {
      throw const BackupValidationException(BackupValidationException.badName);
    }
    final Object? notes = record['notes'];
    if (notes is! String || notes.length > AppConfig.maxPlaceNotesLength) {
      throw const BackupValidationException(BackupValidationException.badNotes);
    }

    final double latitude = _readCoordinate(
      record['latitude'],
      -90,
      90,
    );
    final double longitude = _readCoordinate(
      record['longitude'],
      -180,
      180,
    );
    final DateTime timestamp = _readTimestamp(
      record['timestamp'],
      maxTimestamp,
    );

    final Object? plusCode = record['plusCode'];
    if (plusCode != null &&
        (plusCode is! String ||
            plusCode.length > AppConfig.maxPlacePlusCodeLength)) {
      throw const BackupValidationException(
        BackupValidationException.badPlusCode,
      );
    }

    places.add(
      Place(
        id: id,
        name: name,
        notes: notes,
        latitude: latitude,
        longitude: longitude,
        timestamp: timestamp,
        isPinned: _readFlag(record, 'isPinned'),
        isHidden: _readFlag(record, 'isHidden'),
        isLocked: _readFlag(record, 'isLocked'),
        isVaulted: _readFlag(record, 'isVaulted'),
        updatedAt: _readOptionalTimestamp(record['updatedAt'], maxTimestamp),
        syncVersion: _readRevision(record['syncVersion']),
        deletedAt: _readOptionalTimestamp(record['deletedAt'], maxTimestamp),
      ),
    );
  }

  if (rawChecksum != null && rawChecksum != BackupFormat.checksum(places)) {
    throw const BackupValidationException(BackupValidationException.badChecksum);
  }

  return BackupEnvelope(
    places: places,
    schemaVersion: schemaVersion,
    hasChecksum: rawChecksum != null,
  );
}

int _readSchemaVersion(Object? value) {
  if (value == null) return 1; // v1 pre-dates the marker.
  final int? version = value is int
      ? value
      : (value is num && value.isFinite && value == value.toInt()
          ? value.toInt()
          : null);
  if (version == null ||
      version < 1 ||
      version > BackupFormat.schemaVersion) {
    throw const BackupValidationException(
      BackupValidationException.unsupportedSchema,
    );
  }
  return version;
}

String _readId(Object? value) {
  if (value is! String) {
    throw const BackupValidationException(BackupValidationException.badId);
  }
  final String id = value.trim();
  if (id.isEmpty ||
      id.length > AppConfig.maxPlaceIdLength ||
      !_safeId.hasMatch(id)) {
    throw const BackupValidationException(BackupValidationException.badId);
  }
  return id;
}

double _readCoordinate(Object? value, num min, num max) {
  if (value is! num || !value.isFinite) {
    throw const BackupValidationException(
      BackupValidationException.badCoordinate,
    );
  }
  final double coordinate = value.toDouble();
  if (coordinate < min || coordinate > max) {
    throw const BackupValidationException(
      BackupValidationException.badCoordinate,
    );
  }
  return coordinate;
}

DateTime _readTimestamp(Object? value, DateTime maxTimestamp) {
  DateTime? parsed;
  if (value is String) {
    parsed = DateTime.tryParse(value)?.toUtc();
  } else if (value is num && value.isFinite) {
    try {
      parsed = DateTime.fromMillisecondsSinceEpoch(
        value.toInt(),
        isUtc: true,
      );
    } on Exception {
      parsed = null;
    }
  } else {
    parsed = null;
  }

  if (parsed == null ||
      parsed.millisecondsSinceEpoch < AppConfig.minBackupTimestampMs ||
      parsed.isAfter(maxTimestamp)) {
    throw const BackupValidationException(
      BackupValidationException.badTimestamp,
    );
  }
  return parsed;
}

DateTime? _readOptionalTimestamp(Object? value, DateTime maxTimestamp) {
  if (value == null) return null; // Legacy record: fall back to creation time.
  DateTime? parsed;
  if (value is String) {
    parsed = DateTime.tryParse(value)?.toUtc();
  } else if (value is num && value.isFinite) {
    try {
      parsed = DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    } on Exception {
      parsed = null;
    }
  }
  if (parsed == null ||
      parsed.millisecondsSinceEpoch < AppConfig.minBackupTimestampMs ||
      parsed.isAfter(maxTimestamp)) {
    throw const BackupValidationException(BackupValidationException.badTimestamp);
  }
  return parsed;
}

int _readRevision(Object? value) {
  if (value == null) return 0;
  final int? revision = value is int
      ? value
      : (value is num && value.isFinite && value >= 0 && value == value.toInt()
          ? value.toInt()
          : null);
  if (revision == null || revision < 0) {
    throw const BackupValidationException(BackupValidationException.badRevision);
  }
  return revision;
}

bool _readFlag(Map<String, dynamic> record, String key) {
  final Object? value = record[key];
  // Older backups may omit flags; presence must be a real bool.
  if (value != null && value is! bool) {
    throw const BackupValidationException(BackupValidationException.badFlag);
  }
  return value == true;
}

/// Pre-scans bracket depth while ignoring strings and escapes. This rejects a
/// small but pathologically nested document before `jsonDecode` touches it.
int _jsonDepth(String raw) {
  int depth = 0;
  int maxDepth = 0;
  bool inString = false;
  bool escaped = false;

  for (final int unit in raw.codeUnits) {
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (unit == 0x5c) {
        escaped = true;
      } else if (unit == 0x22) {
        inString = false;
      }
      continue;
    }
    if (unit == 0x22) {
      inString = true;
    } else if (unit == 0x5b || unit == 0x7b) {
      depth++;
      if (depth > maxDepth) maxDepth = depth;
    } else if (unit == 0x5d || unit == 0x7d) {
      depth--;
      if (depth < 0) return maxDepth;
    }
  }
  return maxDepth;
}
