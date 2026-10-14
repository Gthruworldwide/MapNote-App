import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/local/place_local_data_source.dart';
import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/data/repositories/place_repository.dart';
import 'package:routenote/src/features/add_place/add_place_screen.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/app_health_logger.dart';
import 'package:routenote/src/services/geocoding_service.dart';
import 'package:routenote/src/services/location_service.dart';

/// A [LocationService] that never touches the geolocator platform channel.
class _FakeLocationService extends LocationService {
  const _FakeLocationService();

  @override
  Future<LocationResult> determinePosition() async {
    return const LocationSuccess(latitude: 1.5, longitude: 2.5);
  }
}

/// In-memory [PlaceLocalDataSource] so the save chain runs on pure Dart
/// futures (safe inside a widget test's FakeAsync zone).
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

/// Hosts [child] on a pushed route so screens can pop themselves, and so a
/// SnackBar always has a Scaffold to land in after the pop.
class _RouteHost extends StatefulWidget {
  const _RouteHost(this.child);

  final Widget child;

  @override
  State<_RouteHost> createState() => _RouteHostState();
}

class _RouteHostState extends State<_RouteHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => widget.child),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

void main() {
  late Directory tempDir;
  late Box<dynamic> placesBox;
  late Box<dynamic> settingsBox;
  late HiveDatabase database;
  late _MemoryDataSource dataSource;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('routenote_add_test_');
    Hive.init(tempDir.path);
    placesBox = await Hive.openBox<dynamic>('test_add_places');
    settingsBox = await Hive.openBox<dynamic>('test_add_settings');
    database = HiveDatabase(placesBox: placesBox, settingsBox: settingsBox);
    dataSource = _MemoryDataSource(database);
  });

  tearDown(() async {
    await placesBox.close();
    await settingsBox.close();
    await tempDir.delete(recursive: true);
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget child, {
    List<Override> overrides = const <Override>[],
  }) async {
    // A tall viewport keeps the whole form (including the suggestion card next
    // to the Save button) built, so finders do not depend on scroll position.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hiveDatabaseProvider.overrideWithValue(database),
          placeRepositoryProvider.overrideWithValue(PlaceRepository(dataSource)),
          locationServiceProvider.overrideWithValue(
            const _FakeLocationService(),
          ),
          // Saving logs a health event, which is mirrored to the settings box
          // with a fire-and-forget `put`. Inside a widget test that write never
          // completes, so `Box.close()` in tearDown would hang forever. Keep the
          // logger in memory, exactly as its `null` box is documented for tests.
          appHealthLoggerProvider.overrideWithValue(AppHealthLogger(null)),
          ...overrides,
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          // Hosted behind a pushed route so AddPlaceScreen can pop itself.
          home: _RouteHost(child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a shared location pre-fills the manual fields', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      const AddPlaceScreen(
        initialLatitude: 30.0459,
        initialLongitude: 31.2243,
        initialName: 'Cairo Tower',
      ),
    );

    expect(find.text('Cairo Tower'), findsOneWidget);
    expect(find.text('30.0459'), findsOneWidget);
    expect(find.text('31.2243'), findsOneWidget);

    final ChoiceChip manual = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Custom coordinates'),
    );
    expect(manual.selected, isTrue);
  });

  testWidgets('pasting a geo: URI fills coordinates and switches to manual', (
    WidgetTester tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': 'geo:48.8584,2.2945'};
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await pumpScreen(tester, const AddPlaceScreen());
    await tester.tap(find.text('AI Smart Paste'));
    await tester.pumpAndSettle();

    expect(find.text('48.8584'), findsOneWidget);
    expect(find.text('2.2945'), findsOneWidget);

    final ChoiceChip manual = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Custom coordinates'),
    );
    expect(manual.selected, isTrue);
  });

  testWidgets('rejects out-of-range latitude', (WidgetTester tester) async {
    await pumpScreen(
      tester,
      const AddPlaceScreen(initialLatitude: 30.0, initialLongitude: 31.0),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Testing',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Latitude'),
      '120',
    );
    final Finder saveButton = find.text('Save');
    await tester.dragUntilVisible(
      saveButton,
      find.byType(ListView),
      const Offset(0, -200),
    );
    // The form is taller than the 800x600 test viewport, so settle the scroll
    // before tapping or the hit test lands on the pre-scroll position.
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Latitude must be between -90 and 90'), findsOneWidget);
  });

  testWidgets('a typed Plus Code decodes into the coordinate fields', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      const AddPlaceScreen(initialMode: LocationEntryMode.manual),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Plus Code'),
      '8FVC9G8F+6W',
    );
    await tester.pumpAndSettle();

    // The centre of the decoded cell is written into latitude/longitude.
    expect(find.textContaining('47.3655'), findsOneWidget);
    expect(find.textContaining('8.5248'), findsOneWidget);
  });

  testWidgets('the coordinate fields drive the Plus Code preview', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      const AddPlaceScreen(initialMode: LocationEntryMode.manual),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Latitude'),
      '30.0444',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Longitude'),
      '31.2357',
    );
    await tester.pumpAndSettle();

    expect(find.text('8G2H26VP+Q7'), findsOneWidget);
  });

  testWidgets('a Plus-Code-only place decodes offline and saves', (
    WidgetTester tester,
  ) async {
    // Only a Plus Code is provided: no GPS, no lat/lng. The code must be
    // decoded on-device and the place persisted with the decoded coordinates.
    await pumpScreen(
      tester,
      const AddPlaceScreen(initialPlusCode: '8FVC9G8F+6W'),
    );

    // Decoded straight into the (offline) coordinate fields...
    expect(find.textContaining('47.3655'), findsOneWidget);
    expect(find.textContaining('8.5248'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Zurich gate',
    );
    final Finder saveButton = find.text('Save');
    await tester.dragUntilVisible(
      saveButton,
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(dataSource.store, hasLength(1));
    final Place saved = dataSource.store.values.first;
    expect(saved.name, 'Zurich gate');
    // The Smart field rounds to five decimals (≈1 m), so the stored point is
    // the decoded cell centre within that tolerance.
    expect(saved.latitude, closeTo(47.3655625, 1e-4));
    expect(saved.longitude, closeTo(8.5248125, 1e-4));
  });

  testWidgets('a reverse-geocoded suggestion auto-fills Name & Notes', (
    WidgetTester tester,
  ) async {
    final GeocodingService geocoding = GeocodingService(
      placemarkLookup: (double latitude, double longitude) async =>
          <Placemark>[
            const Placemark(
              name: 'Cairo Tower',
              street: '26th of July Corridor',
              locality: 'Cairo',
              country: 'Egypt',
            ),
          ],
    );

    await pumpScreen(
      tester,
      const AddPlaceScreen(initialMode: LocationEntryMode.manual),
      overrides: <Override>[
        geocodingServiceProvider.overrideWithValue(geocoding),
      ],
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Latitude'),
      '30.0459',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Longitude'),
      '31.2243',
    );
    // Let the 600ms geocode debounce fire and the lookup resolve.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('Nearby place'), findsOneWidget);
    expect(find.text('Found: Cairo Tower'), findsOneWidget);

    await tester.tap(find.text('Auto-fill Name & Notes'));
    await tester.pumpAndSettle();

    // The suggestion is consumed and the fields are populated.
    expect(find.text('Found: Cairo Tower'), findsNothing);
    expect(
      find.widgetWithText(
        TextFormField,
        '26th of July Corridor, Cairo, Egypt',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a suggestion can be dismissed without filling anything', (
    WidgetTester tester,
  ) async {
    final GeocodingService geocoding = GeocodingService(
      placemarkLookup: (double latitude, double longitude) async =>
          <Placemark>[const Placemark(name: 'Cairo Tower')],
    );

    await pumpScreen(
      tester,
      const AddPlaceScreen(initialMode: LocationEntryMode.manual),
      overrides: <Override>[
        geocodingServiceProvider.overrideWithValue(geocoding),
      ],
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Latitude'),
      '30.0459',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Longitude'),
      '31.2243',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('Nearby place'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss suggestion'));
    await tester.pumpAndSettle();

    expect(find.text('Nearby place'), findsNothing);
    expect(find.text('Cairo Tower'), findsNothing);
  });
}
