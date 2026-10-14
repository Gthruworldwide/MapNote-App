import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';

import 'package:routenote/src/services/geocoding_service.dart';

void main() {
  group('PlaceSuggestion', () {
    test('title prefers the most specific field available', () {
      const PlaceSuggestion suggestion = PlaceSuggestion(
        name: 'Cairo Tower',
        street: '26th of July Corridor',
        locality: 'Cairo',
      );
      expect(suggestion.title, 'Cairo Tower');
      expect(suggestion.isEmpty, isFalse);
    });

    test('title falls back through street → locality → country', () {
      expect(
        const PlaceSuggestion(street: 'Baker Street').title,
        'Baker Street',
      );
      expect(const PlaceSuggestion(locality: 'Zurich').title, 'Zurich');
      expect(const PlaceSuggestion(country: 'Egypt').title, 'Egypt');
    });

    test('detail joins the breakdown without repeating fields', () {
      const PlaceSuggestion suggestion = PlaceSuggestion(
        street: 'Baker Street',
        locality: 'London',
        country: 'United Kingdom',
      );
      expect(suggestion.detail, 'Baker Street, London, United Kingdom');
    });

    test('a suggestion with no usable field is empty', () {
      const PlaceSuggestion suggestion = PlaceSuggestion(
        name: '   ',
        street: '',
      );
      expect(suggestion.title, isNull);
      expect(suggestion.isEmpty, isTrue);
      expect(suggestion.detail, isNull);
    });

    test('fromPlacemark trims the platform fields', () {
      const Placemark mark = Placemark(
        name: '  Cairo Tower ',
        thoroughfare: '26th of July Corridor',
        locality: 'Cairo',
        country: 'Egypt',
      );
      final PlaceSuggestion suggestion = PlaceSuggestion.fromPlacemark(mark);
      expect(suggestion.title, 'Cairo Tower');
      expect(suggestion.street, '26th of July Corridor');
      expect(suggestion.detail, '26th of July Corridor, Cairo, Egypt');
    });
  });

  group('GeocodingService.reverse', () {
    test('maps the first usable placemark onto a suggestion', () async {
      final GeocodingService service = GeocodingService(
        placemarkLookup: (double latitude, double longitude) async =>
            <Placemark>[
              const Placemark(), // empty mark: skipped
              const Placemark(name: 'Cairo Tower', locality: 'Cairo'),
            ],
      );

      final PlaceSuggestion? suggestion = await service.reverse(
        latitude: 30.0459,
        longitude: 31.2243,
      );
      expect(suggestion, isNotNull);
      expect(suggestion!.title, 'Cairo Tower');
    });

    test('returns null when the geocoder has nothing to say', () async {
      final GeocodingService service = GeocodingService(
        placemarkLookup: (double latitude, double longitude) async =>
            const <Placemark>[],
      );
      expect(
        await service.reverse(latitude: 0, longitude: 0),
        isNull,
      );
    });

    test('swallows a platform failure instead of throwing', () async {
      final GeocodingService service = GeocodingService(
        placemarkLookup: (double latitude, double longitude) async =>
            throw Exception('no geocoder'),
      );
      expect(await service.reverse(latitude: 0, longitude: 0), isNull);
    });
  });

  group('GeocodingService.forward', () {
    test('resolves a city name to coordinates', () async {
      final GeocodingService service = GeocodingService(
        locationLookup: (String address) async => <Location>[
          const Location(latitude: 30.0444, longitude: 31.2357),
        ],
      );

      final point = await service.forward('Cairo');
      expect(point, isNotNull);
      expect(point!.latitude, 30.0444);
      expect(point.longitude, 31.2357);
    });

    test('returns null for blank input without calling the platform', () async {
      bool called = false;
      final GeocodingService service = GeocodingService(
        locationLookup: (String address) async {
          called = true;
          return const <Location>[];
        },
      );
      expect(await service.forward('   '), isNull);
      expect(called, isFalse);
    });

    test('returns null when the lookup fails', () async {
      final GeocodingService service = GeocodingService(
        locationLookup: (String address) async => throw Exception('offline'),
      );
      expect(await service.forward('Cairo'), isNull);
    });
  });
}
