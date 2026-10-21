import 'package:hive_ce/hive.dart';

import '../models/daily_gps_summary.dart';
import 'daily_track_store.dart';

/// Aggregated totals across a window of days.
class AutoMotionAggregates {
  const AutoMotionAggregates({
    required this.totalKm,
    required this.maxSpeedKmh,
    required this.walkKm,
    required this.runKm,
    required this.vehicleKm,
    required this.walkDurationSeconds,
    required this.runDurationSeconds,
    required this.vehicleDurationSeconds,
    required this.days,
  });

  final double totalKm;
  final double maxSpeedKmh;
  final double walkKm;
  final double runKm;
  final double vehicleKm;
  final int walkDurationSeconds;
  final int runDurationSeconds;
  final int vehicleDurationSeconds;
  final int days;

  double get totalModeKm => walkKm + runKm + vehicleKm;

  int get totalModeDurationSeconds =>
      walkDurationSeconds + runDurationSeconds + vehicleDurationSeconds;
}

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

  /// Aggregates the last [days] days ending at [endDate] (inclusive).
  /// Computed strictly in RAM from the Hive store (auto_motion_box).
  AutoMotionAggregates aggregates({int days = 7, DateTime? endDate}) {
    if (days <= 0) {
      return const AutoMotionAggregates(
        totalKm: 0,
        maxSpeedKmh: 0,
        walkKm: 0,
        runKm: 0,
        vehicleKm: 0,
        walkDurationSeconds: 0,
        runDurationSeconds: 0,
        vehicleDurationSeconds: 0,
        days: 0,
      );
    }
    final DateTime end = DailyGpsSummary.dayOf(endDate ?? DateTime.now());
    double totalKm = 0;
    double maxSpeedKmh = 0;
    double walkKm = 0;
    double runKm = 0;
    double vehicleKm = 0;
    int walkDurationSeconds = 0;
    int runDurationSeconds = 0;
    int vehicleDurationSeconds = 0;
    int counted = 0;

    for (int i = 0; i < days; i++) {
      final DateTime day = end.subtract(Duration(days: i));
      final DailyGpsSummary? summary = summaryFor(day);
      if (summary == null) continue;
      counted++;
      totalKm += summary.totalKm;
      if (summary.maxSpeedKmh > maxSpeedKmh) {
        maxSpeedKmh = summary.maxSpeedKmh;
      }
      walkKm += summary.walkKm;
      runKm += summary.runKm;
      vehicleKm += summary.vehicleKm;
      walkDurationSeconds += summary.walkDurationSeconds;
      runDurationSeconds += summary.runDurationSeconds;
      vehicleDurationSeconds += summary.vehicleDurationSeconds;
    }

    return AutoMotionAggregates(
      totalKm: totalKm,
      maxSpeedKmh: maxSpeedKmh,
      walkKm: walkKm,
      runKm: runKm,
      vehicleKm: vehicleKm,
      walkDurationSeconds: walkDurationSeconds,
      runDurationSeconds: runDurationSeconds,
      vehicleDurationSeconds: vehicleDurationSeconds,
      days: counted,
    );
  }

  /// 7-day aggregates.
  AutoMotionAggregates last7Days({DateTime? endDate}) =>
      aggregates(days: 7, endDate: endDate);

  /// 30-day aggregates.
  AutoMotionAggregates last30Days({DateTime? endDate}) =>
      aggregates(days: 30, endDate: endDate);
}
