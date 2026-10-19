import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/features/saved_places/domain/entities/place_link_suggestion.dart';
import 'package:routenote/src/features/saved_places/domain/entities/trip_stop.dart';
import 'package:routenote/src/features/saved_places/domain/services/place_link_suggester.dart';

/// The geofencing rule engine is pure, so these are fast, deterministic unit
/// tests: no Hive, no platform channels, no timers.
void main() {
  const PlaceLinkSuggester suggester = PlaceLinkSuggester();

  TripStop stop({
    double latitude = 30.0444,
    double longitude = 31.2357,
    Duration dwell = const Duration(minutes: 12),
    DateTime? arrivedAt,
  }) => TripStop(
    latitude: latitude,
    longitude: longitude,
    arrivedAt: arrivedAt ?? DateTime.utc(2026, 10, 19, 9),
    dwell: dwell,
  );

  Place place({
    String id = 'place-1',
    double latitude = 30.0444,
    double longitude = 31.2357,
  }) => Place(
    id: id,
    name: 'Saved $id',
    notes: '',
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime.utc(2026, 1, 1),
  );

  group('suggest', () {
    test('links a stop to the saved place it overlaps', () {
      final List<PlaceLinkSuggestion> result = suggester.suggest(
        stops: <TripStop>[stop()],
        places: <Place>[place()],
      );

      expect(result, hasLength(1));
      expect(result.single.kind, PlaceLinkSuggestionKind.linkToExisting);
      expect(result.single.place?.id, 'place-1');
      expect(result.single.distanceMeters, lessThan(1));
    });

    test('picks the nearest place when several are in range', () {
      final List<PlaceLinkSuggestion> result = suggester.suggest(
        stops: <TripStop>[stop()],
        places: <Place>[
          place(id: 'far', latitude: 30.0450, longitude: 31.2360),
          place(id: 'near', latitude: 30.0444, longitude: 31.2357),
        ],
      );

      expect(result.single.place?.id, 'near');
    });

    test('proposes a new place when nothing is saved nearby', () {
      final List<PlaceLinkSuggestion> result = suggester.suggest(
        stops: <TripStop>[stop()],
        places: <Place>[place(latitude: 31.5, longitude: 32.5)],
      );

      expect(result, hasLength(1));
      expect(result.single.kind, PlaceLinkSuggestionKind.saveAsNew);
      expect(result.single.place, isNull);
      expect(result.single.distanceMeters, 0);
    });

    test('ignores stops shorter than the five minute threshold', () {
      final List<PlaceLinkSuggestion> result = suggester.suggest(
        stops: <TripStop>[
          stop(dwell: const Duration(minutes: 4, seconds: 59)),
        ],
        places: <Place>[place()],
      );

      expect(result, isEmpty);
    });

    test('keeps the newest stops, capped at maxSuggestions', () {
      final List<PlaceLinkSuggestion> result = suggester.suggest(
        stops: <TripStop>[
          stop(arrivedAt: DateTime.utc(2026, 10, 19, 8)),
          stop(arrivedAt: DateTime.utc(2026, 10, 19, 10)),
          stop(arrivedAt: DateTime.utc(2026, 10, 19, 12)),
          stop(arrivedAt: DateTime.utc(2026, 10, 19, 14)),
        ],
        places: const <Place>[],
      );

      expect(result, hasLength(3));
      expect(
        result.map((PlaceLinkSuggestion s) => s.stop.arrivedAt.hour).toList(),
        <int>[14, 12, 10],
      );
    });

    test('respects a custom maxLinkDistanceMeters', () {
      const PlaceLinkSuggester strict = PlaceLinkSuggester(
        maxLinkDistanceMeters: 10,
      );
      // The place sits ~111 m north of the stop.
      final List<PlaceLinkSuggestion> result = strict.suggest(
        stops: <TripStop>[stop()],
        places: <Place>[place(latitude: 30.0454)],
      );

      expect(result.single.kind, PlaceLinkSuggestionKind.saveAsNew);
    });

    test('returns nothing for an empty stop list', () {
      expect(suggester.suggest(stops: const <TripStop>[], places: const <Place>[]), isEmpty);
    });
  });

  group('distanceMeters', () {
    test('approximates one degree of latitude as 111 km', () {
      expect(PlaceLinkSuggester.distanceMeters(0, 0, 1, 0), closeTo(111195, 400));
    });

    test('is zero for identical coordinates', () {
      expect(PlaceLinkSuggester.distanceMeters(30.0, 31.0, 30.0, 31.0), 0);
    });
  });

  group('value objects', () {
    test('PlaceLinkSuggestion compares by value', () {
      final TripStop value = stop();
      expect(
        PlaceLinkSuggestion(
          kind: PlaceLinkSuggestionKind.saveAsNew,
          stop: value,
          distanceMeters: 0,
        ),
        PlaceLinkSuggestion(
          kind: PlaceLinkSuggestionKind.saveAsNew,
          stop: value,
          distanceMeters: 0,
        ),
      );
    });
  });
}
