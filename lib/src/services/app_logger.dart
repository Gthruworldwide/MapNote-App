import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum LogLevel { info, warning, error }

/// Local diagnostics logger for the Supervisor Agent workflow.
///
/// Writes timestamped entries to `app_logs.txt` in the app documents
/// directory. This file is the *single sanctioned* on-disk diagnostics feed
/// (see AGENT_SKILLS.md §1.2): everything else persists through Hive only.
///
/// Safety properties (AGENT_SKILLS.md §2.3):
/// * Entries are credential-redacted and truncated before being written.
/// * The file is bounded ([_maxFileBytes]): when exceeded, only the most
///   recent tail is kept, so it can never grow without limit.
/// * All file I/O is best-effort — a failed write never crashes the app.
///
/// Categories are free-form but should follow the supervisor vocabulary:
/// `SYNC`, `AUTH`, `LOCATION_PARSER`, `UI`, `HIVE_DB`, plus the framework
/// handlers in `main()` (`FLUTTER_FRAMEWORK`, `UNCAUGHT_ASYNC`).
class AppLogger {
  static const String _logFileName = 'app_logs.txt';

  /// The file cap; everything older than the last [size] deleted on trim.
  static const int _maxFileBytes = 256 * 1024;

  /// Injectable cap override so tests can exercise trimming cheaply.
  @visibleForTesting
  static int maxFileBytesOverride = _maxFileBytes;

  /// Per-field caps so one broken value cannot blow up a single entry.
  static const int _maxMessageChars = 500;
  static const int _maxErrorChars = 1500;

  static Future<File> _getLogFile() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_logFileName');
  }

  /// Records a log entry. Never throws: writing is best-effort.
  static Future<void> log({
    required String category, // e.g. 'SYNC', 'LOCATION_PARSER', 'AUTH', 'UI'
    required String message,
    LogLevel level = LogLevel.error,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final String timestamp = DateTime.now().toIso8601String();
    final String logTag = level.name.toUpperCase();

    final StringBuffer buffer = StringBuffer();
    buffer
      .writeln(
        '[$timestamp] [$logTag] [$category] '
        '${_clip(_flatten(message), _maxMessageChars)}',
      );
    if (error != null) {
      buffer.writeln('  ErrorDetails: ${_clip(_flatten(error.toString()), _maxErrorChars)}');
    }
    if (stackTrace != null) {
      buffer.writeln('  StackTrace: ${_clip(stackTrace.toString(), _maxErrorChars)}');
    }

    final String entry = _redact(buffer.toString());

    if (kDebugMode) {
      debugPrint(entry);
    }

    try {
      final File file = await _getLogFile();
      await file.writeAsString(entry, mode: FileMode.append, flush: true);
      await _trimToBudget(file);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to write log to file: $e');
      }
    }
  }

  /// Drops the oldest part of the file once it exceeds [_maxFileBytes],
  /// always cutting on a line boundary so entries stay parseable.
  static Future<void> _trimToBudget(File file) async {
    final int length = await file.length();
    if (length <= maxFileBytesOverride) return;
    final String content = await file.readAsString();
    final int budget = maxFileBytesOverride;
    final String tail = content.substring(content.length - budget);
    // Jump to the next "[timestamp] [LEVEL] [CATEGORY]" line after the cut.
    final int marker = tail.indexOf('\n[');
    await file.writeAsString(marker >= 0 ? tail.substring(marker + 1) : tail);
  }

  /// Collapses whitespace/newlines so single entries stay on one field.
  static String _flatten(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _clip(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max - 3)}...';

  /// Defense-in-depth redaction applied to every written entry.
  static final List<RegExp> _sensitivePatterns = <RegExp>[
    // Google API keys (AIza...).
    RegExp(r'AIza[0-9A-Za-z\-_]{20,}'),
    // Bearer tokens.
    RegExp(r'[Bb]earer\s+[A-Za-z0-9\-._~+/]+'),
    // `x-goog-api-key:` / `api_key=` / `authorization=` / `token=` values.
    RegExp(
      r'(?:x-goog-api-key|api[_-]?key|authorization|token)\s*[:=]\s*\S+',
      caseSensitive: false,
    ),
    // Emails.
    RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}'),
    // Long base64-ish tokens (32+ chars).
    RegExp(r'[A-Za-z0-9+/]{32,}={0,2}'),
  ];

  static String _redact(String value) {
    for (final RegExp pattern in _sensitivePatterns) {
      value = value.replaceAll(pattern, '[redacted]');
    }
    return value;
  }

  /// Reads the current log content (used by the supervisor agent).
  static Future<String> readLogs() async {
    try {
      final File file = await _getLogFile();
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      debugPrint('Error reading log file: $e');
    }
    return '';
  }

  /// Clears the log file after it has been processed by the supervisor.
  static Future<void> clearLogs() async {
    try {
      final File file = await _getLogFile();
      if (await file.exists()) {
        await file.writeAsString('');
      }
    } catch (e) {
      debugPrint('Error clearing log file: $e');
    }
  }
}