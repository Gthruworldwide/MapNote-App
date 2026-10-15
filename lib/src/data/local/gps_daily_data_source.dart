import 'package:hive_ce/hive.dart';

import '../models/daily_gps_summary.dart';
import 'daily_track_store.dart';

/// Persists one [DailyGpsSummary] per calendar day.
///
/// Summaries live in a Hive box under a namespaced key
/// (`gps_daily.<yyyy-MM-dd>`) so they never collide with settings keys.
/// Writes are flushed to disk immediately so a tracked day is never lost.
class GpsDailyDataSource implements DailyTrackStore {
  GpsDailyDataSource(this._box);

  final Box<dynamic> _box;

  static const String _prefix = 'gps_daily.';

  /// The stored summary for [day], or null when nothing was tracked that day.
  @override
  DailyGpsSummary? summaryFor(DateTime day) {
    final Object? raw = _box.get(_prefix + DailyGpsSummary.dayKey(day));
    if (raw is Map) {
      return DailyGpsSummary.fromMap(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  @override
  Future<void> save(DailyGpsSummary summary) async {
    await _box.put(
      _prefix + DailyGpsSummary.dayKey(summary.date),
      summary.toMap(),
    );
    await _box.flush();
  }

  /// Every stored summary, newest day first (ready for future daily reports).
  List<DailyGpsSummary> all() {
    final List<DailyGpsSummary> summaries = <DailyGpsSummary>[];
    for (final Object? key in _box.keys) {
      if (key is! String || !key.startsWith(_prefix)) continue;
      final Object? raw = _box.get(key);
      if (raw is Map) {
        summaries.add(DailyGpsSummary.fromMap(Map<String, dynamic>.from(raw)));
      }
    }
    summaries.sort((DailyGpsSummary a, DailyGpsSummary b) =>
        b.date.compareTo(a.date));
    return summaries;
  }
}