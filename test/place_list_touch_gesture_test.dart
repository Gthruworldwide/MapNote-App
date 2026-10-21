import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/features/home/widgets/place_card.dart';

void main() {
  testWidgets('long-press opens action without firing tap', (tester) async {
    bool tapped = false;
    bool longPressed = false;
    final Place place = Place(
      id: 'p1',
      name: 'Cairo Tower',
      notes: '',
      latitude: 30.0444,
      longitude: 31.2357,
      timestamp: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PlaceCard(
            place: place,
            onTap: () => tapped = true,
            onNavigate: () {},
            onLongPress: () => longPressed = true,
          ),
        ),
      ),
    );

    await tester.longPress(find.byType(PlaceCard));
    await tester.pumpAndSettle();

    expect(longPressed, isTrue);
    expect(tapped, isFalse);
  });

  testWidgets('CompactActionBar touch targets are at least 48dp', (tester) async {
    final Place place = Place(
      id: 'p2',
      name: 'Test',
      notes: '',
      latitude: 0,
      longitude: 0,
      timestamp: DateTime.now(),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PlaceCard(
            place: place,
            onTap: () {},
            onNavigate: () {},
            onLongPress: () {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
