import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/src/core/config/app_config.dart';
import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/local/place_local_data_source.dart';
import 'package:routenote/src/data/local/settings_repository.dart';
import 'package:routenote/src/data/models/backup_validator.dart';
import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/data/remote/auth_service.dart';
import 'package:routenote/src/data/remote/drive_service.dart';
import 'package:routenote/src/data/repositories/place_repository.dart';
import 'package:routenote/src/data/repositories/sync_repository.dart';

class _MemoryDataSource extends PlaceLocalDataSource {
  _MemoryDataSource(super.database);

  final Map<String, Place> store = <String, Place>{};

  @override
  Future<List<Place>> getAll() async => store.values.toList();

  // The sync layer reads/writes through these two methods. Back them with the
  // in-memory store so a place inserted mid-download is visible to the merge
  // exactly as it would be in Hive.
  @override
  Future<List<Place>> getAllIncludingDeleted() async =>
      store.values.toList();

  @override
  Future<void> applyMerged({
    required Iterable<Place> resolved,
    required Set<String> baselineIds,
  }) async {
    final Map<String, Place> entries = <String, Place>{
      for (final Place place in resolved) place.id: place,
    };
    // Preserve anything created after the baseline was captured.
    for (final String id in store.keys.toSet().difference(baselineIds)) {
      entries.putIfAbsent(id, () => store[id]!);
    }
    store
      ..clear()
      ..addEntries(entries.entries);
  }

  @override
  Future<RestoreApplyResult> applyBackup({
    required Iterable<Place> backupPlaces,
    required Set<String> baselineIds,
    required bool requireEmptyLocal,
  }) async {
    if (requireEmptyLocal && store.isNotEmpty) {
      return RestoreApplyResult.abortedLocalNotEmpty;
    }
    final Map<String, Place> entries = <String, Place>{
      for (final Place place in backupPlaces) place.id: place,
    };
    for (final String id in store.keys.toSet().difference(baselineIds)) {
      entries[id] = store[id]!;
    }
    store
      ..clear()
      ..addEntries(entries.entries);
    return RestoreApplyResult.applied;
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
  Future<Map<String, String>?> authorizationHeaders({bool prompt = false}) async {
    return <String, String>{};
  }
}

class _GateDrive implements DriveService {
  final Completer<String?> gate = Completer<String?>();
  int downloads = 0;

  @override
  Future<bool> backupExists() async => true;

  @override
  Future<DateTime?> remoteModifiedTime() async => null;

  @override
  Future<String?> downloadBackup() {
    downloads++;
    return gate.future;
  }

  @override
  Future<void> uploadBackup(String jsonContent) async {}
}

String backupJson({
  required List<Map<String, dynamic>> places,
  String? lastSynced,
  String? extraRootKey,
}) {
  return jsonEncode(<String, dynamic>{
    'last_synced': lastSynced ?? '2200-01-01T00:00:00.000Z',
    ...(extraRootKey == null
        ? const <String, dynamic>{}
        : <String, dynamic>{extraRootKey: <String, dynamic>{}}),
    'places': places,
  });
}

Map<String, dynamic> backupPlace({
  String id = 'p1',
  String name = 'Saved Place',
  Object latitude = 30.0444,
  Object longitude = 31.2357,
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'notes': 'notes',
    'latitude': latitude,
    'longitude': longitude,
    'timestamp': '2026-11-19T10:00:00.000Z',
    'isPinned': false,
    'isHidden': false,
    'isLocked': false,
    'isVaulted': false,
  };
}

void main() {
  late Directory tempDir;
  late Box<dynamic> placesBox;
  late Box<dynamic> settingsBox;
  late _MemoryDataSource dataSource;
  late SettingsRepository settings;
  late SyncRepository sync;
  late _GateDrive drive;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('restore_security_');
    Hive.init(tempDir.path);
    placesBox = await Hive.openBox<dynamic>('places');
    settingsBox = await Hive.openBox<dynamic>('settings');
    dataSource = _MemoryDataSource(
      HiveDatabase(placesBox: placesBox, settingsBox: settingsBox),
    );
    settings = SettingsRepository(settingsBox);
    drive = _GateDrive();
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

  test('a place added during download is merged, never overwritten', () async {
    final Future<SyncOutcome> outcome = sync.syncNow();
    final Place added = Place(
      id: 'added-locally',
      name: 'Added Locally',
      notes: '',
      latitude: 1,
      longitude: 2,
      timestamp: DateTime.utc(2026, 11, 19),
    );
    // Inserted after `synchronize` captured its baseline but before the
    // download completes — the exact race the merge must survive.
    dataSource.store[added.id] = added;
    drive.gate.complete(backupJson(places: <Map<String, dynamic>>[
      backupPlace(),
    ]));

    expect(await outcome, SyncOutcome.merged);
    expect(dataSource.store.containsKey(added.id), isTrue);
    expect(dataSource.store.containsKey('p1'), isTrue);
    expect(drive.downloads, 1);
    // A successful Drive round-trip is the only thing that stamps trust.
    expect(settings.lastSynced, isNotNull);
  });

  test('explicit restore keeps local places and merges the cloud copy', () async {
    final Place original = Place(
      id: 'original',
      name: 'Original',
      notes: '',
      latitude: 1,
      longitude: 2,
      timestamp: DateTime.utc(2026, 11, 19),
    );
    dataSource.store[original.id] = original;

    final Future<int> restored = sync.restoreFromDrive();
    final Place added = Place(
      id: 'added-locally',
      name: 'Added Locally',
      notes: '',
      latitude: 3,
      longitude: 4,
      timestamp: DateTime.utc(2026, 11, 19),
    );
    dataSource.store[added.id] = added;
    drive.gate.complete(backupJson(places: <Map<String, dynamic>>[
      backupPlace(),
    ]));

    // No local record is silently replaced: the pre-existing place, the one
    // added mid-download, and the cloud record all survive the merge.
    expect(await restored, 2);
    expect(
      dataSource.store.keys,
      containsAll(<String>['p1', added.id, original.id]),
    );
  });

  test('a remote last_synced never becomes local session-trust evidence',
      () async {
    final Future<int> restored = sync.restoreFromDrive();
    drive.gate.complete(backupJson(
      places: <Map<String, dynamic>>[backupPlace()],
      lastSynced: '2200-01-01T00:00:00.000Z',
    ));

    expect(await restored, 1);
    final DateTime? stamped = settings.lastSynced;
    expect(stamped, isNotNull);
    expect(stamped!.year, DateTime.now().toUtc().year);
    expect(stamped.isAfter(DateTime.now().toUtc()), isFalse);
  });

  group('strict backup validation', () {
    test('rejects non-finite and out-of-range coordinates', () {
      // Raw literals exercise the decoder's own non-finite results; a Dart
      // double.nan cannot be passed through jsonEncode.
      for (final String literal in <String>['NaN', 'Infinity', '-Infinity', '1e999']) {
        final String raw = '{"places":[{"id":"p1","name":"n","notes":"",'
            '"latitude":$literal,"longitude":31.2357,'
            '"timestamp":"2026-11-19T10:00:00.000Z"}]}';
        expect(
          () => parseBackup(raw),
          throwsA(isA<BackupValidationException>()),
          reason: 'coordinate $literal must be rejected',
        );
      }

      for (final Object coordinate in <Object>[91, -181, 'NaN']) {
        expect(
          () => parseBackup(backupJson(places: <Map<String, dynamic>>[
            backupPlace(latitude: coordinate),
          ])),
          throwsA(isA<BackupValidationException>()),
        );
      }
    });

    test('rejects duplicates, unknown keys and non-boolean flags', () {
      final Map<String, dynamic> duplicate = backupPlace();
      expect(
        () => parseBackup(backupJson(places: <Map<String, dynamic>>[
          duplicate,
          Map<String, dynamic>.from(duplicate),
        ])),
        throwsA(isA<BackupValidationException>()),
      );

      final Map<String, dynamic> unknown = backupPlace()
        ..['unexpected'] = true;
      expect(
        () => parseBackup(backupJson(places: <Map<String, dynamic>>[unknown])),
        throwsA(isA<BackupValidationException>()),
      );

      final Map<String, dynamic> badFlag = backupPlace()..['isLocked'] = 1;
      expect(
        () => parseBackup(backupJson(places: <Map<String, dynamic>>[badFlag])),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('rejects oversized, deeply nested and malformed documents', () {
      expect(
        () => parseBackup('x' * (AppConfig.maxBackupBytes + 1)),
        throwsA(isA<BackupValidationException>()),
      );
      expect(
        () => parseBackup(
          '${'[' * (AppConfig.maxBackupJsonDepth + 1)}'
          '0'
          '${']' * (AppConfig.maxBackupJsonDepth + 1)}',
        ),
        throwsA(isA<BackupValidationException>()),
      );
      expect(
        () => parseBackup('{not json'),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('accepts a bounded, well-formed backup', () {
      final List<Place> places = parseBackup(
        backupJson(places: <Map<String, dynamic>>[backupPlace()]),
        now: () => DateTime.utc(2026, 11, 19),
      );
      expect(places, hasLength(1));
      expect(places.single.id, 'p1');
      expect(places.single.latitude, 30.0444);
    });
  });

  test('bounded media reader stops at the byte cap', () async {
    final Stream<List<int>> stream = Stream<List<int>>.fromIterable(
      <List<int>>[
        List<int>.filled(1024, 0x7b),
        List<int>.filled(AppConfig.maxBackupBytes, 0x7d),
      ],
    );
    await expectLater(
      readBoundedBackup(stream, AppConfig.maxBackupBytes + 1024),
      throwsA(isA<FormatException>()),
    );
  });
}
