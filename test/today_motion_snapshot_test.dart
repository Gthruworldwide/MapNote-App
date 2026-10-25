import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/src/data/local/auto_motion_data_source.dart';
import 'package:routenote/src/data/models/daily_gps_summary.dart';
import 'package:routenote/src/data/models/track_point.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/local_insight_engine.dart';

/// The bridge the Smart Insights card reads.
///
/// The tracker persists four counters (walk / run / vehicle distance and the
/// day's step total) and the per-fix track points they were derived from. The
/// insight engine wants one immutable [MotionSnapshot]. `todayMotionSnapshotProvider`
/// is that glue, and the interesting properties are: it reads *today's* day, it
/// prefers the classified fixes over the persisted totals, it falls back to the
/// record when the fixes are gone, and it re-reads when a new fix lands.

/// Metres per degree of latitude at the test latitude (~30°), so a synthetic
/// walk is physically consistent.
const double _metresPerDegreeLat = 111_320;

/// A measured walk: 5 s fixes at [speedMps], [stepsPerFix] steps each.
///
/// The first fix has no step sample (the meter learns its baseline from it), so
/// `fixes - 1` increments are counted — exactly what the tracker persists.
List<TrackPoint> _walk({
  required DateTime start,
  int fixes = 25,
  int stepsPerFix = 8,
  double speedMps = 1.4,
}) => <TrackPoint>[
  for (int i = 0; i < fixes; i++)
    TrackPoint(
      latitude: 30.0444 + (speedMps * 5 * i) / _metresPerDegreeLat,
      longitude: 31.2357,
      timestamp: start.add(Duration(seconds: 5 * i)),
      speed: speedMps,
      hasSpeed: true,
      accuracy: 5,
      detectedActivity: '',
      steps: i == 0 ? null : stepsPerFix,
    ),
];

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late AutoMotionDataSource source;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('routenote_motion_');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('motion');
    source = AutoMotionDataSource(box);
  });

  tearDown(() async {
    await box.close();
    await directory.delete(recursive: true);
  });

  ProviderContainer containerWith(Stream<int> fixes) {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        autoMotionDataSourceProvider.overrideWithValue(source),
        autoMotionFixesProvider.overrideWith((Ref ref) => fixes),
      ],
    );
    addTearDown(container.dispose);
    // Keep the provider mounted so a fix actually invalidates it.
    container.listen(todayMotionSnapshotProvider, (_, _) {});
    return container;
  }

  test('a day with nothing recorded is an empty snapshot', () {
    final ProviderContainer container = containerWith(const Stream<int>.empty());

    final MotionSnapshot snapshot =
        container.read(todayMotionSnapshotProvider);

    expect(snapshot, MotionSnapshot.none);
    expect(snapshot.isEmpty, isTrue);
  });

  test('a day whose fixes are gone is read back from its persisted counters',
      () async {
    final DateTime today = DailyGpsSummary.dayOf(DateTime.now());
    await source.save(
      DailyGpsSummary(
        date: today,
        totalKm: 13.4,
        walkKm: 1.2,
        runKm: 3.5,
        vehicleKm: 8.7,
        walkDurationSeconds: 900,
        runDurationSeconds: 1500,
        vehicleDurationSeconds: 1200,
        stepCount: 5000,
        // The legacy shape: only the persisted totals, no track points (or a
        // pruned day). The record is then the only evidence left.
        trackPoints: null,
      ),
    );
    final ProviderContainer container = containerWith(const Stream<int>.empty());

    final MotionSnapshot snapshot =
        container.read(todayMotionSnapshotProvider);

    expect(snapshot.walkingKm, 1.2);
    expect(snapshot.runningKm, 3.5);
    expect(snapshot.vehicleKm, 8.7);
    expect(snapshot.steps, 5000);
    expect(snapshot.totalKm, closeTo(13.4, 1e-9));
  });

  test('today\'s classified fixes win over stale persisted counters', () async {
    final DateTime today = DailyGpsSummary.dayOf(DateTime.now());
    // A record left behind by an earlier session: its totals are stale, and the
    // track points below are the fresher, physically consistent evidence.
    await source.save(
      DailyGpsSummary(
        date: today,
        walkKm: 9,
        stepCount: 12000,
        trackPoints: _walk(
          start: today.add(const Duration(hours: 8)),
          fixes: 25,
          stepsPerFix: 8,
        ),
      ),
    );
    final ProviderContainer container = containerWith(const Stream<int>.empty());

    final MotionSnapshot snapshot =
        container.read(todayMotionSnapshotProvider);

    // 24 × 8 = 192 measured steps × 0.75 m = 144 m.
    expect(snapshot.steps, 192);
    expect(snapshot.walkingKm, closeTo(0.144, 1e-3));
    expect(snapshot.runningKm, 0);
    expect(snapshot.vehicleKm, 0);
    expect(snapshot.totalKm, closeTo(0.144, 1e-3));
  });

  test('a summary from another day is not today\'s motion', () async {
    final DateTime yesterday = DailyGpsSummary.dayOf(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    await source.save(
      DailyGpsSummary(
        date: yesterday,
        walkKm: 9,
        stepCount: 900,
        trackPoints: _walk(
          start: yesterday.add(const Duration(hours: 8)),
          fixes: 25,
        ),
      ),
    );
    final ProviderContainer container = containerWith(const Stream<int>.empty());

    expect(container.read(todayMotionSnapshotProvider), MotionSnapshot.none);
  });

  test('a new fix re-reads the day, so the insight follows the tracker',
      () async {
    final StreamController<int> fixes = StreamController<int>();
    addTearDown(fixes.close);
    final ProviderContainer container = containerWith(fixes.stream);
    final DateTime today = DailyGpsSummary.dayOf(DateTime.now());

    expect(container.read(todayMotionSnapshotProvider), MotionSnapshot.none);

    await source.save(
      DailyGpsSummary(
        date: today,
        trackPoints: _walk(
          start: today.add(const Duration(hours: 8)),
          fixes: 25,
          stepsPerFix: 8,
        ),
      ),
    );
    // Saving alone is invisible: only an accepted fix invalidates the read,
    // which is precisely what keeps the card honest about a stale day.
    expect(container.read(todayMotionSnapshotProvider), MotionSnapshot.none);

    fixes.add(0);
    await pumpEventQueue();

    final MotionSnapshot snapshot =
        container.read(todayMotionSnapshotProvider);
    expect(snapshot.walkingKm, closeTo(0.144, 1e-3));
    expect(snapshot.steps, 192);
  });
}
