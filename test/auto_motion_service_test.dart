import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/src/core/config/app_config.dart';
import 'package:routenote/src/data/local/auto_motion_data_source.dart';
import 'package:routenote/src/data/models/daily_gps_summary.dart';
import 'package:routenote/src/services/auto_motion_service.dart';

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
    tempDir = await Directory.systemTemp.createTemp('routenote_automotion_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    for (final Box<dynamic> box in openBoxes) {
      await box.close();
    }
    openBoxes.clear();
    await tempDir.delete(recursive: true);
  });

  /// Opens the production box name (`auto_motion_box`) so the binary/storage
  /// wiring is pinned exactly as the app opens it in main().
  Future<AutoMotionDataSource> openStore(String suffix) async {
    final Box<dynamic> box =
        await Hive.openBox<dynamic>('${AppConfig.autoMotionBoxName}$suffix');
    openBoxes.add(box);
    return AutoMotionDataSource(box);
  }

  group('AutoMotionDataSource storage keys', () {
    test('stores each day under its YYYY-MM-DD key without a prefix', () async {
      final AutoMotionDataSource store = await openStore('_keys');
      final DateTime day = DateTime(2026, 10, 11);

      await store.save(
        DailyGpsSummary(date: day, totalKm: 3.5, maxSpeedKmh: 42),
      );

      final Box<dynamic> box =
          openBoxes.last; // the box just wrapped by openStore
      expect(box.keys, contains('2026-10-11'));
      final Map<String, dynamic> raw =
          Map<String, dynamic>.from(box.get('2026-10-11') as Map);
      expect(raw['date'], '2026-10-11');
      expect(raw['total_km'], 3.5);
      expect(raw['max_speed'], 42);

      expect(store.summaryFor(day), isNotNull);
      expect(store.summaryFor(DateTime(2026, 10, 10)), isNull);
    });
  });

  group('AutoMotionService accumulation', () {
    test('accumulates distance and tracks current/max speed in km/h', () async {
      final AutoMotionService service =
          AutoMotionService(dailyStore: await openStore('_accum'));

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

    test('drops noisy / non-accuracy fixes without poisoning the state',
        () async {
      final AutoMotionService service =
          AutoMotionService(dailyStore: await openStore('_noise'));

      service.recordPosition(_fix(0, 0)); // valid seed
      service.recordPosition(_fix(0, 0, accuracy: 80)); // > 35 m
      service.recordPosition(_fix(0.01, 0, hasAccuracy: false, speed: 40));
      expect(service.totalDistanceKm, 0);
      expect(service.maxSpeedKmh, 0);

      service.recordPosition(_fix(0.01, 0, speed: 7));
      expect(service.totalDistanceKm, closeTo(1.11, 0.01));
      expect(service.maxSpeedKmh, closeTo(25.2, 0.001));
    });
  });

  group('AutoMotionService persistence & restart', () {
    test('stop() persists the day; a fresh app restart re-seeds from storage',
        () async {
      final AutoMotionDataSource store = await openStore('_persist');
      final AutoMotionService service = AutoMotionService(dailyStore: store);

      service.recordPosition(_fix(0, 0));
      service.recordPosition(_fix(0.009, 0, speed: 12));
      service.recordPosition(_fix(0.018, 0, speed: 33));
      await service.stop();

      // Stored under the date key inside the auto_motion_box.
      final DailyGpsSummary? saved =
          store.summaryFor(DailyGpsSummary.dayOf(DateTime.now()));
      expect(saved, isNotNull);
      expect(saved!.totalKm, closeTo(2.0, 0.05));
      expect(saved.maxSpeedKmh, closeTo(118.8, 0.001));

      // Simulate an app restart: close the box and reopen it from disk, then a
      // brand new service instance picks today's totals back up.
      final Box<dynamic> box = openBoxes.last;
      await box.close();
      final Box<dynamic> reopened =
          await Hive.openBox<dynamic>('${AppConfig.autoMotionBoxName}_persist');
      openBoxes.add(reopened);

      final AutoMotionService restarted =
          AutoMotionService(dailyStore: AutoMotionDataSource(reopened));
      await restarted.resyncFromStore();
      expect(restarted.totalDistanceKm, closeTo(2.0, 0.05));
      expect(restarted.maxSpeedKmh, closeTo(118.8, 0.001));
    });

    test('stop() without any tracking never writes to storage', () async {
      final AutoMotionDataSource store = await openStore('_novalue');
      final AutoMotionService service = AutoMotionService(dailyStore: store);

      await service.stop();
      expect(store.all(), isEmpty);
    });
  });

  group('AutoMotionService streaming', () {
    test('start() with an injected stream bypasses the platform channels',
        () async {
      final AutoMotionDataSource store = await openStore('_stream');
      final AutoMotionService service = AutoMotionService(dailyStore: store);
      final StreamController<Position> controller = StreamController<Position>();

      final bool started = await service.start(positions: controller.stream);
      expect(started, isTrue);
      expect(service.isTracking, isTrue);

      controller.add(_fix(0, 0));
      controller.add(_fix(0.009, 0, speed: 10));
      await Future<void>.delayed(Duration.zero); // let stream events land

      expect(service.totalDistanceKm, closeTo(1.0, 0.05));
      await service.stop();
      expect(service.isTracking, isFalse);
      expect(
        store.summaryFor(DailyGpsSummary.dayOf(DateTime.now()))!.totalKm,
        closeTo(1.0, 0.05),
      );
      await controller.close();
    });
  });

  group('AutoMotionService live updates', () {
    test('emits on every accepted fix so the UI never waits for a toggle',
        () async {
      final AutoMotionService service =
          AutoMotionService(dailyStore: await openStore('_changes'));
      final List<int> notifications = <int>[];
      final StreamSubscription<void> subscription =
          service.changes.listen((_) => notifications.add(1));

      service.recordPosition(_fix(0, 0));
      service.recordPosition(_fix(0.009, 0, speed: 10));
      await Future<void>.delayed(Duration.zero);
      expect(notifications, hasLength(2));

      // A rejected fix is not an update.
      service.recordPosition(_fix(0.02, 0, accuracy: 80));
      await Future<void>.delayed(Duration.zero);
      expect(notifications, hasLength(2));

      await subscription.cancel();
    });

    test('persists each accepted fix instead of only on stop', () async {
      final AutoMotionDataSource store = await openStore('_eager');
      final AutoMotionService service = AutoMotionService(dailyStore: store);

      service.recordPosition(_fix(0, 0));
      service.recordPosition(_fix(0.009, 0, speed: 10));
      // Let the fire-and-forget writes land (no stop() call yet).
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final DailyGpsSummary? saved =
          store.summaryFor(DailyGpsSummary.dayOf(DateTime.now()));
      expect(saved, isNotNull);
      expect(saved!.totalKm, closeTo(1.0, 0.05));
      expect(saved.maxSpeedKmh, closeTo(36.0, 0.001));
      expect(service.isTracking, isFalse); // still never started
    });

    test('a long silence between fixes is not counted as travel', () async {
      final AutoMotionService service =
          AutoMotionService(dailyStore: await openStore('_gap'));
      final DateTime start = DateTime.now();

      service.recordPosition(_fix(0, 0, at: start));
      // Three hours later the phone is 20 km away: parked, not travelled.
      service.recordPosition(
        _fix(0.18, 0, at: start.add(const Duration(hours: 3)), speed: 0),
      );

      expect(service.totalDistanceKm, 0);
    });
  });

  group('AutoMotionService midnight roll-over', () {
    test('saves the finished day and starts the next one', () async {
      final AutoMotionDataSource store = await openStore('_roll');
      final AutoMotionService service = AutoMotionService(dailyStore: store);

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