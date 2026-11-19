import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/local/place_local_data_source.dart';
import 'package:routenote/src/data/local/settings_repository.dart';
import 'package:routenote/src/data/models/backup_data.dart';
import 'package:routenote/src/data/models/backup_validator.dart';
import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/data/remote/auth_service.dart';
import 'package:routenote/src/data/remote/drive_service.dart';
import 'package:routenote/src/data/repositories/place_repository.dart';
import 'package:routenote/src/data/repositories/sync_repository.dart';
import 'package:routenote/src/data/services/sync_merge.dart';

final DateTime _t = DateTime.utc(2026, 11, 19, 12);

Place _place(
  String id, {
  String name = 'Place',
  String notes = '',
  DateTime? updatedAt,
  int syncVersion = 0,
  DateTime? deletedAt,
}) =>
    Place(
      id: id,
      name: name,
      notes: notes,
      latitude: 30.0444,
      longitude: 31.2357,
      timestamp: _t.subtract(const Duration(days: 1)),
      updatedAt: updatedAt,
      syncVersion: syncVersion,
      deletedAt: deletedAt,
    );

class _MemoryDataSource extends PlaceLocalDataSource {
  _MemoryDataSource(super.database);

  final Map<String, Place> store = <String, Place>{};

  @override
  Future<List<Place>> getAll() async =>
      store.values.where((Place p) => !p.isDeleted).toList();

  @override
  Future<List<Place>> getAllIncludingDeleted() async => store.values.toList();

  @override
  Future<Place?> getById(String id) async => store[id];

  @override
  Future<void> put(Place place) async {
    store[place.id] = place;
  }

  @override
  Future<void> applyMerged({
    required Iterable<Place> resolved,
    required Set<String> baselineIds,
  }) async {
    final Map<String, Place> entries = <String, Place>{
      for (final Place place in resolved) place.id: place,
    };
    for (final String id in store.keys.toSet().difference(baselineIds)) {
      entries.putIfAbsent(id, () => store[id]!);
    }
    store
      ..clear()
      ..addEntries(entries.entries);
  }
}

class _SignedInAuth implements AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(id: 'u', email: 'u@example.test');
  @override
  bool get isSignedIn => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<AuthUser?> signInSilently() async => currentUser;
  @override
  Future<AuthUser> signIn() async => currentUser!;
  @override
  Future<void> signOut() async {}
  @override
  Future<Map<String, String>?> authorizationHeaders({
    bool prompt = false,
  }) async =>
      const <String, String>{};
}

class _Drive implements DriveService {
  String? raw;
  int uploads = 0;
  String? lastUploaded;

  @override
  Future<bool> backupExists() async => raw != null;

  @override
  Future<DateTime?> remoteModifiedTime() async => null;

  @override
  Future<String?> downloadBackup() async => raw;

  @override
  Future<void> uploadBackup(String jsonContent) async {
    uploads++;
    lastUploaded = jsonContent;
  }
}

void main() {
  group('record-level merge', () {
    const SyncMerger merger = SyncMerger();

    test('the most recently edited copy wins', () {
      final Place older = _place('p1', name: 'Old', updatedAt: _t);
      final Place newer = _place(
        'p1',
        name: 'New',
        updatedAt: _t.add(const Duration(minutes: 1)),
      );

      expect(
        merger.merge(local: <Place>[newer], cloud: <Place>[older])
            .places
            .single
            .name,
        'New',
      );
      expect(
        merger.merge(local: <Place>[older], cloud: <Place>[newer])
            .places
            .single
            .name,
        'New',
      );
    });

    test('syncVersion breaks an exact timestamp tie', () {
      final Place low = _place('p1', name: 'Low', updatedAt: _t, syncVersion: 1);
      final Place high =
          _place('p1', name: 'High', updatedAt: _t, syncVersion: 3);

      final SyncMergeResult result =
          merger.merge(local: <Place>[low], cloud: <Place>[high]);
      expect(result.hasConflicts, isFalse);
      expect(result.places.single.name, 'High');
    });

    test('an equal-timestamp differing edit is a conflict; local is kept', () {
      final Place local = _place('p1', name: 'Local', updatedAt: _t);
      final Place cloud = _place('p1', name: 'Cloud', updatedAt: _t);

      final SyncMergeResult result =
          merger.merge(local: <Place>[local], cloud: <Place>[cloud]);

      expect(result.hasConflicts, isTrue);
      expect(result.conflicts.single.placeId, 'p1');
      expect(result.places.single, local);
    });

    test('a fresh tombstone beats a stale cloud copy without a conflict', () {
      final Place tombstone = _place(
        'p1',
        name: 'Gone',
        updatedAt: _t,
        deletedAt: _t,
      );
      final Place cloud = _place(
        'p1',
        name: 'Stale',
        updatedAt: _t.subtract(const Duration(days: 2)),
      );

      final SyncMergeResult result =
          merger.merge(local: <Place>[tombstone], cloud: <Place>[cloud]);
      expect(result.hasConflicts, isFalse);
      expect(result.places.single.isDeleted, isTrue);
    });

    test('records that exist on only one side are preserved', () {
      final Place localOnly = _place('local', name: 'Local only');
      final Place cloudOnly = _place('cloud', name: 'Cloud only');

      final SyncMergeResult result = merger.merge(
        local: <Place>[localOnly],
        cloud: <Place>[cloudOnly],
      );
      expect(result.places.map((Place p) => p.id), containsAll(<String>[
        'local',
        'cloud',
      ]));
      expect(result.hasConflicts, isFalse);
    });

    test('all three user resolutions produce a fresh, ordered record', () {
      final SyncConflict conflict = SyncConflict(
        'p1',
        _place('p1', name: 'Local', notes: 'local note', updatedAt: _t),
        _place('p1', name: 'Cloud', notes: 'cloud note', updatedAt: _t),
      );

      final Place kept = merger.resolve(conflict, SyncResolution.keepLocal);
      expect(kept.name, 'Local');
      expect(kept.syncVersion, 1);
      expect(kept.updatedAt, isNotNull);

      final Place used = merger.resolve(conflict, SyncResolution.useCloud);
      expect(used.name, 'Cloud');
      expect(used.syncVersion, 1);

      final Place merged = merger.resolve(conflict, SyncResolution.merge);
      expect(merged.notes, contains('local note'));
      expect(merged.notes, contains('cloud note'));
      expect(merged.syncVersion, 1);
    });
  });

  group('versioned backup envelope', () {
    test('v2 round-trips schema, checksum and per-record sync metadata', () {
      final Place place = _place(
        'p1',
        name: 'Tagged',
        updatedAt: _t,
        syncVersion: 7,
        deletedAt: _t.add(const Duration(seconds: 1)),
      );
      final String raw = BackupData(
        places: <Place>[place],
        lastSynced: _t,
      ).toRaw();

      final BackupEnvelope envelope = parseBackupEnvelope(raw);
      expect(envelope.schemaVersion, BackupFormat.schemaVersion);
      expect(envelope.hasChecksum, isTrue);
      expect(envelope.places.single.syncVersion, 7);
      expect(envelope.places.single.updatedAt, _t);
      expect(envelope.places.single.deletedAt, _t.add(const Duration(seconds: 1)));
    });

    test('checksum excludes last_synced so it cannot become trust evidence', () {
      final List<Place> places = <Place>[_place('p1')];
      final String a = BackupData(places: places, lastSynced: _t).toRaw();
      final String b = BackupData(
        places: places,
        lastSynced: _t.add(const Duration(days: 5)),
      ).toRaw();

      final String checksumA =
          (jsonDecode(a) as Map<String, dynamic>)['checksum'] as String;
      final String checksumB =
          (jsonDecode(b) as Map<String, dynamic>)['checksum'] as String;
      expect(checksumA, checksumB);
    });

    test('a modified checksum is rejected without echoing any field value', () {
      final Map<String, dynamic> decoded = jsonDecode(
        BackupData(places: <Place>[_place('p1', name: 'Original')]).toRaw(),
      ) as Map<String, dynamic>;
      final List<dynamic> places = decoded['places'] as List<dynamic>;
      (places.first as Map<String, dynamic>)['name'] = 'Tampered';

      expect(
        () => parseBackupEnvelope(jsonEncode(decoded)),
        throwsA(
          isA<BackupValidationException>().having(
            (BackupValidationException e) => e.code,
            'code',
            BackupValidationException.badChecksum,
          ),
        ),
      );
    });

    test('legacy v1 payloads remain readable', () {
      final String raw = jsonEncode(<String, dynamic>{
        'last_synced': _t.toIso8601String(),
        'places': <Map<String, dynamic>>[
          _place('p1').toJson()..remove('updatedAt'),
        ],
      });
      final BackupEnvelope envelope = parseBackupEnvelope(raw);
      expect(envelope.schemaVersion, 1);
      expect(envelope.hasChecksum, isFalse);
    });

    test('an unsupported schema version is rejected', () {
      final Map<String, dynamic> decoded = jsonDecode(
        BackupData(places: <Place>[_place('p1')]).toRaw(),
      ) as Map<String, dynamic>;
      decoded['schema_version'] = BackupFormat.schemaVersion + 1;
      expect(
        () => parseBackupEnvelope(jsonEncode(decoded)),
        throwsA(
          isA<BackupValidationException>().having(
            (BackupValidationException e) => e.code,
            'code',
            BackupValidationException.unsupportedSchema,
          ),
        ),
      );
    });
  });

  group('sync safety with a non-empty device', () {
    late Directory tempDir;
    late Box<dynamic> placesBox;
    late Box<dynamic> settingsBox;
    late _MemoryDataSource dataSource;
    late SettingsRepository settings;
    late _Drive drive;
    late SyncRepository sync;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sync_merge_');
      Hive.init(tempDir.path);
      placesBox = await Hive.openBox<dynamic>('sync_merge_places');
      settingsBox = await Hive.openBox<dynamic>('sync_merge_settings');
      dataSource = _MemoryDataSource(
        HiveDatabase(placesBox: placesBox, settingsBox: settingsBox),
      );
      settings = SettingsRepository(settingsBox);
      drive = _Drive();
      sync = SyncRepository(
        placeRepository: PlaceRepository(dataSource),
        driveService: drive,
        settingsRepository: settings,
        authService: _SignedInAuth(),
      );
    });

    tearDown(() async {
      await placesBox.close();
      await settingsBox.close();
      await tempDir.delete(recursive: true);
    });

    test('conflicts are neither uploaded nor trusted', () async {
      dataSource.store['p1'] = _place('p1', name: 'Local', updatedAt: _t);
      drive.raw = BackupData(
        places: <Place>[_place('p1', name: 'Cloud', updatedAt: _t)],
      ).toRaw();

      final SyncExecution execution = await sync.synchronize();

      expect(execution.outcome, SyncOutcome.conflictsDetected);
      expect(execution.hasConflicts, isTrue);
      expect(drive.uploads, 0);
      expect(settings.lastSynced, isNull);
      expect(dataSource.store['p1']!.name, 'Local');
    });

    test('resolving a conflict uploads and stamps trust', () async {
      dataSource.store['p1'] = _place('p1', name: 'Local', updatedAt: _t);
      drive.raw = BackupData(
        places: <Place>[_place('p1', name: 'Cloud', updatedAt: _t)],
      ).toRaw();
      final SyncExecution conflicted = await sync.synchronize();
      expect(conflicted.hasConflicts, isTrue);

      final SyncExecution resolved = await sync.resolveConflict(
        conflicted.merge!.conflicts.single,
        SyncResolution.useCloud,
        resolve: (SyncConflict c, SyncResolution r) =>
            const SyncMerger().resolve(c, r),
      );

      expect(resolved.outcome, SyncOutcome.merged);
      expect(resolved.hasConflicts, isFalse);
      expect(dataSource.store['p1']!.name, 'Cloud');
      expect(drive.uploads, 1);
      expect(settings.lastSynced, isNotNull);
    });

    test('a tombstone is propagated, not resurrected by a stale backup', () async {
      dataSource.store['p1'] = _place(
        'p1',
        updatedAt: _t,
        deletedAt: _t,
      );
      drive.raw = BackupData(
        places: <Place>[
          _place(
            'p1',
            updatedAt: _t.subtract(const Duration(days: 2)),
          ),
        ],
      ).toRaw();

      final SyncExecution execution = await sync.synchronize();

      expect(execution.outcome, SyncOutcome.merged);
      expect(dataSource.store['p1']!.isDeleted, isTrue);
      expect(await dataSource.getAll(), isEmpty);
      expect(drive.lastUploaded, contains('deletedAt'));
    });

    test('manual recovery import merges offline and surfaces conflicts', () async {
      dataSource.store['p1'] = _place('p1', name: 'Local', updatedAt: _t);
      final String envelope = BackupData(
        places: <Place>[_place('p1', name: 'Cloud', updatedAt: _t)],
      ).toRaw();

      final SyncExecution conflicted =
          await sync.importRecoveryBackup(envelope);

      expect(conflicted.outcome, SyncOutcome.conflictsDetected);
      expect(conflicted.hasConflicts, isTrue);
      // Recovery is fully offline: it never touches Drive or trust evidence.
      expect(drive.uploads, 0);
      expect(settings.lastSynced, isNull);

      final SyncExecution clean = await sync.importRecoveryBackup(
        BackupData(places: <Place>[_place('new-id', name: 'New')]).toRaw(),
      );
      expect(clean.outcome, SyncOutcome.merged);
      expect(dataSource.store.containsKey('new-id'), isTrue);
      expect(drive.uploads, 0);
    });

    test('a tampered envelope is rejected on both sync entry points', () async {
      final Map<String, dynamic> decoded = jsonDecode(
        BackupData(places: <Place>[_place('p1', name: 'Original')]).toRaw(),
      ) as Map<String, dynamic>;
      // Mutation after the checksum was computed: the parser must reject it.
      (decoded['places'] as List<dynamic>).first['name'] = 'Tampered';
      final String tampered = jsonEncode(decoded);

      expect(
        () => sync.importRecoveryBackup(tampered),
        throwsA(isA<BackupValidationException>()),
      );
      drive.raw = tampered;
      expect(
        () => sync.synchronize(),
        throwsA(isA<BackupValidationException>()),
      );

      // A rejected payload never reaches storage, Drive or trust evidence.
      expect(dataSource.store, isEmpty);
      expect(drive.uploads, 0);
      expect(settings.lastSynced, isNull);
    });
  });
}
