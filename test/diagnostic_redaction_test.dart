import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/services/diagnostic_redaction.dart';

void main() {
  group('shared diagnostic redaction', () {
    const String apiKey = 'AIzaSyTESTTESTTESTTESTTESTTESTTESTTESTTEST';
    const String bearer = 'Bearer abcdefghijklmnopqrstuvwxyz0123456789';

    test('strips credential shapes from every sink', () {
      final String redacted = redactForDiagnostics(
        'x-goog-api-key=$apiKey $bearer user@example.com '
        'sk-abcdefghijklmnopqrstuvwxyz',
      );

      expect(redacted, isNot(contains(apiKey)));
      expect(redacted, isNot(contains('Bearer')));
      expect(redacted, isNot(contains('user@example.com')));
      expect(redacted, isNot(contains('sk-abcdefghijklmnopqrstuvwxyz')));
      expect(redacted, contains('[redacted]'));
    });

    test('strips user home directories from stacks', () {
      const String path = 'file:///Users/testuser/projects/routenote/lib/main.dart';
      final String redacted = redactForDiagnostics(path);

      expect(redacted, isNot(contains('testuser')));
      expect(redacted, isNot(contains(path)));
    });

    test('bounds remote values so one exception cannot flood a sink', () {
      final String redacted = redactForDiagnostics(('word ' * 400).trim());

      expect(redacted.length, diagnosticMaxChars);
      expect(redacted.endsWith('...'), isTrue);
    });
  });
}
