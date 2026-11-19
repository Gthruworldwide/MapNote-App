import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:routenote/src/services/geoapify_client.dart';
import 'package:routenote/src/services/geocoding_service.dart';

GeocodingService _service(http.Client client) => GeocodingService(
  isCloudEnabled: true,
  geoApifyClient: GeoapifyClient(httpClient: client, apiKey: 'test-key'),
);

http.Client _client({
  List<Map<String, dynamic>> results = const <Map<String, dynamic>>[],
  bool throwing = false,
}) => MockClient((http.Request request) async {
  if (throwing) throw StateError('offline');
  return http.Response(
    '{"results":${_encode(results)}}',
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );
});

String _encode(List<Map<String, dynamic>> results) {
  if (results.isEmpty) return '[]';
  final Map<String, dynamic> first = results.first;
  return '[{"lat":${first['lat']},"lon":${first['lon']},'
      '"formatted":"${first['formatted']}","country":"${first['country']}"}]';
}

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
      expect(suggestion.detail, isEmpty);
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
    test('maps a Geoapify result onto a suggestion', () async {
      final List<Uri> requests = <Uri>[];
      final http.Client client = MockClient((http.Request request) async {
        requests.add(request.url);
        return http.Response(
          '{"results":[{"lat":30.0459,"lon":31.2243,'
          '"formatted":"Cairo Tower, 26th of July Corridor, Cairo, Egypt",'
          '"country":"Egypt"}]}',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      final PlaceSuggestion? suggestion = await _service(client).reverse(
        latitude: 30.0459,
        longitude: 31.2243,
      );

      expect(suggestion, isNotNull);
      expect(
        suggestion!.title,
        'Cairo Tower, 26th of July Corridor, Cairo, Egypt',
      );
      expect(
        suggestion.detail,
        '26th of July Corridor, Cairo, Egypt',
      );
      expect(requests, hasLength(1));
      expect(requests.single.host, 'api.geoapify.com');
      expect(requests.single.queryParameters['lat'], '30.045900');
      expect(requests.single.queryParameters['lon'], '31.224300');
    });

    test('returns null when the provider has nothing to say', () async {
      final PlaceSuggestion? suggestion = await _service(_client()).reverse(
        latitude: 0,
        longitude: 0,
      );
      expect(suggestion, isNull);
    });

    test('swallows a provider failure instead of throwing', () async {
      final PlaceSuggestion? suggestion = await _service(
        _client(throwing: true),
      ).reverse(latitude: 0, longitude: 0);
      expect(suggestion, isNull);
    });

    test('makes no request when cloud geocoding is disabled', () async {
      int calls = 0;
      final http.Client client = MockClient((http.Request request) async {
        calls++;
        return http.Response('{}', 200);
      });
      final GeocodingService service = GeocodingService(
        isCloudEnabled: false,
        geoApifyClient: GeoapifyClient(httpClient: client, apiKey: 'test-key'),
      );

      expect(await service.reverse(latitude: 1, longitude: 2), isNull);
      expect(calls, 0);
    });
  });

  group('GeocodingService.forward', () {
    test('is an alias of reverse for coordinate-based lookups', () async {
      final PlaceSuggestion? suggestion = await _service(
        _client(results: <Map<String, dynamic>>[
          <String, dynamic>{
            'lat': 30.0444,
            'lon': 31.2357,
            'formatted': 'Cairo, Egypt',
            'country': 'Egypt',
          },
        ]),
      ).forward(latitude: 30.0444, longitude: 31.2357);

      expect(suggestion, isNotNull);
      expect(suggestion!.title, 'Cairo, Egypt');
    });
  });
}
