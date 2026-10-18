import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/src/core/config/app_config.dart';
import 'package:routenote/src/data/local/auto_motion_data_source.dart';
import 'package:routenote/src/data/models/daily_gps_summary.dart';
import 'package:routenote/src/services/auto_motion_service.dart';
import 'package:routenote/src/services/location_service.dart';
import 'package:routenote/src/services/motion_signal.dart';

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

/// Store that records every write instead of touching Hive, so the periodic
/// flush can be observed without waiting on disk.
class _RecordingStore extends AutoMotionDataSource {
  _RecordingStore(super.box);

  final List<DailyGpsSummary> saved = <DailyGpsSummary>[];

  @override
  Future<void> save(DailyGpsSummary summary) async {
    saved.add(summary);
  }
}

/// A [LocationService] that answers every check without touching the
/// geolocator platform channels and records each stream (re-)open together
/// with the exact [LocationSettings] it was asked for, so power-mode and
/// adaptive-sampling re-opens can be counted and inspected.
class _RecordingLocationService extends LocationService {
  /// How many times the position stream has been (re-)opened.
  int openCount = 0;

  /// The settings of every open, in order ([openCount] entries).
  final List<LocationSettings> openedWith = <LocationSettings>[];

  @override
  Future<bool> isServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;

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
    // `AutoMotionService._streamSettings`), never with a bare null.
    openedWith.add(settings!);
    return const Stream<Position>.empty();
  }
}

/// Adds [fix] to [controller] and waits until the tracker has recorded it, so
/// a following synchronous call (e.g. [AutoMotionService.noteOutage]) happens
/// strictly after the fix landed — mirroring real fix arrival order.
Future<void> _deliver(
  StreamController<Position> controller,
  Position fix,
) async {
  controller.add(fix);
  await Future<void>.delayed(Duration.zero);
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
  Future<Box<dynamic>> openBox(String suffix) async {
    final Box<dynamic> box =
        await Hive.openBox<dynamic>('${AppConfig.autoMotionBoxName}$suffix');
    openBoxes.add(box);
    return box;
  }

  Future<AutoMotionDataSource> openStore(String suffix) async =>
      AutoMotionDataSource(await openBox(suffix));

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

  group('AutoMotionService dead reckoning', () {
    test('bridges a long outage when the motion signal saw the car moving',
        () async {
      final DateTime start = DateTime.now().subtract(const Duration(hours: 1));
      final AutoMotionService service = AutoMotionService(
        dailyStore: await openStore('_bridge'),
        // Motion evidence 40 minutes in: the tunnel did not stop the car.
        motion: _FakeMotion(start.add(const Duration(minutes: 40))),
      );

      service.recordPosition(_fix(0, 0, at: start));
      // 45 minutes (and ~30 km) later the GPS comes back: the gap is bridged
      // because the device demonstrably kept moving.
      service.recordPosition(
        _fix(0.27, 0, at: start.add(const Duration(minutes: 45))),
      );

      expect(service.totalDistanceKm, closeTo(30.0, 0.2));
    });

    test('refuses to bridge the same outage without motion evidence', () async {
      final DateTime start = DateTime.now().subtract(const Duration(hours: 1));
      final AutoMotionService service =
          AutoMotionService(dailyStore: await openStore('_parked'));

      service.recordPosition(_fix(0, 0, at: start));
      service.recordPosition(
        _fix(0.27, 0, at: start.add(const Duration(minutes: 45))),
      );

      expect(service.totalDistanceKm, 0);
    });

    test('never bridges an outage beyond the bridge window', () async {
      final DateTime start = DateTime.now().subtract(const Duration(hours: 5));
      final AutoMotionService service = AutoMotionService(
        dailyStore: await openStore('_tooLong'),
        motion: _FakeMotion(start.add(const Duration(minutes: 10))),
      );

      service.recordPosition(_fix(0, 0, at: start));
      service.recordPosition(
        _fix(0.27, 0, at: start.add(const Duration(hours: 3))),
      );

      expect(service.totalDistanceKm, 0);
    });

    test('a step implying an impossible speed is a GPS jump, not travel',
        () async {
      final AutoMotionService service =
          AutoMotionService(dailyStore: await openStore('_jump'));
      final DateTime start = DateTime.now();

      service.recordPosition(_fix(0, 0, at: start));
      // 111 km in five seconds (~80 000 km/h): a glitch, never a drive.
      service.recordPosition(
        _fix(1.0, 0, at: start.add(const Duration(seconds: 5))),
      );

      expect(service.totalDistanceKm, 0);
    });

    test('ignores a Doppler speed spike instead of poisoning the maximum',
        () async {
      final AutoMotionService service =
          AutoMotionService(dailyStore: await openStore('_spike'));

      service.recordPosition(_fix(0, 0, speed: 0));
      // 200 m/s = 720 km/h: a GPS glitch, not a supercar.
      service.recordPosition(_fix(0.001, 0, speed: 200));

      expect(service.currentSpeedKmh, 0);
      expect(service.maxSpeedKmh, 0);
    });

    test('resumes an in-progress trip after an app restart', () async {
      final AutoMotionDataSource store = await openStore('_resume');
      final DateTime start = DateTime.now();

      final AutoMotionService service = AutoMotionService(dailyStore: store);
      service.recordPosition(_fix(0, 0, at: start));
      service.recordPosition(
        _fix(0.009, 0, at: start.add(const Duration(minutes: 2)), speed: 8),
      );
      await service.stop();
      expect(service.totalDistanceKm, closeTo(1.0, 0.05));

      // A brand new instance (as after a crash) picks the persisted last fix
      // back up and keeps accumulating the same trip.
      final AutoMotionService restarted = AutoMotionService(dailyStore: store);
      await restarted.resyncFromStore();
      expect(restarted.totalDistanceKm, closeTo(1.0, 0.05));

      restarted.recordPosition(
        _fix(0.018, 0, at: start.add(const Duration(minutes: 7)), speed: 12),
      );
      expect(restarted.totalDistanceKm, closeTo(2.0, 0.05));
    });
  });

  group('AutoMotionService explicit outage recovery', () {
    test('an observed outage recovers the plausible A→B crossing', () async {
      final AutoMotionService service =
          AutoMotionService(dailyStore: await openStore('_outage'));
      final StreamController<Position> controller =
          StreamController<Position>();
      expect(await service.start(positions: controller.stream), isTrue);

      final DateTime start = DateTime.now().subtract(const Duration(hours: 1));
      await _deliver(controller, _fix(0, 0, at: start));
      expect(service.totalDistanceKm, 0); // first fix seeds only

      // The outage is *observed* (provider switched off / stream failed)…
      service.noteOutage();
      // …and GPS comes back 10 minutes later, 20 km away: 120 km/h implied,
      // plausible travel, so the whole crossing rejoins today's total.
      await _deliver(
        controller,
        _fix(0.18, 0, at: start.add(const Duration(minutes: 10))),
      );

      // Exactly the Haversine crossing — recovered, but not a metre more.
      expect(service.totalDistanceKm, closeTo(20.0, 0.05));

      await service.stop();
      await controller.close();
    });

    test('an observed outage recovers a span silent-gap rules refuse',
        () async {
      final AutoMotionService service =
          AutoMotionService(dailyStore: await openStore('_outage_span'));
      final StreamController<Position> controller =
          StreamController<Position>();
      expect(await service.start(positions: controller.stream), isTrue);

      final DateTime start = DateTime.now().subtract(const Duration(hours: 1));
      await _deliver(controller, _fix(0, 0, at: start));

      // The very numbers the silent-gap contract refuses (45 min / 30 km,
      // no motion evidence ⇒ 0): once the outage was observed, the crossing
      // is judged by the gap-recovery rule alone — 40 km/h implied — and is
      // recovered without any motion signal.
      service.noteOutage();
      await _deliver(
        controller,
        _fix(0.27, 0, at: start.add(const Duration(minutes: 45))),
      );

      expect(service.totalDistanceKm, closeTo(30.0, 0.1));

      await service.stop();
      await controller.close();
    });

    test('an implausible outage crossing recovers nothing', () async {
      final AutoMotionService service =
          AutoMotionService(dailyStore: await openStore('_outage_bad'));
      final StreamController<Position> controller =
          StreamController<Position>();
      expect(await service.start(positions: controller.stream), isTrue);

      final DateTime start = DateTime.now().subtract(const Duration(hours: 1));
      await _deliver(controller, _fix(0, 0, at: start));

      // 10 km in one minute implies 600 km/h: a teleport, never travel. The
      // outage pass recovers 0, and the inertial fallback (noop by default)
      // has no estimate to vouch for the window either.
      service.noteOutage();
      await _deliver(
        controller,
        _fix(0.09, 0, at: start.add(const Duration(minutes: 1))),
      );

      expect(service.totalDistanceKm, 0);

      await service.stop();
      await controller.close();
    });
  });

  group('AutoMotionService crash resilience', () {
    test('flushes today\'s metrics periodically while tracking', () async {
      final _RecordingStore store = _RecordingStore(await openBox('_flush'));
      final AutoMotionService service = AutoMotionService(
        dailyStore: store,
        flushEvery: const Duration(milliseconds: 20),
      );
      final StreamController<Position> controller =
          StreamController<Position>();

      expect(await service.start(positions: controller.stream), isTrue);
      service.recordPosition(_fix(0, 0));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final int afterFirstFix = store.saved.length;

      // No further fixes arrive, but the periodic flush keeps writing.
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(store.saved.length, greaterThan(afterFirstFix));

      await service.stop();
      await controller.close();
    });

    test('the production flush cadence is ten seconds', () {
      expect(AutoMotionService.persistInterval, const Duration(seconds: 10));
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

  group('AutoMotionService power mode & adaptive sampling', () {
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
      final AutoMotionService service =
          AutoMotionService(dailyStore: await openStore('_powermode'));

      expect(await service.start(locations: scripted), isTrue);
      expect(scripted.openCount, 1, reason: 'start() opens the stream once');
      final AndroidSettings visible =
          scripted.openedWith.single as AndroidSettings;
      expect(visible.accuracy, LocationAccuracy.high);
      expect(visible.intervalDuration, AutoMotionService.defaultInterval);

      await service.setPowerMode(backgrounded: true);
      expect(scripted.openCount, 2, reason: 'the mode change re-opens once');
      final AndroidSettings background =
          scripted.openedWith.last as AndroidSettings;
      expect(background.accuracy, LocationAccuracy.medium);
      expect(background.intervalDuration, AutoMotionService.defaultInterval);

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
      final AutoMotionService service =
          AutoMotionService(dailyStore: await openStore('_sampling'));

      expect(await service.start(locations: scripted), isTrue);
      expect(
        (scripted.openedWith.single as AndroidSettings).intervalDuration,
        AutoMotionService.defaultInterval,
        reason: 'no profile yet: the fixed 5 s baseline applies',
      );

      await service.applySampling(interval: const Duration(seconds: 15));
      expect(scripted.openCount, 2, reason: 'a new profile re-opens once');
      AndroidSettings sampled = scripted.openedWith.last as AndroidSettings;
      expect(sampled.intervalDuration, const Duration(seconds: 15));
      expect(sampled.accuracy, LocationAccuracy.high); // still foreground

      await service.applySampling(interval: const Duration(seconds: 15));
      expect(scripted.openCount, 2, reason: 'the same profile is idempotent');

      await service.applySampling(
        interval: const Duration(seconds: 15),
        accuracy: LocationAccuracy.lowest,
      );
      expect(scripted.openCount, 3, reason: 'a tier change re-opens');
      sampled = scripted.openedWith.last as AndroidSettings;
      expect(sampled.intervalDuration, const Duration(seconds: 15));
      expect(sampled.accuracy, LocationAccuracy.lowest);
      expect(
        sampled.distanceFilter,
        LocationService.trackingDistanceFilterMeters,
      );

      await service.stop();
    });

    test('sampling tiers are capped by the background power budget', () async {
      overrideToAndroid();
      final _RecordingLocationService scripted = _RecordingLocationService();
      final AutoMotionService service =
          AutoMotionService(dailyStore: await openStore('_sampling_bg'));

      expect(await service.start(locations: scripted), isTrue);
      await service.setPowerMode(backgrounded: true);
      expect(scripted.openCount, 2);
      expect(scripted.openedWith.last.accuracy, LocationAccuracy.medium);

      // The stationary tier may go *lower* than the visible baseline even
      // while backgrounded — a profile may lower accuracy freely.
      await service.applySampling(
        interval: const Duration(seconds: 15),
        accuracy: LocationAccuracy.lowest,
      );
      expect(scripted.openCount, 3);
      expect(scripted.openedWith.last.accuracy, LocationAccuracy.lowest);

      // …but a high-accuracy profile may never outspend the power mode: it
      // is capped back down to the background budget.
      await service.applySampling(
        interval: const Duration(seconds: 15),
        accuracy: LocationAccuracy.high,
      );
      expect(scripted.openCount, 4);
      expect(scripted.openedWith.last.accuracy, LocationAccuracy.medium);

      await service.stop();
    });

    test('with an injected stream the power/sampling knobs change nothing',
        () async {
      final AutoMotionService service =
          AutoMotionService(dailyStore: await openStore('_injected_knobs'));
      final StreamController<Position> controller =
          StreamController<Position>();
      expect(await service.start(positions: controller.stream), isTrue);

      // No LocationService backs an injected stream (`_activeLocations` is
      // null), so both knobs are deliberate no-ops: nothing to re-open,
      // nothing to reconfigure.
      await service.setPowerMode(backgrounded: true);
      await service.applySampling(interval: const Duration(seconds: 15));

      // The original subscription keeps feeding fixes undisturbed.
      controller.add(_fix(0, 0));
      controller.add(_fix(0.009, 0, speed: 10));
      await Future<void>.delayed(Duration.zero);

      expect(service.isTracking, isTrue);
      expect(service.totalDistanceKm, closeTo(1.0, 0.05));

      await service.stop();
      await controller.close();
    });
  });
}