import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/core/theme/app_theme.dart';
import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/features/place_detail/widgets/route_preview_card.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/location_service.dart';

import 'helpers/route_preview_harness.dart';

/// The tile source every OSM-backed map in the app must use.
const String _osmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// OSM attribution, in the two locales the suite exercises.
const String _attributionEn = '© OpenStreetMap contributors';
const String _attributionAr = '© المساهمون في OpenStreetMap';

/// The saved place the preview always marks, and a device fix ~1.1 km away.
const double _placeLat = 30.0444;
const double _placeLon = 31.2357;
const double _deviceLat = 30.0459;
const double _deviceLon = 31.2243;

const LocationSuccess _fix = LocationSuccess(
  latitude: _deviceLat,
  longitude: _deviceLon,
);

/// A [LocationService] that returns a fixed verdict without ever touching the
/// geolocator platform channel.
class _FixedLocationService extends LocationService {
  const _FixedLocationService(this.result);

  final LocationResult result;

  @override
  Future<LocationResult> determinePosition() async => result;
}

Place _place() => Place(
  id: 'place-1',
  name: 'Cairo Tower',
  notes: 'Near the Nile',
  latitude: _placeLat,
  longitude: _placeLon,
  timestamp: DateTime.utc(2026, 1, 1),
);

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required LocationResult locationResult,
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('en'),
  }) async {
    final List<Override> overrides = <Override>[
      locationServiceProvider.overrideWithValue(
        _FixedLocationService(locationResult),
      ),
      // Never the network: the tile layer is served by the shared fake, so the
      // preview "loads" with zero imagery and the offline grid stays visible —
      // exactly how the route map's tests keep them deterministic.
      routeTileProviderProvider.overrideWithValue(NoImageryTiles()),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: brightness == Brightness.light
              ? AppTheme.light()
              : AppTheme.dark(),
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: RoutePreviewCard(place: _place())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  FlutterMap mapOf(WidgetTester tester) =>
      tester.widget<FlutterMap>(find.byType(FlutterMap).first);

  MapCamera cameraOf(WidgetTester tester) =>
      mapOf(tester).mapController!.camera;

  testWidgets('draws the route over OSM tiles with both markers and distance', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, locationResult: _fix);

    expect(find.text('Route preview'), findsOneWidget);
    expect(find.text('Current location'), findsOneWidget);
    expect(find.text('Saved place'), findsOneWidget);
    // The distance chip reads "<n> km away" for this pair.
    expect(find.textContaining('km away'), findsOneWidget);

    expect(tester.takeException(), isNull);
    expect(find.byType(FlutterMap), findsOneWidget);

    // Real raster tiles from OSM, served through the injected (network-free)
    // provider, and the app's package name folded into the User-Agent header
    // as the tile usage policy requires.
    final TileLayer tiles = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(tiles.urlTemplate, _osmUrl);
    expect(tiles.tileProvider, isA<NoImageryTiles>());
    expect(
      tiles.tileProvider.headers['User-Agent'],
      contains('com.routenote.routenote'),
    );
    expect(find.text(_attributionEn), findsOneWidget);

    // Red pin on the saved place, blue dot on the device — the colours the
    // legend under the card prints.
    final ColorScheme scheme = AppTheme.light().colorScheme;
    final List<Marker> markers = tester
        .widget<MarkerLayer>(find.byType(MarkerLayer))
        .markers;
    expect(markers, hasLength(2));
    expect(markers.first.point, const LatLng(_placeLat, _placeLon));
    expect(markers.last.point, const LatLng(_deviceLat, _deviceLon));

    final Icon pin = tester.widget<Icon>(
      find.descendant(
        of: find.byType(MarkerLayer),
        matching: find.byType(Icon),
      ),
    );
    expect(pin.color, scheme.error);
    final Container dot = tester.widget<Container>(
      find.descendant(
        of: find.byType(MarkerLayer),
        matching: find.byType(Container),
      ),
    );
    expect((dot.decoration! as BoxDecoration).color, scheme.primary);
  });

  testWidgets('connects the device to the place with a straight path', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, locationResult: _fix);

    // Halo + crisp line, the same two-stroke language as the route map, over
    // the real map instead of the old painted grid.
    final List<Polyline> polylines = tester
        .widget<PolylineLayer>(find.byType(PolylineLayer))
        .polylines;
    expect(polylines, hasLength(2));
    for (final Polyline line in polylines) {
      expect(line.points, <LatLng>[
        const LatLng(_deviceLat, _deviceLon),
        const LatLng(_placeLat, _placeLon),
      ]);
    }
  });

  testWidgets('fits the camera around both markers', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, locationResult: _fix);

    // "Fit bounds" with padding: the pair is framed without any interaction,
    // and neither marker can end up under the card's rounded edge.
    final LatLngBounds visible = cameraOf(tester).visibleBounds;
    expect(visible.contains(const LatLng(_placeLat, _placeLon)), isTrue);
    expect(visible.contains(const LatLng(_deviceLat, _deviceLon)), isTrue);
  });

  testWidgets('keeps the offline grid under a transparent map', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, locationResult: _fix);

    // The grid painter sits below the map and the map's background is
    // transparent — that combination is what degrades to the offline view
    // instead of a blank box when no tile can be fetched.
    final Stack stack = tester.widget<Stack>(
      find
          .ancestor(of: find.byType(FlutterMap), matching: find.byType(Stack))
          .first,
    );
    expect(stack.children, hasLength(2));
    expect(stack.children.first, isA<CustomPaint>());
    expect(mapOf(tester).options.backgroundColor, Colors.transparent);
  });

  testWidgets('marks only the saved place when location is off', (
    WidgetTester tester,
  ) async {
    await pumpCard(
      tester,
      locationResult: const LocationPermissionDenied(
        permanentlyDenied: false,
      ),
    );

    expect(find.text('Route preview'), findsOneWidget);
    expect(find.textContaining('away'), findsNothing);
    expect(
      find.text('Turn on location to see your distance'),
      findsOneWidget,
    );

    // No device fix: no path, no blue dot — but the place is still marked and
    // still framed.
    expect(
      tester
          .widget<PolylineLayer>(find.byType(PolylineLayer))
          .polylines,
      isEmpty,
    );
    final List<Marker> markers = tester
        .widget<MarkerLayer>(find.byType(MarkerLayer))
        .markers;
    expect(markers, hasLength(1));
    expect(markers.single.point, const LatLng(_placeLat, _placeLon));
    expect(
      cameraOf(tester).visibleBounds.contains(
        const LatLng(_placeLat, _placeLon),
      ),
      isTrue,
    );
  });

  testWidgets('tapping the card opens the larger preview sheet', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, locationResult: _fix);

    await tester.tap(find.text('Route preview'));
    await tester.pumpAndSettle();

    // The sheet shows the map-preview title and a second, taller preview,
    // which gets its own map (never a shared camera with the card's).
    expect(find.text('Map preview'), findsOneWidget);
    expect(find.text('Saved place'), findsNWidgets(2));
    expect(find.byType(FlutterMap), findsNWidgets(2));
  });

  testWidgets('renders the OSM preview in Arabic RTL on the dark theme', (
    WidgetTester tester,
  ) async {
    await pumpCard(
      tester,
      locationResult: _fix,
      brightness: Brightness.dark,
      locale: const Locale('ar'),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('معاينة المسار'), findsOneWidget);
    expect(find.text(_attributionAr), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(
      cameraOf(tester).visibleBounds.contains(
        const LatLng(_deviceLat, _deviceLon),
      ),
      isTrue,
    );
  });
}
