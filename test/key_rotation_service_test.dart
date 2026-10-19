import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/core/config/app_config.dart';
import 'package:routenote/src/services/key_rotation_service.dart';

void main() {
  group('KeyRotationService pool', () {
    test('trims, drops blanks and de-duplicates while keeping priority order', () {
      final KeyRotationService service = KeyRotationService(
        keys: <String>['primary', '  fallback  ', '', 'primary', 'third'],
      );
      expect(service.keys, <String>['primary', 'fallback', 'third']);
      expect(service.length, 3);
      expect(service.hasKeys, isTrue);
    });

    test('reports no keys when every entry is blank', () {
      final KeyRotationService service = KeyRotationService(
        keys: <String>['', '   '],
      );
      expect(service.hasKeys, isFalse);
      expect(service.currentKey, isNull);
    });

    test('never exposes key material through toString', () {
      final KeyRotationService service = KeyRotationService(
        keys: <String>['super-secret-key'],
      );
      expect(service.toString(), isNot(contains('super-secret-key')));
    });
  });

  group('KeyRotationService rotation', () {
    late DateTime now;

    KeyRotationService build() => KeyRotationService(
      keys: <String>['a', 'b'],
      clock: () => now,
      cooldown: const Duration(minutes: 10),
    );

    setUp(() {
      now = DateTime.utc(2026, 1, 1, 12);
    });

    test('starts on the first key', () {
      expect(build().currentKey, 'a');
    });

    test('markFailure rotates to the next healthy key', () {
      final KeyRotationService service = build();
      service.markFailure('a', statusCode: 429);
      expect(service.failuresFor('a'), 1);
      expect(service.currentKey, 'b');
      expect(service.hasHealthyKey, isTrue);
    });

    test('a cooled-down key recovers after the cooldown elapses', () {
      final KeyRotationService service = KeyRotationService(
        keys: <String>['only'],
        clock: () => now,
        cooldown: const Duration(minutes: 10),
      );
      service.markFailure('only');
      expect(service.hasHealthyKey, isFalse);

      now = now.add(const Duration(minutes: 11));
      expect(service.hasHealthyKey, isTrue);
    });

    test('when every key is cooling down, returns the soonest to recover', () {
      final KeyRotationService service = build();
      service.markFailure('a');
      now = now.add(const Duration(minutes: 1));
      service.markFailure('b');

      // "a" recovers one minute before "b", so it is retried first.
      expect(service.hasHealthyKey, isFalse);
      expect(service.currentKey, 'a');
    });

    test('markSuccess clears a key and pins the cursor to it', () {
      final KeyRotationService service = build();
      service.markFailure('a', statusCode: 429);
      expect(service.currentKey, 'b');

      service.markSuccess('a');
      expect(service.failuresFor('a'), 0);
      expect(service.hasHealthyKey, isTrue);
      expect(service.currentKey, 'a');
    });

    test('reset forgets failures and returns to the first key', () {
      final KeyRotationService service = build();
      service.markFailure('a');
      service.reset();
      expect(service.failuresFor('a'), 0);
      expect(service.currentKey, 'a');
      expect(service.hasHealthyKey, isTrue);
    });

    test('ignores failures reported for a key it does not own', () {
      final KeyRotationService service = build();
      service.markFailure('not-mine');
      expect(service.failuresFor('not-mine'), 0);
      expect(service.currentKey, 'a');
    });
  });

  group('KeyRotationService.looksLikeKeyError', () {
    test('treats auth and quota statuses as key failures', () {
      expect(KeyRotationService.looksLikeKeyError(401, ''), isTrue);
      expect(KeyRotationService.looksLikeKeyError(403, ''), isTrue);
      expect(KeyRotationService.looksLikeKeyError(429, ''), isTrue);
    });

    test('detects an invalid-key 400 but not a generic 400', () {
      expect(
        KeyRotationService.looksLikeKeyError(400, '{"reason":"API_KEY_INVALID"}'),
        isTrue,
      );
      expect(
        KeyRotationService.looksLikeKeyError(
          400,
          'API key not valid. Please pass a valid API key.',
        ),
        isTrue,
      );
      expect(
        KeyRotationService.looksLikeKeyError(400, '{"error":"bad request"}'),
        isFalse,
      );
    });

    test('does not treat server or success responses as key failures', () {
      expect(KeyRotationService.looksLikeKeyError(200, ''), isFalse);
      expect(KeyRotationService.looksLikeKeyError(500, ''), isFalse);
    });
  });

  group('AppConfig.parseGeminiApiKeys', () {
    test('splits on commas, semicolons and whitespace and de-duplicates', () {
      expect(
        AppConfig.parseGeminiApiKeys(' one, two ;three\nfour  one '),
        <String>['one', 'two', 'three', 'four'],
      );
    });

    test('returns an empty pool for an empty or blank value', () {
      expect(AppConfig.parseGeminiApiKeys(''), isEmpty);
      expect(AppConfig.parseGeminiApiKeys('   ,  ; '), isEmpty);
    });
  });
}
