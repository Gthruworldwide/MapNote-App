import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:routenote/src/services/app_logger.dart';

class FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('app_logger_test_');
    PathProviderPlatform.instance = FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('logs error message to app_logs.txt and reads them back', () async {
    await AppLogger.log(
      category: 'SYNC',
      message: 'Failed to connect to Google Drive',
      level: LogLevel.error,
      error: 'Network Timeout',
    );

    final String logs = await AppLogger.readLogs();
    expect(logs, contains('[ERROR] [SYNC] Failed to connect to Google Drive'));
    expect(logs, contains('ErrorDetails: Network Timeout'));
  });

  test('clears log file when clearLogs is called', () async {
    await AppLogger.log(
      category: 'LOCATION_PARSER',
      message: 'Invalid coordinates format',
      level: LogLevel.warning,
    );

    expect(await AppLogger.readLogs(), isNotEmpty);

    await AppLogger.clearLogs();

    expect(await AppLogger.readLogs(), isEmpty);
  });

  test('redacts credential-like values before writing', () async {
    const String apiKey = 'AIzaSyDeAdBeEf0000000000000000000000000';
    await AppLogger.log(
      category: 'SYNC',
      message: 'request failed',
      error: 'x-goog-api-key=$apiKey token=abc123def456ghi789jkl012mno345pqr678stu',
    );

    final String logs = await AppLogger.readLogs();
    expect(logs, isNot(contains(apiKey)));
    expect(logs, isNot(contains('x-goog-api-key')));
    expect(logs, isNot(contains('abc123def456ghi789jkl012mno345pqr678stu')));
    expect(logs, contains('[redacted]'));
  });

  test('bounds the log file and trims older entries', () async {
    AppLogger.maxFileBytesOverride = 2048;
    addTearDown(() => AppLogger.maxFileBytesOverride = 256 * 1024);

    for (int i = 0; i < 60; i++) {
      await AppLogger.log(
        category: 'UI',
        message: 'performance entry number $i',
        level: LogLevel.info,
      );
    }

    final String logs = await AppLogger.readLogs();
    expect(logs.length, lessThanOrEqualTo(2048));
    expect(logs, startsWith('['), reason: 'trim must cut on a line boundary');
    expect(logs, contains('performance entry number 59'), reason: 'newest entry kept');
  });

  test('serialises concurrent writes without losing an entry', () async {
    addTearDown(() => AppLogger.maxFileBytesOverride = 256 * 1024);

    // Fire every write before awaiting any of them: without serialisation the
    // append + trim read-modify-write of one entry could clobber another.
    await Future.wait(<Future<void>>[
      for (int i = 0; i < 40; i++)
        AppLogger.log(
          category: 'UI',
          message: 'concurrent entry $i',
          level: LogLevel.info,
        ),
    ]);

    final String logs = await AppLogger.readLogs();
    for (int i = 0; i < 40; i++) {
      expect(logs, contains('concurrent entry $i'));
    }
  });

  test('trims whole lines without splitting multi-byte Arabic text', () async {
    AppLogger.maxFileBytesOverride = 400;
    addTearDown(() => AppLogger.maxFileBytesOverride = 256 * 1024);

    // Arabic characters are multiple UTF-8 bytes each; a naive cut would slice
    // one in half and decode it back as the U+FFFD replacement character.
    for (int i = 0; i < 40; i++) {
      await AppLogger.log(
        category: 'UI',
        message: 'الإحداثيات $i',
        level: LogLevel.info,
      );
    }

    final String logs = await AppLogger.readLogs();
    expect(utf8.encode(logs).length, lessThanOrEqualTo(400));
    expect(logs, startsWith('['), reason: 'trim must cut on a line boundary');
    expect(logs, contains('الإحداثيات 39'), reason: 'newest entry kept');
    expect(logs.contains('\uFFFD'), isFalse, reason: 'no half-cut character');
  });
}
