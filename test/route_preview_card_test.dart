import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/core/theme/app_theme.dart';
import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/features/place_detail/widgets/route_preview_card.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/location_service.dart';

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
  latitude: 30.0444,
  longitude: 31.2357,
  timestamp: DateTime.utc(2026, 1, 1),
);

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required LocationResult locationResult,
  }) async {
    final List<Override> overrides = <Override>[
      locationServiceProvider.overrideWithValue(
        _FixedLocationService(locationResult),
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: RoutePreviewCard(place: _place())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('draws the route, both markers and the estimated distance', (
    WidgetTester tester,
  ) async {
    await pumpCard(
      tester,
      // ~1.1 km from the saved place.
      locationResult: const LocationSuccess(
        latitude: 30.0459,
        longitude: 31.2243,
      ),
    );

    expect(find.text('Route preview'), findsOneWidget);
    expect(find.text('Current location'), findsOneWidget);
    expect(find.text('Saved place'), findsOneWidget);
    // The distance chip reads "<n> km away" for this pair.
    expect(find.textContaining('km away'), findsOneWidget);
    // The map itself is painted, not a placeholder.
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('omits the distance and shows a hint when location is off', (
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
  });

  testWidgets('tapping the card opens the larger preview sheet', (
    WidgetTester tester,
  ) async {
    await pumpCard(
      tester,
      locationResult: const LocationSuccess(
        latitude: 30.0459,
        longitude: 31.2243,
      ),
    );

    await tester.tap(find.text('Route preview'));
    await tester.pumpAndSettle();

    // The sheet shows the map-preview title and a second, taller preview.
    expect(find.text('Map preview'), findsOneWidget);
    expect(find.text('Saved place'), findsNWidgets(2));
  });
}
