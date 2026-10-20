import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/src/data/local/gps_daily_data_source.dart';
import 'package:routenote/src/data/models/daily_gps_summary.dart';
import 'package:routenote/src/services/daily_track_engine.dart';
import 'package:routenote/src/services/gps_tracker_service.dart';
import 'package:routenote/src/services/location_service.dart';
import 'package:routenote/src/services/motion_signal.dart';

/// A [MotionSignal] whose whole state is the timestamp the test hands it: the
/// trackers only ask whether motion evidence is newer than the last fix.
class _FakeMotion implements MotionSignal {
  _FakeMotion(this.lastMotionAt);

  @override
  DateTime? lastMotionAt;

  @override
  bool get inTransit => lastMotionAt != null;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void observeSpeed(double metersPerSecond) {}
}

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

/// A location source that returns a scripted verdict without ever touching the
/// geolocator platform channels, so the tracker's typed start failures can be
/// exercised deterministically.
class _ScriptedLocationService extends LocationService {
  _ScriptedLocationService({
    this.serviceEnabled = true,
    this.permission = LocationPermission.whileInUse,
    this.throwOnCheck = false,
  });

  final bool serviceEnabled;
  final LocationPermission permission;
  final bool throwOnCheck;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async {
    if (throwOnCheck) {
      throw Exception('platform location channel unavailable');
    }
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Stream<Position> trackingPositionStream({
    LocationSettings? settings,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) =>
      const Stream<Position>.empty();
}

/// A [LocationService] that answers every check without touching the
/// geolocator platform channels and records each stream (re-)open together
/// with the exact [LocationSettings] it was asked for, so power-mode and
/// adaptive-sampling re-opens can be counted and inspected.
class _RecordingLocationService extends _ScriptedLocationService {
  /// How many times the position stream has been (re-)opened.
  int openCount = 0;

  /// The settings of every open, in order ([openCount] entries).
  final List<LocationSettings> openedWith = <LocationSettings>[];

  @override
  Stream<ServiceStatus> serviceStatusStream() =>
      const Stream<ServiceStatus>.empty();

  @override
  Stream<Position> trackingPositionStream({
    LocationSettings? settings,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    openCount += 1;
    // The tracker always opens with an explicit profile (see
    // `GpsTrackerService._streamSettings`), never with a bare null.
    openedWith.add(settings!);
    return const Stream<Position>.empty();
  }
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

  group('GpsTrackerService dead reckoning', () {
    test('bridges a long outage when the motion signal saw the car moving',
        () async {
      final DateTime start = DateTime.now().subtract(const Duration(hours: 1));
      final GpsTrackerService service = GpsTrackerService(
        dailyStore: await openStore('bridge'),
        motion: _FakeMotion(start.add(const Duration(minutes: 40))),
      );

      service.recordPosition(_fix(0, 0, at: start));
      service.recordPosition(
        _fix(0.27, 0, at: start.add(const Duration(minutes: 45))),
      );

      expect(service.totalDistanceKm, closeTo(30.0, 0.2));
    });

    test('refuses to bridge the same outage without motion evidence', () async {
      final DateTime start = DateTime.now().subtract(const Duration(hours: 1));
      final GpsTrackerService service =
          GpsTrackerService(dailyStore: await openStore('parked'));

      service.recordPosition(_fix(0, 0, at: start));
      service.recordPosition(
        _fix(0.27, 0, at: start.add(const Duration(minutes: 45))),
      );

      expect(service.totalDistanceKm, 0);
    });

    test('a step implying an impossible speed is a GPS jump, not travel',
        () async {
      final GpsTrackerService service =
          GpsTrackerService(dailyStore: await openStore('jump'));
      final DateTime start = DateTime.now();

      service.recordPosition(_fix(0, 0, at: start));
      service.recordPosition(
        _fix(1.0, 0, at: start.add(const Duration(seconds: 5))),
      );

      expect(service.totalDistanceKm, 0);
    });

    test('resumes an in-progress trip after an app restart', () async {
      final GpsDailyDataSource store = await openStore('resume');
      final DateTime start = DateTime.now();

      final GpsTrackerService service = GpsTrackerService(dailyStore: store);
      service.recordPosition(_fix(0, 0, at: start));
      service.recordPosition(
        _fix(0.009, 0, at: start.add(const Duration(minutes: 2)), speed: 8),
      );
      await service.stop();

      final GpsTrackerService restarted = GpsTrackerService(dailyStore: store);
      await restarted.resyncFromStore();
      expect(restarted.totalDistanceKm, closeTo(1.0, 0.05));

      restarted.recordPosition(
        _fix(0.018, 0, at: start.add(const Duration(minutes: 7)), speed: 12),
      );
      expect(restarted.totalDistanceKm, closeTo(2.0, 0.05));
    });

    test('the production flush cadence is ten seconds', () {
      expect(GpsTrackerService.persistInterval, const Duration(seconds: 10));
    });
  });

  group('GpsTrackerService outage recovery', () {
    test('noteOutage() recovers a plausible A→B crossing', () async {
      final GpsTrackerService service =
          GpsTrackerService(dailyStore: await openStore('outage'));
      final DateTime start = DateTime.now().subtract(const Duration(hours: 1));

      service.recordPosition(_fix(0, 0, at: start));
      service.noteOutage();
      // Ten minutes later the phone is 20 km away: 120 km/h implied —
      // plausible travel, so the crossing rejoins the day's total.
      service.recordPosition(
        _fix(0.18, 0, at: start.add(const Duration(minutes: 10))),
      );

      expect(service.totalDistanceKm, closeTo(20.0, 0.05));
    });

    test('noteOutage() refuses a crossing implying an implausible speed',
        () async {
      final GpsTrackerService service =
          GpsTrackerService(dailyStore: await openStore('outage_refused'));
      final DateTime start = DateTime.now().subtract(const Duration(hours: 1));

      service.recordPosition(_fix(0, 0, at: start));
      service.noteOutage();
      // 10 km in one minute implies 600 km/h: a teleport, never travel.
      service.recordPosition(
        _fix(0.09, 0, at: start.add(const Duration(minutes: 1))),
      );

      expect(service.totalDistanceKm, 0);
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

  group('GpsTrackerService typed start failures', () {
    test('reports GPS disabled', () async {
      final GpsTrackerService service =
          GpsTrackerService(dailyStore: await openStore('fail_off'));

      final bool started = await service.start(
        locations: _ScriptedLocationService(serviceEnabled: false),
      );

      expect(started, isFalse);
      expect(service.failure, TrackStartFailure.locationServiceDisabled);
      expect(service.isTracking, isFalse);
    });

    test('reports permission denied', () async {
      final GpsTrackerService service =
          GpsTrackerService(dailyStore: await openStore('fail_denied'));

      final bool started = await service.start(
        locations:
            _ScriptedLocationService(permission: LocationPermission.denied),
      );

      expect(started, isFalse);
      expect(service.failure, TrackStartFailure.permissionDenied);
    });

    test('reports permission permanently denied', () async {
      final GpsTrackerService service =
          GpsTrackerService(dailyStore: await openStore('fail_forever'));

      final bool started = await service.start(
        locations: _ScriptedLocationService(
          permission: LocationPermission.deniedForever,
        ),
      );

      expect(started, isFalse);
      expect(service.failure, TrackStartFailure.permissionDeniedForever);
    });

    test('reports a platform channel error', () async {
      final GpsTrackerService service =
          GpsTrackerService(dailyStore: await openStore('fail_platform'));

      final bool started = await service.start(
        locations: _ScriptedLocationService(throwOnCheck: true),
      );

      expect(started, isFalse);
      expect(service.failure, TrackStartFailure.platformError);
    });

    test('clears the failure once an injected stream starts tracking',
        () async {
      final GpsTrackerService service =
          GpsTrackerService(dailyStore: await openStore('fail_clear'));
      final StreamController<Position> controller =
          StreamController<Position>();

      await service.start(
        locations: _ScriptedLocationService(serviceEnabled: false),
      );
      expect(service.failure, TrackStartFailure.locationServiceDisabled);

      final bool started = await service.start(positions: controller.stream);
      expect(started, isTrue);
      expect(service.failure, TrackStartFailure.none);

      await service.stop();
      await controller.close();
    });
  });

  group('GpsTrackerService power mode & adaptive sampling', () {
    // The request interval only exists on the platform-specific settings
    // (AndroidSettings.intervalDuration), so these tests build the profiles
    // under an Android platform; the service's own logic is platform-free.
    void overrideToAndroid() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
    }

    test('setPowerMode re-opens the live stream only on a mode change',
        () async {
      overrideToAndroid();
      final _RecordingLocationService scripted = _RecordingLocationService();
      final GpsTrackerService service =
          GpsTrackerService(dailyStore: await openStore('_powermode'));

      expect(await service.start(locations: scripted), isTrue);
      expect(scripted.openCount, 1, reason: 'start() opens the stream once');
      final AndroidSettings visible =
          scripted.openedWith.single as AndroidSettings;
      expect(visible.accuracy, LocationAccuracy.high);
      expect(visible.intervalDuration, GpsTrackerService.defaultInterval);
      expect(
        visible.distanceFilter,
        LocationService.trackingDistanceFilterMeters,
      );

      await service.setPowerMode(backgrounded: true);
      expect(scripted.openCount, 2, reason: 'the mode change re-opens once');
      final AndroidSettings background =
          scripted.openedWith.last as AndroidSettings;
      expect(background.accuracy, LocationAccuracy.medium);
      expect(background.intervalDuration, GpsTrackerService.defaultInterval);

      await service.setPowerMode(backgrounded: true);
      expect(scripted.openCount, 2, reason: 'same mode: idempotent, no re-open');

      await service.setPowerMode(backgrounded: false);
      expect(scripted.openCount, 3, reason: 'returning to foreground re-opens');
      expect(scripted.openedWith.last.accuracy, LocationAccuracy.high);

      await service.stop();
    });

    test('applySampling re-opens only on a profile change and records it',
        () async {
      overrideToAndroid();
      final _RecordingLocationService scripted = _RecordingLocationService();
      final GpsTrackerService service =
          GpsTrackerService(dailyStore: await openStore('_sampling'));

      expect(await service.start(locations: scripted), isTrue);
      expect(
        (scripted.openedWith.single as AndroidSettings).intervalDuration,
        GpsTrackerService.defaultInterval,
        reason: 'no profile yet: the fixed 5 s baseline applies',
      );

      await service.applySampling(interval: const Duration(seconds: 15));
      expect(scripted.openCount, 2, reason: 'a new profile re-opens once');
      AndroidSettings sampled = scripted.openedWith.last as AndroidSettings;
      expect(sampled.intervalDuration, const Duration(seconds: 15));
      expect(sampled.accuracy, LocationAccuracy.high); // still foreground

      await service.applySampling(interval: const Duration(seconds: 15));
      expect(scripted.openCount, 2, reason: 'the same profile is idempotent');

      // The stationary tier's 50 m movement filter reaches the request.
      await service.applySampling(
        interval: const Duration(seconds: 60),
        accuracy: LocationAccuracy.lowest,
        distanceFilter: 50,
      );
      expect(scripted.openCount, 3, reason: 'a tier change re-opens');
      sampled = scripted.openedWith.last as AndroidSettings;
      expect(sampled.intervalDuration, const Duration(seconds: 60));
      expect(sampled.accuracy, LocationAccuracy.lowest);
      expect(sampled.distanceFilter, 50);

      await service.stop();
    });

    test('the background accuracy cap lifts only for transport speeds',
        () async {
      overrideToAndroid();
      final _RecordingLocationService scripted = _RecordingLocationService();
      final GpsTrackerService service =
          GpsTrackerService(dailyStore: await openStore('_sampling_bg'));

      expect(await service.start(locations: scripted), isTrue);
      await service.setPowerMode(backgrounded: true);
      expect(scripted.openCount, 2);
      expect(scripted.openedWith.last.accuracy, LocationAccuracy.medium);

      // A walking profile (medium) is already within the background budget.
      await service.applySampling(
        interval: const Duration(seconds: 15),
        accuracy: LocationAccuracy.medium,
        distanceFilter: 10,
      );
      expect(scripted.openedWith.last.accuracy, LocationAccuracy.medium);

      // The vehicle tier is the *only* profile allowed to outspend the
      // background budget.
      await service.applySampling(
        interval: const Duration(seconds: 1),
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        transportSpeed: true,
      );
      expect(scripted.openedWith.last.accuracy, LocationAccuracy.high);

      // …and losing the transport flag caps it back down.
      await service.applySampling(
        interval: const Duration(seconds: 1),
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
      expect(scripted.openedWith.last.accuracy, LocationAccuracy.medium);

      await service.stop();
    });

    test('a paused profile closes the platform stream entirely', () async {
      overrideToAndroid();
      final _RecordingLocationService scripted = _RecordingLocationService();
      final GpsTrackerService service =
          GpsTrackerService(dailyStore: await openStore('_sampling_paused'));

      expect(await service.start(locations: scripted), isTrue);
      expect(scripted.openCount, 1);

      // The orchestrator's idleStandby profile: the platform stream must be
      // closed outright, not merely slowed, so the GNSS receiver can sleep.
      // No new platform open happens — the engine is re-pointed at an empty
      // stream instead.
      await service.applySampling(
        interval: const Duration(minutes: 10),
        accuracy: LocationAccuracy.lowest,
        distanceFilter: 200,
        paused: true,
      );
      expect(
        scripted.openCount,
        1,
        reason: 'pausing detaches without re-opening the platform stream',
      );
      expect(
        service.isTracking,
        isTrue,
        reason: 'the session survives the pause — only the stream is closed',
      );

      // Resuming re-opens the platform stream at the driving profile.
      await service.applySampling(
        interval: const Duration(seconds: 1),
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        transportSpeed: true,
        paused: false,
      );
      expect(scripted.openCount, 2, reason: 'resuming re-opens');
      final AndroidSettings resumed = scripted.openedWith.last as AndroidSettings;
      expect(resumed.accuracy, LocationAccuracy.high);
      expect(resumed.distanceFilter, 5);
      expect(resumed.intervalDuration, const Duration(seconds: 1));

      await service.stop();
    });

    test('a repeated paused profile never re-opens the stream', () async {
      overrideToAndroid();
      final _RecordingLocationService scripted = _RecordingLocationService();
      final GpsTrackerService service =
          GpsTrackerService(dailyStore: await openStore('_sampling_paused_twice'));

      expect(await service.start(locations: scripted), isTrue);
      await service.applySampling(
        interval: const Duration(minutes: 10),
        accuracy: LocationAccuracy.lowest,
        distanceFilter: 200,
        paused: true,
      );
      await service.applySampling(
        interval: const Duration(minutes: 10),
        accuracy: LocationAccuracy.lowest,
        distanceFilter: 200,
        paused: true,
      );

      expect(scripted.openCount, 1, reason: 'pausing is idempotent');

      await service.stop();
    });

    test('with an injected stream the sampling knobs change nothing',
        () async {
      overrideToAndroid();
      final _RecordingLocationService scripted = _RecordingLocationService();
      final GpsTrackerService service =
          GpsTrackerService(dailyStore: await openStore('_sampling_injected'));
      final StreamController<Position> controller =
          StreamController<Position>();

      expect(
        await service.start(positions: controller.stream),
        isTrue,
      );
      await service.applySampling(
        interval: const Duration(seconds: 1),
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        transportSpeed: true,
      );
      await service.setPowerMode(backgrounded: true);
      expect(
        scripted.openCount,
        0,
        reason: 'an injected stream is never re-opened by the knobs',
      );

      await service.stop();
      await controller.close();
    });
  });
}