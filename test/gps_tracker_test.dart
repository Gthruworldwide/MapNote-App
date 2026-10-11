import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/src/data/local/gps_daily_data_source.dart';
import 'package:routenote/src/data/models/daily_gps_summary.dart';
import 'package:routenote/src/services/gps_tracker_service.dart';

/// Builds a [Position] with the required fields for geolocator 14.
Position _fix(
  double lat,
  double lon, {
  DateTime? at,
  double speed = 0,
  bool hasSpeed = true,
  double accuracy = 5,
  bool hasAccuracy = true,
}) {
  return Position(
    latitude: lat,
    longitude: lon,
    timestamp: at ?? DateTime.now(),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
    hasAccuracy: hasAccuracy,
    hasSpeed: hasSpeed,
  );
}

void main() {
  late Directory tempDir;
  final List<Box<dynamic>> openBoxes = <Box<dynamic>>[];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('routenote_gps_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    for (final Box<dynamic> box in openBoxes) {
      await box.close();
    }
    openBoxes.clear();
    await tempDir.delete(recursive: true);
  });

  Future<GpsDailyDataSource> openStore(String name) async {
    final Box<dynamic> box = await Hive.openBox<dynamic>('gps_$name');
    openBoxes.add(box);
    return GpsDailyDataSource(box);
  }

  group('DailyGpsSummary', () {
    test('round-trips through toMap/fromMap', () {
      final DailyGpsSummary summary = DailyGpsSummary(
        date: DateTime(2026, 10, 11),
        totalKm: 12.34,
        maxSpeedKmh: 88.8,
      );
      final DailyGpsSummary restored =
          DailyGpsSummary.fromMap(summary.toMap());
      expect(restored, summary);
      expect(DailyGpsSummary.dayKey(restored.date), '2026-10-11');
    });

    test('fromMap tolerates missing fields', () {
      final DailyGpsSummary summary =
          DailyGpsSummary.fromMap(<String, dynamic>{'date': '2026-10-11'});
      expect(summary.totalKm, 0);
      expect(summary.maxSpeedKmh, 0);
      expect(DailyGpsSummary.dayKey(summary.date), '2026-10-11');
    });
  });

  group('GpsTrackerService.distanceKmBetween', () {
    test('returns the expected Haversine distances', () {
      // 1° of latitude is ~111.19 km.
      expect(
        GpsTrackerService.distanceKmBetween(0, 0, 0, 1),
        closeTo(111.19, 0.05),
      );
      // 0.01° of latitude is ~1.11 km.
      expect(
        GpsTrackerService.distanceKmBetween(0, 0, 0.01, 0),
        closeTo(1.11, 0.01),
      );
      // Zero distance for identical points.
      expect(GpsTrackerService.distanceKmBetween(4, 5, 4, 5), 0);
    });
  });

  group('GpsTrackerService accumulation', () {
    test('accumulates distance and tracks current/max speed in km/h', () async {
      final GpsTrackerService service =
          GpsTrackerService(dailyStore: await openStore('accumulate'));

      service.recordPosition(_fix(0, 0)); // first fix: seed only
      expect(service.totalDistanceKm, 0);

      // ~1 km north at 10 m/s ⇒ 36 km/h.
      service.recordPosition(_fix(0.009, 0, speed: 10));
      expect(service.totalDistanceKm, closeTo(1.0, 0.05));
      expect(service.currentSpeedKmh, closeTo(36.0, 0.001));
      expect(service.maxSpeedKmh, closeTo(36.0, 0.001));

      // Another ~1 km north at 25 m/s ⇒ 90 km/h.
      service.recordPosition(_fix(0.018, 0, speed: 25));
      expect(service.totalDistanceKm, closeTo(2.0, 0.05));
      expect(service.currentSpeedKmh, closeTo(90.0, 0.001));
      expect(service.maxSpeedKmh, closeTo(90.0, 0.001));
    });

    test('drops fixes that are too noisy or lack a real accuracy', () async {
      final GpsTrackerService service =
          GpsTrackerService(dailyStore: await openStore('noise'));

      service.recordPosition(_fix(0, 0)); // valid seed
      service.recordPosition(_fix(0, 0, accuracy: 80)); // > 35 m
      service.recordPosition(
        _fix(0.01, 0, hasAccuracy: false, speed: 40),
      );
      // Both noisy fixes are dropped: only the seed's speed counted.
      expect(service.totalDistanceKm, 0);
      expect(service.maxSpeedKmh, 0);
      expect(service.currentSpeedKmh, 0);

      // A clean fix right after still works (no state was poisoned).
      service.recordPosition(_fix(0.01, 0, speed: 7));
      expect(service.totalDistanceKm, closeTo(1.11, 0.01));
      expect(service.maxSpeedKmh, closeTo(25.2, 0.001));
    });

    test('ignores sub-min-step jitter for distance but keeps the speed',
        () async {
      final GpsTrackerService service =
          GpsTrackerService(dailyStore: await openStore('jitter'));

      service.recordPosition(_fix(0, 0)); // ~0.55 km north
      service.recordPosition(_fix(0.005, 0, speed: 5));
      final double before = service.totalDistanceKm;
      expect(before, greaterThan(0));

      // ~0.1 m move right after: jitter, no distance.
      service.recordPosition(_fix(0.005001, 0, speed: 50));
      expect(service.totalDistanceKm, before);
      // But the speed still registers.
      expect(service.maxSpeedKmh, closeTo(180.0, 0.001));
    });
  });

  group('GpsTrackerService persistence', () {
    test('stop() persists today and a fresh instance re-seeds its totals',
        () async {
      final GpsDailyDataSource store = await openStore('persist');
      final GpsTrackerService service = GpsTrackerService(dailyStore: store);

      service.recordPosition(_fix(0, 0));
      service.recordPosition(_fix(0.009, 0, speed: 12));
      service.recordPosition(_fix(0.018, 0, speed: 33));
      await service.stop();

      final DailyGpsSummary? saved =
          store.summaryFor(DailyGpsSummary.dayOf(DateTime.now()));
      expect(saved, isNotNull);
      expect(saved!.totalKm, closeTo(2.0, 0.05));
      expect(saved.maxSpeedKmh, closeTo(118.8, 0.001));

      // A brand new instance (as after an app restart) picks up the day again.
      final GpsTrackerService restarted = GpsTrackerService(dailyStore: store);
      await restarted.resyncFromStore();
      expect(restarted.totalDistanceKm, closeTo(2.0, 0.05));
      expect(restarted.maxSpeedKmh, closeTo(118.8, 0.001));
    });

    test('stop() without any tracking never touches the store', () async {
      final GpsDailyDataSource store = await openStore('novalue');
      final GpsTrackerService service = GpsTrackerService(dailyStore: store);

      await service.stop();
      expect(store.all(), isEmpty);
    });
  });

  group('GpsTrackerService streaming', () {
    test('start() with an injected stream bypasses the platform channels',
        () async {
      final GpsDailyDataSource store = await openStore('stream');
      final GpsTrackerService service = GpsTrackerService(dailyStore: store);
      final StreamController<Position> controller = StreamController<Position>();

      final bool started = await service.start(positions: controller.stream);
      expect(started, isTrue);
      expect(service.isTracking, isTrue);

      controller.add(_fix(0, 0));
      controller.add(_fix(0.009, 0, speed: 10));
      await Future<void>.delayed(Duration.zero); // let the stream events land

      expect(service.totalDistanceKm, closeTo(1.0, 0.05));
      expect(service.isTracking, isTrue);

      await service.stop();
      expect(service.isTracking, isFalse);
      expect(
        store.summaryFor(DailyGpsSummary.dayOf(DateTime.now()))!.totalKm,
        closeTo(1.0, 0.05),
      );
      await controller.close();
    });

    test('a second start() while tracking is a no-op', () async {
      final GpsTrackerService service =
          GpsTrackerService(dailyStore: await openStore('noop'));
      final StreamController<Position> controller = StreamController<Position>();

      expect(await service.start(positions: controller.stream), isTrue);
      expect(
        await service.start(positions: controller.stream),
        isTrue,
        reason: 'already tracking: returns true without re-subscribing',
      );
      await service.stop();
      await controller.close();
    });
  });

  group('GpsTrackerService midnight roll-over', () {
    test('saves the finished day and starts the next one', () async {
      final GpsDailyDataSource store = await openStore('rollover');
      final GpsTrackerService service = GpsTrackerService(dailyStore: store);

      final DateTime today = DailyGpsSummary.dayOf(DateTime.now());
      final DateTime tomorrow = today.add(const Duration(days: 1));

      service.recordPosition(
        _fix(0, 0, at: today.add(const Duration(hours: 23, minutes: 50))),
      );
      service.recordPosition(
        _fix(0.009, 0, at: today.add(const Duration(hours: 23, minutes: 55))),
      );
      // The next fix is after midnight: today is finalised, tomorrow starts.
      service.recordPosition(
        _fix(0.018, 0, at: tomorrow.add(const Duration(minutes: 1))),
      );
      await service.stop();

      // The fired-and-forgotten save for yesterday completes on the event loop.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(store.summaryFor(today)!.totalKm, closeTo(1.0, 0.05));
      expect(store.summaryFor(tomorrow)!.totalKm, closeTo(1.0, 0.05));
      expect(store.all().length, 2);
    });
  });
}