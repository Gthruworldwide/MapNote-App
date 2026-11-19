import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/features/home/home_screen.dart';
import 'package:routenote/src/services/home_shortcut_service.dart';

void main() {
  Place buildPlace({
    required String id,
    required String name,
    bool isLocked = false,
    bool isPinned = false,
    bool isHidden = false,
  }) {
    return Place(
      id: id,
      name: name,
      notes: 'private note $id',
      latitude: 30.0444,
      longitude: 31.2357,
      timestamp: DateTime.utc(2026, 1, 1),
      isLocked: isLocked,
      isPinned: isPinned,
      isHidden: isHidden,
    );
  }

  group('Home search', () {
    test('locked places are excluded from every search query', () {
      final List<Place> places = <Place>[
        buildPlace(id: 'locked', name: 'Cairo Tower', isLocked: true),
        buildPlace(id: 'open', name: 'Open Place'),
      ];

      for (final String query in <String>[
        'cairo',
        'private note locked',
        places.first.plusCode,
        places.first.notes,
      ]) {
        expect(
          filterPlacesForQuery(places, query).map((Place p) => p.id),
          isNot(contains('locked')),
          reason: 'query "$query" must not match a locked place',
        );
      }

      expect(
        filterPlacesForQuery(places, 'open').map((Place p) => p.id),
        <String>['open'],
      );
    });

    test('empty query keeps locked rows in the masked list', () {
      final List<Place> places = <Place>[
        buildPlace(id: 'locked', name: 'Cairo Tower', isLocked: true),
        buildPlace(id: 'open', name: 'Open Place'),
      ];

      expect(filterPlacesForQuery(places, ''), places);
    });
  });

  group('OS launcher shortcuts', () {
    test('locked, hidden and unpinned places are never exported', () {
      final List<Place> places = <Place>[
        buildPlace(id: 'pinned', name: 'Pinned', isPinned: true),
        buildPlace(
          id: 'locked',
          name: 'Secret Tower',
          isLocked: true,
          isPinned: true,
        ),
        buildPlace(
          id: 'hidden',
          name: 'Hidden Tower',
          isHidden: true,
          isPinned: true,
        ),
        buildPlace(id: 'loose', name: 'Not Pinned'),
      ];

      expect(
        shortcutEligiblePlaces(places).map((Place p) => p.id),
        <String>['pinned'],
      );
    });

    test('at most four eligible places are exported, in order', () {
      final List<Place> places = <Place>[
        for (int i = 0; i < 6; i++)
          buildPlace(id: 'p$i', name: 'Place $i', isPinned: true),
      ];

      expect(
        shortcutEligiblePlaces(places).map((Place p) => p.id),
        <String>['p0', 'p1', 'p2', 'p3'],
      );
    });
  });
}
