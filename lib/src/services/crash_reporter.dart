import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'diagnostic_redaction.dart';

/// The only Crashlytics operation MapNote needs.
///
/// The sink receives already-redacted strings, never the original exception or
/// stack object, so a future caller cannot accidentally forward a live token.
abstract interface class CrashReportSink {
  Future<void> record({
    required String error,
    required String stack,
    required bool fatal,
  });
}

class FirebaseCrashReportSink implements CrashReportSink {
  const FirebaseCrashReportSink(this._crashlytics);

  final FirebaseCrashlytics _crashlytics;

  @override
  Future<void> record({
    required String error,
    required String stack,
    required bool fatal,
  }) =>
      _crashlytics.recordError(
        error,
        StackTrace.fromString(stack),
        fatal: fatal,
      );
}

/// Global-handler-facing reporter that redacts before handing anything over.
abstract interface class CrashReporter {
  void recordFlutterFatalError(FlutterErrorDetails details);

  void recordError(Object error, StackTrace stack, {required bool fatal});
}

class RedactedCrashReporter implements CrashReporter {
  const RedactedCrashReporter(this._sink);

  final CrashReportSink _sink;

  @override
  void recordFlutterFatalError(FlutterErrorDetails details) => _report(
        error: redactForDiagnostics(details.exceptionAsString()),
        stack: redactForDiagnostics(details.stack?.toString() ?? ''),
        fatal: true,
      );

  @override
  void recordError(Object error, StackTrace stack, {required bool fatal}) =>
      _report(
        error: redactForDiagnostics(error.toString()),
        stack: redactForDiagnostics(stack.toString()),
        fatal: fatal,
      );

  void _report({
    required String error,
    required String stack,
    required bool fatal,
  }) {
    unawaited(
      (() async {
        try {
          await _sink.record(error: error, stack: stack, fatal: fatal);
        } catch (_) {
          // Best-effort diagnostics: a failed upload must never escape a
          // global error handler and become a second crash.
        }
      })(),
    );
  }
}
