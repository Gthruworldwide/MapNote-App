import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('source secrets hygiene', () {
    test('no Dart source contains a credential-shaped literal', () {
      final List<File> sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File file) => file.path.endsWith('.dart'))
          .toList();
      expect(sources, isNotEmpty);

      final RegExp credentials = RegExp(
        r'AIza[0-9A-Za-z\-_]{20,}|sk-[0-9A-Za-z\-_]{16,}|'
        r'-----BEGIN (RSA |EC )?PRIVATE KEY-----',
      );
      for (final File source in sources) {
        final String text = source.readAsStringSync();
        expect(
          credentials.hasMatch(text),
          isFalse,
          reason: '${source.path} contains a credential-shaped literal',
        );
      }
    });

    test('Geoapify documentation uses a non-key placeholder', () {
      final String config =
          File('lib/src/core/config/app_config.dart').readAsStringSync();

      expect(config, contains('your-geoapify-key'));
    });
  });
}
