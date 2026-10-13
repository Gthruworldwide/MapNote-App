import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/features/home/widgets/place_card.dart';

void main() {
  Place place({bool isLocked = false}) => Place(
    id: 'place-1',
    name: 'Secret Spot',
    notes: 'private journal',
    latitude: 30.0444,
    longitude: 31.2357,
    timestamp: DateTime(2026, 1, 1),
    isLocked: isLocked,
  );

  Future<void> pumpCard(WidgetTester tester, Place value) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PlaceCard(place: value, onTap: () {}, onNavigate: () {}),
        ),
      ),
    );
  }

  testWidgets('locked place masks title, notes and coordinates', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, place(isLocked: true));

    // Raw sensitive text must never appear on screen while locked.
    expect(find.text('Secret Spot'), findsNothing);
    expect(find.text('private journal'), findsNothing);
    expect(find.textContaining('30.044'), findsNothing);
    expect(find.textContaining('31.235'), findsNothing);
    // The Plus Code encodes the exact location, so it is hidden too.
    expect(find.text('8G2H26VP+Q7'), findsNothing);

    // The lock indicator is still visible so the row is recognizable.
    expect(find.byIcon(Icons.lock), findsOneWidget);
  });

  testWidgets('unlocked place shows title, notes and coordinates', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, place(isLocked: false));

    expect(find.text('Secret Spot'), findsOneWidget);
    expect(find.text('private journal'), findsOneWidget);
    expect(find.textContaining('30.044'), findsOneWidget);
    // The derived Plus Code for these coordinates is shown alongside them.
    expect(find.text('8G2H26VP+Q7'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsNothing);
  });
}
