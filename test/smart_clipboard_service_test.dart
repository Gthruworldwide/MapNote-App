import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/services/smart_clipboard_service.dart';

void main() {
  const SmartClipboardService service = SmartClipboardService();

  group('SmartClipboardService.extractPlusCode', () {
    test('finds a full Plus Code inside copied text', () {
      expect(
        service.extractPlusCode('Directions to 8FVC9G8F+6X, Zurich'),
        '8FVC9G8F+6X',
      );
    });

    test('finds a short, locality-relative Plus Code', () {
      expect(service.extractPlusCode('9G8F+6W, Cairo'), '9G8F+6W');
    });

    test('normalises lower case and ignores surrounding whitespace', () {
      expect(service.extractPlusCode(' 8fvc9g8f+6x '), '8FVC9G8F+6X');
    });

    test('returns null for coordinates, prose and empty input', () {
      expect(service.extractPlusCode('30.0444, 31.2357'), isNull);
      expect(service.extractPlusCode('see you there at noon'), isNull);
      expect(service.extractPlusCode(''), isNull);
      expect(service.extractPlusCode(null), isNull);
    });

    test('skips code-shaped text that is not a valid code', () {
      // The alphabet excludes '0', '1', 'A', 'B', 'I', 'L', 'O', 'S', 'U', 'Z',
      // so a string like this cannot be a real Open Location Code.
      expect(service.extractPlusCode('1234+5678'), isNull);
    });
  });

  group('SmartClipboardService.readPlusCode', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('returns the code on the clipboard', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall call,
          ) async {
            if (call.method == 'Clipboard.getData') {
              return <String, dynamic>{'text': '8FVC9G8F+6W'};
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      expect(await service.readPlusCode(), '8FVC9G8F+6W');
    });

    test('returns null when the clipboard holds no code', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall call,
          ) async {
            if (call.method == 'Clipboard.getData') {
              return <String, dynamic>{'text': 'just a note'};
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      expect(await service.readPlusCode(), isNull);
    });

    test('stands down when the platform channel is unavailable', () async {
      // No mock handler: the channel throws, and the service must swallow it.
      expect(await service.readPlusCode(), isNull);
    });
  });
}
