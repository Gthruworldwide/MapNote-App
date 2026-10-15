import '../models/daily_gps_summary.dart';

/// Day-keyed persistence for the daily trackers' summaries.
///
/// Implemented by both Hive data sources so [DailyTrackEngine] can read and
/// write the daily metrics without knowing which box (and therefore which
/// settings switch) the owning tracker belongs to.
abstract interface class DailyTrackStore {
  /// The stored summary for [day], or null when nothing was recorded.
  DailyGpsSummary? summaryFor(DateTime day);

  /// Persists [summary] under its own day.
  Future<void> save(DailyGpsSummary summary);
}
