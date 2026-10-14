import 'package:flutter/foundation.dart';

import 'app_health_logger.dart';

/// Coarse issue categories reported through [AppObserverService].
///
/// Kept stable and public so call sites never depend on internal
/// [HealthEventType] names.
enum AppIssueCategory { sync, parsing, ui, performance }

/// Sanitizing facade for "something went wrong" reporting.
///
/// This is the single public entry point for reporting issues. Events are
/// recorded through [AppHealthLogger] — a bounded (ring buffer), Hive-backed,
/// privacy-safe log — with only coarse, non-sensitive fields: a category and a
/// truncated message.
///
/// Raw [error] text is truncated, and [stackTrace] is **never persisted** — it
/// is surfaced only in debug builds via [debugPrint] (MapNote security
/// standard, AGENT_SKILLS.md §2.3): raw transport errors can embed request
/// URIs/headers, and stack traces embed file paths, so neither belongs on
/// disk.
class AppObserverService {
  const AppObserverService(this._logger);

  final AppHealthLogger _logger;

  static const int _maxMessageLength = 120;

  /// Records a sanitized issue event.
  ///
  /// [error] is collapsed to a single line and truncated before it is stored.
  /// [contextData] is merged into the event payload verbatim — keep it small
  /// and free of PII (counts, flags, enum names), matching the logger's
  /// `data` contract.
  void logIssue({
    required AppIssueCategory category,
    required String error,
    String? stackTrace,
    Map<String, dynamic>? contextData,
  }) {
    if (kDebugMode && stackTrace != null && stackTrace.isNotEmpty) {
      debugPrint('MapNote issue [${category.name}]: $stackTrace');
    }

    _logger.log(
      HealthEventType.serviceIssue,
      message: _sanitize(error),
      data: <String, Object?>{
        ...?contextData,
        'category': category.name,
      },
    );
  }

  String _sanitize(String raw) {
    final String flattened = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flattened.length <= _maxMessageLength) return flattened;
    return '${flattened.substring(0, _maxMessageLength - 3)}...';
  }
}