import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/features/saved_places/domain/entities/place_link_suggestion.dart';
import 'package:routenote/src/features/saved_places/domain/entities/trip_stop.dart';
import 'package:routenote/src/features/saved_places/presentation/providers/saved_places_providers.dart';
import 'package:routenote/src/features/saved_places/presentation/widgets/place_link_suggestions_card.dart';

/// The suggestion card is driven entirely by [placeLinkSuggestionsProvider], so
/// the derived provider is overridden with fixed value objects — no route, no
/// Hive and no platform channels are involved.
void main() {
  TripStop stop() => TripStop(
    latitude: 30.0444,
    longitude: 31.2357,
    arrivedAt: DateTime.utc(2026, 10, 19, 9),
    dwell: const Duration(minutes: 12),
  );

  Place place() => Place(
    id: 'place-1',
    name: 'Coffee Corner',
    notes: '',
    latitude: 30.0444,
    longitude: 31.2357,
    timestamp: DateTime.utc(2026, 1, 1),
  );

  late AppLocalizations l10n;
  late AppLocalizations l10nAr;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
    l10nAr = await AppLocalizations.delegate.load(const Locale('ar'));
  });

  Future<void> pumpCard(
    WidgetTester tester,
    List<PlaceLinkSuggestion> suggestions, {
    ThemeData? theme,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          placeLinkSuggestionsProvider.overrideWithValue(suggestions),
        ],
        child: MaterialApp(
          theme: theme,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: PlaceLinkSuggestionsCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders nothing when there are no suggestions', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, const <PlaceLinkSuggestion>[]);

    expect(find.byType(Card), findsNothing);
    expect(find.text(l10n.suggestedPlaceLinks), findsNothing);
  });

  testWidgets('shows a matching saved place, its distance and the dwell', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, <PlaceLinkSuggestion>[
      PlaceLinkSuggestion(
        kind: PlaceLinkSuggestionKind.linkToExisting,
        stop: stop(),
        place: place(),
        distanceMeters: 42,
      ),
    ]);

    expect(find.text(l10n.suggestedPlaceLinks), findsOneWidget);
    expect(find.textContaining('Coffee Corner'), findsOneWidget);
    expect(find.textContaining('42'), findsOneWidget);
    expect(find.textContaining('12'), findsOneWidget);
    expect(find.text(l10n.suggestedPlaceOpenAction), findsOneWidget);
    expect(find.text(l10n.suggestedPlaceSaveAction), findsNothing);
  });

  testWidgets('offers to save an unmatched stop', (WidgetTester tester) async {
    await pumpCard(tester, <PlaceLinkSuggestion>[
      PlaceLinkSuggestion(
        kind: PlaceLinkSuggestionKind.saveAsNew,
        stop: stop(),
        distanceMeters: 0,
      ),
    ]);

    expect(find.text(l10n.suggestedPlaceNoMatch), findsOneWidget);
    expect(find.text(l10n.suggestedPlaceSaveAction), findsOneWidget);
    expect(find.text(l10n.suggestedPlaceOpenAction), findsNothing);
  });

  testWidgets('renders in dark mode', (WidgetTester tester) async {
    await pumpCard(
      tester,
      <PlaceLinkSuggestion>[
        PlaceLinkSuggestion(
          kind: PlaceLinkSuggestionKind.linkToExisting,
          stop: stop(),
          place: place(),
          distanceMeters: 42,
        ),
      ],
      theme: ThemeData.dark(),
    );

    expect(find.text(l10n.suggestedPlaceLinks), findsOneWidget);
    expect(find.text(l10n.suggestedPlaceOpenAction), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders mirrored for Arabic', (WidgetTester tester) async {
    await pumpCard(
      tester,
      <PlaceLinkSuggestion>[
        PlaceLinkSuggestion(
          kind: PlaceLinkSuggestionKind.linkToExisting,
          stop: stop(),
          place: place(),
          distanceMeters: 42,
        ),
      ],
      locale: const Locale('ar'),
    );

    // The layout must be direction-agnostic: the same card renders with Arabic
    // strings and no overflow/exception in RTL.
    expect(
      Directionality.of(tester.element(find.byType(Card))),
      TextDirection.rtl,
    );
    expect(find.text(l10nAr.suggestedPlaceLinks), findsOneWidget);
    expect(find.text(l10nAr.suggestedPlaceOpenAction), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
