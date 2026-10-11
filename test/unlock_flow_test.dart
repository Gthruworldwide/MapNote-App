import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/app.dart';
import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/local/place_local_data_source.dart';
import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/data/repositories/place_repository.dart';
import 'package:routenote/src/data/remote/auth_service.dart';
import 'package:routenote/src/features/home/widgets/place_card.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/app_health_logger.dart';
import 'package:routenote/src/services/biometric_service.dart';

/// In-memory [PlaceLocalDataSource] so PlacesNotifier's save/getById/getAll
/// chain runs on pure Dart futures (safe inside a widget test's FakeAsync
/// zone, where real Hive file I/O can never complete).
class _MemoryDataSource extends PlaceLocalDataSource {
  _MemoryDataSource(super.database);

  final Map<String, Place> store = <String, Place>{};

  @override
  Future<List<Place>> getAll() async {
    final List<Place> places = store.values.toList();
    places.sort((Place a, Place b) => b.timestamp.compareTo(a.timestamp));
    return places;
  }

  @override
  Future<Place?> getById(String id) async => store[id];

  @override
  Future<void> put(Place place) async => store[place.id] = place;

  @override
  Future<void> delete(String id) async => store.remove(id);

  @override
  Future<void> replaceAll(Iterable<Place> places) async {
    store
      ..clear()
      ..addEntries(places.map((Place p) => MapEntry<String, Place>(p.id, p)));
  }
}

class _FakeAuthService implements AuthService {
  @override
  AuthUser? get currentUser => null;

  @override
  bool get isSignedIn => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<AuthUser?> signInSilently() async => null;

  @override
  Future<AuthUser> signIn() => throw UnimplementedError();

  @override
  Future<void> signOut() async {}

  @override
  Future<Map<String, String>?> authorizationHeaders({
    bool prompt = false,
  }) async {
    return null;
  }
}

/// Fake identity gate with a test-controlled verdict, so the unlock handler
/// can be exercised without the `local_auth` platform channel.
class _FakeBiometrics extends BiometricService {
  _FakeBiometrics({required this.available, required this.verdict});

  final bool available;
  final bool verdict;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate({required String reason}) async => verdict;
}

void main() {
  late Directory tempDir;
  late Box<dynamic> placesBox;
  late Box<dynamic> settingsBox;
  late HiveDatabase database;
  late _MemoryDataSource dataSource;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('routenote_unlock_test_');
    Hive.init(tempDir.path);
    placesBox = await Hive.openBox<dynamic>('test_places');
    settingsBox = await Hive.openBox<dynamic>('test_settings');
    database = HiveDatabase(placesBox: placesBox, settingsBox: settingsBox);
    dataSource = _MemoryDataSource(database);
  });

  tearDown(() async {
    await placesBox.close();
    await settingsBox.close();
    await tempDir.delete(recursive: true);
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    required bool biometricVerdict,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hiveDatabaseProvider.overrideWithValue(database),
          authServiceProvider.overrideWithValue(_FakeAuthService()),
          appHealthLoggerProvider.overrideWithValue(AppHealthLogger(null)),
          biometricServiceProvider.overrideWithValue(
            _FakeBiometrics(available: true, verdict: biometricVerdict),
          ),
          // Keep PlacesNotifier's persistence chain out of Hive so it can
          // complete inside the FakeAsync zone.
          placeRepositoryProvider.overrideWithValue(
            PlaceRepository(dataSource),
          ),
        ],
        child: const RouteNoteApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Place lockedPlace() => Place(
    id: 'place-1',
    name: 'Cairo Tower',
    notes: 'Near the Nile',
    latitude: 30.0444,
    longitude: 31.2357,
    timestamp: DateTime(2026, 1, 1),
    isLocked: true,
  );

  testWidgets('unlock persists isLocked=false and refreshes the UI', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() => dataSource.put(lockedPlace()));
    await pumpApp(tester, biometricVerdict: true);

    // Locked places are masked: no raw title/coordinates on screen.
    expect(find.text('Cairo Tower'), findsNothing);
    expect(find.textContaining('30.044'), findsNothing);

    // Long-press opens the context menu.
    await tester.longPress(find.byType(PlaceCard));
    await tester.pumpAndSettle();
    expect(find.text('Unlock location'), findsOneWidget);

    // Unlock triggers local_auth (fake verdict: verified), then persists
    // through the repository and refreshes the provider state.
    await tester.tap(find.text('Unlock location'));
    await tester.pumpAndSettle();

    final Place? stored = await dataSource.getById('place-1');
    expect(stored, isNotNull);
    expect(stored!.isLocked, isFalse);

    // The home list rebuilt: the row now shows the real title/coordinates.
    expect(find.text('Cairo Tower'), findsOneWidget);
    expect(find.textContaining('30.044'), findsOneWidget);
  });

  testWidgets('canceled identity check keeps the place locked', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() => dataSource.put(lockedPlace()));
    await pumpApp(tester, biometricVerdict: false);

    await tester.longPress(find.byType(PlaceCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock location'));
    await tester.pumpAndSettle();

    final Place? stored = await dataSource.getById('place-1');
    expect(stored!.isLocked, isTrue);

    // The failure snackbar is shown and the row stays masked.
    expect(find.text('Authentication failed'), findsOneWidget);
    expect(find.text('Cairo Tower'), findsNothing);
  });
}
