import 'dart:convert';

import '../data/local/auto_motion_data_source.dart';
import '../data/models/daily_gps_summary.dart';

/// Exports AutoMotion daily metrics and period aggregates to portable,
/// coordinate-free formats (CSV / JSON) for sharing or archival.
///
/// **Privacy contract:** the output never contains latitude/longitude or any
/// place identity — only kind, distance, speed and duration aggregates
/// (`AGENT_SKILLS.md` §5). The exporter reads exclusively from
/// `auto_motion_box` via [AutoMotionDataSource]; it never touches
/// `gps_daily.hive`.
class AutoMotionExportService {
  const AutoMotionExportService(this._store);

  final AutoMotionDataSource _store;

  /// CSV export of every recorded day in [from]..[to] (inclusive), newest
  /// first, followed by a 7-day and 30-day aggregate block. Coordinates are
  /// never emitted.
  String exportCsv({DateTime? from, DateTime? to}) {
    final List<DailyGpsSummary> days = _daysInRange(from: from, to: to);
    final StringBuffer buf = StringBuffer();
    buf.writeln(
      'date,total_km,max_speed_kmh,walk_km,run_km,vehicle_km,'
      'walk_duration_s,run_duration_s,vehicle_duration_s',
    );
    for (final DailyGpsSummary d in days) {
      buf.writeln(
        '${DailyGpsSummary.dayKey(d.date)},'
        '${d.totalKm.toStringAsFixed(3)},'
        '${d.maxSpeedKmh.toStringAsFixed(2)},'
        '${d.walkKm.toStringAsFixed(3)},'
        '${d.runKm.toStringAsFixed(3)},'
        '${d.vehicleKm.toStringAsFixed(3)},'
        '${d.walkDurationSeconds},'
        '${d.runDurationSeconds},'
        '${d.vehicleDurationSeconds}',
      );
    }
    final AutoMotionAggregates agg7 = _store.last7Days(endDate: to);
    final AutoMotionAggregates agg30 = _store.last30Days(endDate: to);
    buf.writeln();
    buf.writeln('aggregate,window_days,days_recorded,total_km,max_speed_kmh,'
        'walk_km,run_km,vehicle_km,walk_duration_s,run_duration_s,'
        'vehicle_duration_s');
    buf.writeln(
      'period,7,${agg7.days},${agg7.totalKm.toStringAsFixed(3)},'
      '${agg7.maxSpeedKmh.toStringAsFixed(2)},${agg7.walkKm.toStringAsFixed(3)},'
      '${agg7.runKm.toStringAsFixed(3)},${agg7.vehicleKm.toStringAsFixed(3)},'
      '${agg7.walkDurationSeconds},${agg7.runDurationSeconds},'
      '${agg7.vehicleDurationSeconds}',
    );
    buf.writeln(
      'period,30,${agg30.days},${agg30.totalKm.toStringAsFixed(3)},'
      '${agg30.maxSpeedKmh.toStringAsFixed(2)},${agg30.walkKm.toStringAsFixed(3)},'
      '${agg30.runKm.toStringAsFixed(3)},${agg30.vehicleKm.toStringAsFixed(3)},'
      '${agg30.walkDurationSeconds},${agg30.runDurationSeconds},'
      '${agg30.vehicleDurationSeconds}',
    );
    return buf.toString();
  }

  /// JSON export of the same data, suitable for archival or re-import.
  String exportJson({DateTime? from, DateTime? to}) {
    final List<DailyGpsSummary> days = _daysInRange(from: from, to: to);
    final AutoMotionAggregates agg7 = _store.last7Days(endDate: to);
    final AutoMotionAggregates agg30 = _store.last30Days(endDate: to);
    final Map<String, Object?> payload = <String, Object?>{
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'range': <String, Object?>{
        'from': from == null ? null : DailyGpsSummary.dayKey(from),
        'to': to == null ? null : DailyGpsSummary.dayKey(to),
      },
      'days': <Map<String, Object?>>[
        for (final DailyGpsSummary d in days)
          <String, Object?>{
            'date': DailyGpsSummary.dayKey(d.date),
            'total_km': d.totalKm,
            'max_speed_kmh': d.maxSpeedKmh,
            'walk_km': d.walkKm,
            'run_km': d.runKm,
            'vehicle_km': d.vehicleKm,
            'walk_duration_s': d.walkDurationSeconds,
            'run_duration_s': d.runDurationSeconds,
            'vehicle_duration_s': d.vehicleDurationSeconds,
          },
      ],
      'aggregates': <String, Object?>{
        'last_7_days': _aggregateMap(agg7),
        'last_30_days': _aggregateMap(agg30),
      },
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Map<String, Object?> _aggregateMap(AutoMotionAggregates a) =>
      <String, Object?>{
        'days_recorded': a.days,
        'total_km': a.totalKm,
        'max_speed_kmh': a.maxSpeedKmh,
        'walk_km': a.walkKm,
        'run_km': a.runKm,
        'vehicle_km': a.vehicleKm,
        'walk_duration_s': a.walkDurationSeconds,
        'run_duration_s': a.runDurationSeconds,
        'vehicle_duration_s': a.vehicleDurationSeconds,
      };

  List<DailyGpsSummary> _daysInRange({DateTime? from, DateTime? to}) {
    final DateTime end = DailyGpsSummary.dayOf(to ?? DateTime.now());
    final DateTime start = DailyGpsSummary.dayOf(from ?? end.subtract(const Duration(days: 30)));
    final List<DailyGpsSummary> result = <DailyGpsSummary>[];
    for (DateTime day = start; !day.isAfter(end); day = day.add(const Duration(days: 1))) {
      final DailyGpsSummary? summary = _store.summaryFor(day);
      if (summary != null) result.add(summary);
    }
    result.sort((DailyGpsSummary a, DailyGpsSummary b) => b.date.compareTo(a.date));
    return result;
  }
}
