import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/src/data/local/auto_motion_data_source.dart';
import 'package:routenote/src/data/models/daily_gps_summary.dart';

void main() {
  late Directory tempDir;
  late Box<dynamic> box;
  late AutoMotionDataSource store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mapnote_auto_motion_agg');
    Hive.init(tempDir.path);
    box = await Hive.openBox<dynamic>('auto_motion_box');
    store = AutoMotionDataSource(box);
  });

  tearDown(() async {
    await box.close();
    await tempDir.delete(recursive: true);
  });

  DailyGpsSummary day(
    DateTime date, {
    double totalKm = 0,
    double maxSpeedKmh = 0,
    double walkKm = 0,
    double runKm = 0,
    double vehicleKm = 0,
    int walkDurationSeconds = 0,
    int runDurationSeconds = 0,
    int vehicleDurationSeconds = 0,
  }) {
    return DailyGpsSummary(
      date: date,
      totalKm: totalKm,
      maxSpeedKmh: maxSpeedKmh,
      walkKm: walkKm,
      runKm: runKm,
      vehicleKm: vehicleKm,
      walkDurationSeconds: walkDurationSeconds,
      runDurationSeconds: runDurationSeconds,
      vehicleDurationSeconds: vehicleDurationSeconds,
    );
  }

  test('empty store yields zero aggregates and zero days', () {
    final AutoMotionAggregates agg = store.aggregates(days: 7);
    expect(agg.totalKm, 0);
    expect(agg.maxSpeedKmh, 0);
    expect(agg.walkKm, 0);
    expect(agg.runKm, 0);
    expect(agg.vehicleKm, 0);
    expect(agg.walkDurationSeconds, 0);
    expect(agg.runDurationSeconds, 0);
    expect(agg.vehicleDurationSeconds, 0);
    expect(agg.days, 0);
  });

  test('single recorded day is reflected verbatim', () async {
    final DateTime d = DateTime(2026, 3, 10);
    await store.save(day(
      d,
      totalKm: 5.5,
      maxSpeedKmh: 42.0,
      walkKm: 1.0,
      runKm: 0.5,
      vehicleKm: 4.0,
      walkDurationSeconds: 600,
      runDurationSeconds: 180,
      vehicleDurationSeconds: 300,
    ));

    final AutoMotionAggregates agg = store.last7Days(endDate: d);
    expect(agg.totalKm, closeTo(5.5, 1e-9));
    expect(agg.maxSpeedKmh, closeTo(42.0, 1e-9));
    expect(agg.walkKm, closeTo(1.0, 1e-9));
    expect(agg.runKm, closeTo(0.5, 1e-9));
    expect(agg.vehicleKm, closeTo(4.0, 1e-9));
    expect(agg.walkDurationSeconds, 600);
    expect(agg.runDurationSeconds, 180);
    expect(agg.vehicleDurationSeconds, 300);
    expect(agg.days, 1);
  });

  test('aggregates sum across multiple days and take max speed', () async {
    final DateTime end = DateTime(2026, 3, 10);
    await store.save(day(DateTime(2026, 3, 10),
        totalKm: 3, maxSpeedKmh: 30, walkKm: 1, vehicleKm: 2,
        walkDurationSeconds: 100, vehicleDurationSeconds: 200));
    await store.save(day(DateTime(2026, 3, 9),
        totalKm: 4, maxSpeedKmh: 50, runKm: 4,
        runDurationSeconds: 400));
    await store.save(day(DateTime(2026, 3, 8),
        totalKm: 2, maxSpeedKmh: 20, vehicleKm: 2,
        vehicleDurationSeconds: 150));

    final AutoMotionAggregates agg = store.aggregates(days: 7, endDate: end);
    expect(agg.totalKm, closeTo(9, 1e-9));
    expect(agg.maxSpeedKmh, closeTo(50, 1e-9));
    expect(agg.walkKm, closeTo(1, 1e-9));
    expect(agg.runKm, closeTo(4, 1e-9));
    expect(agg.vehicleKm, closeTo(4, 1e-9));
    expect(agg.walkDurationSeconds, 100);
    expect(agg.runDurationSeconds, 400);
    expect(agg.vehicleDurationSeconds, 350);
    expect(agg.days, 3);
  });

  test('days outside the window are excluded', () async {
    final DateTime end = DateTime(2026, 3, 10);
    // Inside window (last 7 days): Mar 4..Mar 10.
    await store.save(day(DateTime(2026, 3, 10), totalKm: 1, maxSpeedKmh: 10));
    // Outside window (8 days back).
    await store.save(day(DateTime(2026, 3, 2), totalKm: 99, maxSpeedKmh: 99));

    final AutoMotionAggregates agg = store.aggregates(days: 7, endDate: end);
    expect(agg.totalKm, closeTo(1, 1e-9));
    expect(agg.maxSpeedKmh, closeTo(10, 1e-9));
    expect(agg.days, 1);
  });

  test('missing days are skipped and not counted', () async {
    final DateTime end = DateTime(2026, 3, 10);
    await store.save(day(DateTime(2026, 3, 10), totalKm: 1));
    // Mar 9 missing.
    await store.save(day(DateTime(2026, 3, 8), totalKm: 2));

    final AutoMotionAggregates agg = store.aggregates(days: 3, endDate: end);
    expect(agg.totalKm, closeTo(3, 1e-9));
    expect(agg.days, 2);
  });

  test('last7Days and last30Days convenience wrappers', () async {
    final DateTime end = DateTime(2026, 3, 10);
    for (int i = 0; i < 15; i++) {
      await store.save(day(
        end.subtract(Duration(days: i)),
        totalKm: 1,
        maxSpeedKmh: 10 + i.toDouble(),
      ));
    }
    final AutoMotionAggregates w7 = store.last7Days(endDate: end);
    final AutoMotionAggregates w30 = store.last30Days(endDate: end);
    expect(w7.days, 7);
    expect(w7.totalKm, closeTo(7, 1e-9));
    expect(w30.days, 15);
    expect(w30.totalKm, closeTo(15, 1e-9));
  });

  test('30-day window aggregates per-mode totals', () async {
    final DateTime end = DateTime(2026, 3, 10);
    await store.save(day(DateTime(2026, 3, 10),
        walkKm: 0.5, runKm: 1.2, vehicleKm: 3.3,
        walkDurationSeconds: 300, runDurationSeconds: 400, vehicleDurationSeconds: 500));
    await store.save(day(DateTime(2026, 2, 15),
        walkKm: 0.1, runKm: 0.2, vehicleKm: 0.3,
        walkDurationSeconds: 60, runDurationSeconds: 70, vehicleDurationSeconds: 80));

    final AutoMotionAggregates agg = store.last30Days(endDate: end);
    expect(agg.walkKm, closeTo(0.6, 1e-9));
    expect(agg.runKm, closeTo(1.4, 1e-9));
    expect(agg.vehicleKm, closeTo(3.6, 1e-9));
    expect(agg.walkDurationSeconds, 360);
    expect(agg.runDurationSeconds, 470);
    expect(agg.vehicleDurationSeconds, 580);
    expect(agg.totalModeKm, closeTo(5.6, 1e-9));
    expect(agg.totalModeDurationSeconds, 1410);
  });

  test('all() returns newest first', () async {
    await store.save(day(DateTime(2026, 1, 1), totalKm: 1));
    await store.save(day(DateTime(2026, 1, 3), totalKm: 3));
    await store.save(day(DateTime(2026, 1, 2), totalKm: 2));
    final List<DailyGpsSummary> list = store.all();
    expect(list.map((DailyGpsSummary s) => s.totalKm).toList(),
        <double>[3, 2, 1]);
  });

  test('summaryFor returns null for missing day', () {
    expect(store.summaryFor(DateTime(2026, 5, 5)), isNull);
  });

  test('DailyGpsSummary.fromMap tolerates legacy maps without per-mode keys', () {
    final Map<String, dynamic> legacy = <String, dynamic>{
      'date': '2026-01-01',
      'total_km': 7.0,
      'max_speed': 25.0,
    };
    final DailyGpsSummary s = DailyGpsSummary.fromMap(legacy);
    expect(s.totalKm, closeTo(7.0, 1e-9));
    expect(s.maxSpeedKmh, closeTo(25.0, 1e-9));
    expect(s.walkKm, 0);
    expect(s.runKm, 0);
    expect(s.vehicleKm, 0);
    expect(s.walkDurationSeconds, 0);
    expect(s.runDurationSeconds, 0);
    expect(s.vehicleDurationSeconds, 0);
  });

  test('toMap/fromMap round-trips per-mode fields', () async {
    final DailyGpsSummary original = day(
      DateTime(2026, 4, 4),
      totalKm: 2,
      maxSpeedKmh: 12,
      walkKm: 0.4,
      runKm: 0.6,
      vehicleKm: 1.0,
      walkDurationSeconds: 240,
      runDurationSeconds: 360,
      vehicleDurationSeconds: 600,
    );
    await store.save(original);
    final DailyGpsSummary? restored = store.summaryFor(DateTime(2026, 4, 4));
    expect(restored, isNotNull);
    expect(restored!.walkKm, closeTo(0.4, 1e-9));
    expect(restored.runKm, closeTo(0.6, 1e-9));
    expect(restored.vehicleKm, closeTo(1.0, 1e-9));
    expect(restored.walkDurationSeconds, 240);
    expect(restored.runDurationSeconds, 360);
    expect(restored.vehicleDurationSeconds, 600);
  });

  test('fromMap defaults missing date to today', () {
    final DailyGpsSummary s = DailyGpsSummary.fromMap(<String, dynamic>{});
    expect(s.date, DailyGpsSummary.dayOf(DateTime.now()));
  });
}
