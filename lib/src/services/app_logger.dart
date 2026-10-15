import 'dart:async';
import 'dart:convert';
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
/// * Every file operation is serialised, so concurrent writers can never
///   interleave the append + trim read-modify-write and lose an entry.
/// * Trimming cuts on whole-line boundaries only, so multi-byte UTF-8 text
///   (Arabic, emoji) is never split into a broken character.
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

  /// Serialises every file operation through a single chain, so the
  /// append + trim read-modify-write in [log] can never interleave with a
  /// concurrent write or read and lose or duplicate an entry.
  static Future<void> _ioChain = Future<void>.value();

  /// Runs [action] only after every previously queued file operation has
  /// finished, completing with its result (or error). The chain itself never
  /// fails, so one bad operation cannot poison the operations queued after it.
  static Future<T> _serialize<T>(Future<T> Function() action) {
    final Completer<T> completer = Completer<T>();
    _ioChain = _ioChain.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
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
      await _serialize(() async {
        final File file = await _getLogFile();
        await file.writeAsString(entry, mode: FileMode.append, flush: true);
        await _trimToBudget(file);
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to write log to file: $e');
      }
    }
  }

  /// Drops the oldest part of the file once it exceeds [_maxFileBytes],
  /// keeping only the newest whole lines that still fit the budget.
  ///
  /// Working backwards one complete line at a time means the cut can never fall
  /// inside a UTF-16 surrogate pair or a multi-byte UTF-8 sequence, so Arabic
  /// text (and emoji) is never split into a corrupted character and every
  /// retained entry stays intact and parseable.
  static Future<void> _trimToBudget(File file) async {
    final int budget = maxFileBytesOverride;
    if (await file.length() <= budget) return;

    final List<String> lines = (await file.readAsString()).split('\n');

    // Keep the newest suffix whose UTF-8 size fits the budget. The `+1` per
    // line accounts for its trailing '\n'; it over-counts the final (empty)
    // segment by one byte, so this trims a hair more — never less.
    final List<String> kept = <String>[];
    int bytes = 0;
    for (int i = lines.length - 1; i >= 0; i--) {
      final int lineBytes = utf8.encode(lines[i]).length + 1;
      if (kept.isNotEmpty && bytes + lineBytes > budget) break;
      kept.add(lines[i]);
      bytes += lineBytes;
    }

    await file.writeAsString(kept.reversed.join('\n'));
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
      return await _serialize(() async {
        final File file = await _getLogFile();
        if (await file.exists()) {
          return await file.readAsString();
        }
        return '';
      });
    } catch (e) {
      debugPrint('Error reading log file: $e');
      return '';
    }
  }

  /// Clears the log file after it has been processed by the supervisor.
  static Future<void> clearLogs() async {
    try {
      await _serialize(() async {
        final File file = await _getLogFile();
        if (await file.exists()) {
          await file.writeAsString('');
        }
      });
    } catch (e) {
      debugPrint('Error clearing log file: $e');
    }
  }
}