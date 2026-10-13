import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/core/utils/plus_code.dart';
import 'package:routenote/src/data/models/place.dart';

void main() {
  group('PlusCode.encode', () {
    test('matches the reference Open Location Code vectors', () {
      // The canonical OLC README example (Zurich) and a spread of hemispheres,
      // pinned so a regression in the wrapper or a swapped dependency is caught.
      expect(PlusCode.encode(47.365590, 8.524997), '8FVC9G8F+6X');
      expect(PlusCode.encode(37.422, -122.084), '849VCWC8+RC');
      expect(PlusCode.encode(0, 0), '6FG22222+22');
      expect(PlusCode.encode(-33.8688, 151.2093), '4RRH46J5+FP');
    });

    test('defaults to a ten-digit global code', () {
      final String code = PlusCode.encode(30.0444, 31.2357);
      expect(code.length, 11, reason: '10 significant digits plus the "+"');
      expect(code[8], '+');
    });

    test('clips latitude and normalises longitude instead of throwing', () {
      // Latitude 90 cannot be decoded as-is, so the encoder nudges it south.
      expect(() => PlusCode.encode(90, 180), returnsNormally);
      expect(PlusCode.isPlusCode(PlusCode.encode(90, 180)), isTrue);
    });
  });

  group('PlusCode.isPlusCode', () {
    test('accepts full codes, including grouped and lowercase forms', () {
      expect(PlusCode.isPlusCode('8FVC9G8F+6X'), isTrue);
      expect(PlusCode.isPlusCode('8FVC 9G8F+6X'), isTrue);
      expect(PlusCode.isPlusCode('8fvc9g8f+6x'), isTrue);
      expect(PlusCode.isPlusCode(' 8FVC9G8F+6X '), isTrue);
    });

    test('rejects short codes, coordinates and arbitrary text', () {
      expect(PlusCode.isPlusCode('9G8F+6X'), isFalse,
          reason: 'short codes need a reference location');
      expect(PlusCode.isPlusCode('30.0444, 31.2357'), isFalse);
      expect(PlusCode.isPlusCode('hello world'), isFalse);
      expect(PlusCode.isPlusCode(''), isFalse);
    });
  });

  group('PlusCode.decode', () {
    test('returns the centre of the decoded cell', () {
      final PlusCodePoint? point = PlusCode.decode('8FVC9G8F+6W');
      expect(point, isNotNull);
      expect(point!.latitude, closeTo(47.3655625, 1e-9));
      expect(point.longitude, closeTo(8.5248125, 1e-9));
    });

    test('round-trips through encode', () {
      const String code = '8FVC9G8F+6W';
      final PlusCodePoint point = PlusCode.decode(code)!;
      expect(PlusCode.encode(point.latitude, point.longitude), code);
    });

    test('normalises whitespace and case before decoding', () {
      final PlusCodePoint? spaced = PlusCode.decode('8fvc 9g8f+6w');
      expect(spaced, isNotNull);
      expect(spaced!.latitude, closeTo(47.3655625, 1e-9));
    });

    test('returns null for anything that is not a full code', () {
      expect(PlusCode.decode('9G8F+6W'), isNull);
      expect(PlusCode.decode('not a code'), isNull);
      expect(PlusCode.decode(''), isNull);
    });
  });

  group('Place.plusCode', () {
    test('is derived from the coordinates, never stored', () {
      final Place place = Place(
        id: 'p1',
        name: 'Blue Gate car park',
        notes: '',
        latitude: 47.365590,
        longitude: 8.524997,
        timestamp: DateTime.utc(2026, 1, 1),
      );

      expect(place.plusCode, '8FVC9G8F+6X');

      // The stored map keeps only the source of truth...
      expect(place.toMap().containsKey('plusCode'), isFalse);
      // ...while the exported JSON carries the derived code.
      expect(place.toJson()['plusCode'], '8FVC9G8F+6X');

      // Moving the pin moves the code.
      expect(place.copyWith(latitude: 0, longitude: 0).plusCode,
          '6FG22222+22');
    });
  });
}
