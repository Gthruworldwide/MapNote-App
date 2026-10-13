import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/features/add_place/add_place_screen.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/location_service.dart';

/// A [LocationService] that never touches the geolocator platform channel.
class _FakeLocationService extends LocationService {
  const _FakeLocationService();

  @override
  Future<LocationResult> determinePosition() async {
    return const LocationSuccess(latitude: 1.5, longitude: 2.5);
  }
}

void main() {
  Future<void> pumpScreen(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(
            const _FakeLocationService(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: child,
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
    await tester.tap(find.text('Paste location from clipboard'));
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
}
