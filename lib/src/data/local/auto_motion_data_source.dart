import 'package:hive_ce/hive.dart';

import '../models/daily_gps_summary.dart';
import 'daily_track_store.dart';

/// Persists AutoMotion's daily metrics.
///
/// Each calendar day is stored under its `YYYY-MM-DD` key in the dedicated
/// `auto_motion_box` Hive box (see [AppConfig.autoMotionBoxName]), so reading a
/// specific day is a simple lookup. Writes are flushed so a tracked day is
/// never lost on a sudden kill.
class AutoMotionDataSource implements DailyTrackStore {
  AutoMotionDataSource(this._box);

  final Box<dynamic> _box;

  /// The stored metrics for [day], or null when nothing was recorded that day.
  @override
  DailyGpsSummary? summaryFor(DateTime day) {
    final Object? raw = _box.get(DailyGpsSummary.dayKey(day));
    if (raw is Map) {
      return DailyGpsSummary.fromMap(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  @override
  Future<void> save(DailyGpsSummary summary) async {
    await _box.put(DailyGpsSummary.dayKey(summary.date), summary.toMap());
    await _box.flush();
  }

  /// Every stored day, newest first (ready for future AutoMotion reports).
  List<DailyGpsSummary> all() {
    final List<DailyGpsSummary> summaries = <DailyGpsSummary>[];
    for (final Object? key in _box.keys) {
      if (key is! String || key.length != 10) continue;
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