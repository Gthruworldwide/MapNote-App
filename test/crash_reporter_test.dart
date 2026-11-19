import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/services/crash_reporter.dart';

class _RecordedReport {
  const _RecordedReport(this.error, this.stack, this.fatal);

  final String error;
  final String stack;
  final bool fatal;
}

class _RecordingSink implements CrashReportSink {
  final List<_RecordedReport> reports = <_RecordedReport>[];

  @override
  Future<void> record({
    required String error,
    required String stack,
    required bool fatal,
  }) async {
    reports.add(_RecordedReport(error, stack, fatal));
  }
}

void main() {
  const String secret = 'AIzaSyTESTTESTTESTTESTTESTTESTTESTTESTTEST';
  const String home = 'file:///Users/testuser/projects/routenote/lib/main.dart';

  test('global async handler reports only redacted strings', () async {
    final _RecordingSink sink = _RecordingSink();
    final RedactedCrashReporter reporter = RedactedCrashReporter(sink);

    reporter.recordError(
      Exception('x-goog-api-key=$secret'),
      StackTrace.fromString(home),
      fatal: true,
    );
    await pumpEventQueue();

    expect(sink.reports, hasLength(1));
    final _RecordedReport report = sink.reports.single;
    expect(report.error, isNot(contains(secret)));
    expect(report.stack, isNot(contains('testuser')));
    expect(report.fatal, isTrue);
  });

  test('framework handler reports only redacted strings', () async {
    final _RecordingSink sink = _RecordingSink();
    final RedactedCrashReporter reporter = RedactedCrashReporter(sink);

    reporter.recordFlutterFatalError(
      FlutterErrorDetails(
        exception: Exception('token=$secret'),
        stack: StackTrace.fromString(home),
      ),
    );
    await pumpEventQueue();

    expect(sink.reports, hasLength(1));
    expect(sink.reports.single.error, isNot(contains(secret)));
    expect(sink.reports.single.stack, isNot(contains('testuser')));
  });
}
