import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/local/place_local_data_source.dart';
import 'package:routenote/src/data/local/settings_repository.dart';
import 'package:routenote/src/data/models/backup_data.dart';
import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/data/remote/auth_service.dart';
import 'package:routenote/src/data/remote/drive_service.dart';
import 'package:routenote/src/data/repositories/place_repository.dart';
import 'package:routenote/src/features/settings/sync_conflict_sheet.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/app_health_logger.dart';

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

/// A real Hive write never completes inside `testWidgets`' FakeAsync zone, so
/// the trust stamp is kept in memory for this widget-level test.
class _MemorySettings extends SettingsRepository {
  _MemorySettings(super.box);

  DateTime? _lastSynced;

  @override
  DateTime? get lastSynced => _lastSynced;

  @override
  Future<void> setLastSynced(DateTime time) async {
    _lastSynced = time.toUtc();
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

class _RecordingDrive implements DriveService {
  int uploads = 0;

  @override
  Future<bool> backupExists() async => true;
  @override
  Future<DateTime?> remoteModifiedTime() async => null;
  @override
  Future<String?> downloadBackup() async => null;
  @override
  Future<void> uploadBackup(String jsonContent) async {
    uploads++;
  }
}

void main() {
  late Directory tempDir;
  late Box<dynamic> placesBox;
  late Box<dynamic> settingsBox;
  late _MemoryDataSource dataSource;
  late _RecordingDrive drive;
  late ProviderContainer container;

  final DateTime stamp = DateTime.utc(2026, 11, 19, 12);
  Place place(String name) => Place(
        id: 'p1',
        name: name,
        notes: '',
        latitude: 30.0444,
        longitude: 31.2357,
        timestamp: stamp,
        updatedAt: stamp,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_conflict_ui_');
    Hive.init(tempDir.path);
    placesBox = await Hive.openBox<dynamic>('conflict_places');
    settingsBox = await Hive.openBox<dynamic>('conflict_settings');
    final HiveDatabase database = HiveDatabase(
      placesBox: placesBox,
      settingsBox: settingsBox,
    );
    dataSource = _MemoryDataSource(database);
    drive = _RecordingDrive();

    container = ProviderContainer(
      overrides: <Override>[
        hiveDatabaseProvider.overrideWithValue(database),
        settingsRepositoryProvider.overrideWithValue(
          _MemorySettings(settingsBox),
        ),
        placeRepositoryProvider.overrideWithValue(
          PlaceRepository(dataSource),
        ),
        authServiceProvider.overrideWithValue(_SignedInAuth()),
        driveServiceProvider.overrideWithValue(drive),
        appHealthLoggerProvider.overrideWithValue(AppHealthLogger(null)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await placesBox.close();
    await settingsBox.close();
    await tempDir.delete(recursive: true);
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const SyncConflictSheet(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('conflict sheet offers all three resolutions and resolves one', (
    WidgetTester tester,
  ) async {
    dataSource.store['p1'] = place('Local');
    await container.read(syncControllerProvider.notifier).importRecoveryBackup(
          BackupData(places: <Place>[place('Cloud')]).toRaw(),
        );
    expect(container.read(syncControllerProvider).status, SyncStatus.conflict);

    await pumpSheet(tester);

    expect(find.text('Resolve sync conflicts'), findsOneWidget);
    expect(find.text('Keep local'), findsOneWidget);
    expect(find.text('Use cloud'), findsOneWidget);
    expect(find.text('Merge'), findsOneWidget);

    await tester.tap(find.text('Use cloud'));
    await tester.pumpAndSettle();

    final SyncState state = container.read(syncControllerProvider);
    expect(state.status, SyncStatus.success);
    expect(state.hasConflicts, isFalse);
    expect(dataSource.store['p1']!.name, 'Cloud');
    // Resolving uploads the clean result; the sheet closes when none remain.
    expect(drive.uploads, 1);
    expect(find.text('Conflict resolved'), findsOneWidget);
    expect(find.text('Resolve sync conflicts'), findsNothing);
  });
}
