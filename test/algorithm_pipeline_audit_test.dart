import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/src/core/config/app_config.dart';
import 'package:routenote/src/data/local/auto_motion_data_source.dart';
import 'package:routenote/src/data/models/daily_gps_summary.dart';
import 'package:routenote/src/features/motion_analytics/data/motion_event_mapper.dart';
import 'package:routenote/src/features/motion_analytics/domain/entities/motion_event.dart';
import 'package:routenote/src/services/daily_track_engine.dart';
import 'package:routenote/src/services/gap_recovery_service.dart';
import 'package:routenote/src/services/motion_profiler.dart';
import 'package:routenote/src/services/polyline_smoother.dart';
import 'package:routenote/src/services/transport_classifier.dart';

/// The audit's core claim, pinned with tests: no computed metric is orphaned.
/// Every stage of the map pipeline (raw fix -> engine -> smoother -> map vertex)
/// and the motion pipeline (classified event -> mapper -> event log -> stream)
/// is asserted to actually carry its value forward.

Position _fix(
  double lat,
  double lon, {
  DateTime? at,
  double speed = 0,
  bool hasSpeed = true,
}) {
  return Position(
    latitude: lat,
    longitude: lon,
    timestamp: at ?? DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
    hasAccuracy: true,
    hasSpeed: hasSpeed,
  );
}

class _RecordingStore extends AutoMotionDataSource {
  _RecordingStore(super.box);
  final List<DailyGpsSummary> saved = <DailyGpsSummary>[];
  @override
  Future<void> save(DailyGpsSummary summary) async => saved.add(summary);
}

DateTime _todayMorning() =>
    DailyGpsSummary.dayOf(DateTime.now()).add(const Duration(hours: 8));

/// Distance between two vertices in metres, via the trackers' own haversine.
double _metersBetween(RoutePoint a, RoutePoint b) =>
    GapRecoveryService.haversineKm(
          a.latitude,
          a.longitude,
          b.latitude,
          b.longitude,
        ) *
        1000;

void main() {
  late Directory tempDir;
  final List<Box<dynamic>> openBoxes = <Box<dynamic>>[];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('routenote_pipeline_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    for (final Box<dynamic> box in openBoxes) {
      await box.close();
    }
    openBoxes.clear();
    await tempDir.delete(recursive: true);
  });

  Future<Box<dynamic>> openBox(String suffix) async {
    final Box<dynamic> box =
        await Hive.openBox<dynamic>('${AppConfig.autoMotionBoxName}$suffix');
    openBoxes.add(box);
    return box;
  }

  group('Map coordinate pipeline: fix -> engine -> smoother -> map', () {
    test('a raw fix reaches dayPath and smoothedPath without a transform',
        () async {
      final _RecordingStore store = _RecordingStore(await openBox('_map1'));
      final DailyTrackEngine engine = DailyTrackEngine(store: store);
      final DateTime base = _todayMorning();

      // One clean fix: no jitter to smooth, so the map vertex must be the
      // exact coordinate the engine was handed — 1:1, no offset, no rotation.
      engine.recordPosition(_fix(30.0444, 31.2357, at: base, speed: 12));

      expect(engine.dayPath, hasLength(1));
      expect(engine.dayPath.single.latitude, closeTo(30.0444, 1e-12));
      expect(engine.dayPath.single.longitude, closeTo(31.2357, 1e-12));
      expect(engine.dayPath.single.at, base);

      final List<RoutePoint> smoothed = engine.smoothedPath;
      expect(smoothed, hasLength(1));
      expect(smoothed.single.latitude, closeTo(30.0444, 1e-12));
      expect(smoothed.single.longitude, closeTo(31.2357, 1e-12));

      await engine.detach();
    });

    test('smoothed vertices stay within the correction cap of their fixes',
        () async {
      final _RecordingStore store = _RecordingStore(await openBox('_map2'));
      final DailyTrackEngine engine = DailyTrackEngine(store: store);
      final DateTime base = _todayMorning();

      // A straight eastbound drive with cross-track wobble: the smoothed map
      // vertices must be pulled toward the true line, but never displaced more
      // than the smoother's documented cap from the raw fix they came from.
      final List<Position> fixes = <Position>[
        for (int i = 0; i < 40; i++)
          _fix(
            30.0 + (i.isEven ? 0.00009 : -0.00009),
            31.0 + i * 0.001,
            at: base.add(Duration(seconds: 5 * i)),
            speed: 20,
          ),
      ];
      for (final Position fix in fixes) {
        engine.recordPosition(fix);
      }

      final List<RoutePoint> raw = engine.dayPath;
      final List<RoutePoint> smoothed = engine.smoothedPath;
      expect(raw, hasLength(fixes.length));
      expect(smoothed, hasLength(fixes.length));

      // The cap lives in the smoother's local tangent plane (equirectangular
      // about the first fix). Measuring with haversine instead would re-derive
      // the same displacement through a slightly different Earth model, so the
      // comparison is made in the plane the cap is actually defined in — plus a
      // millimetre of float slack.
      const double cap = 30.0; // PolylineSmoother.maxCorrectionM default.
      final RoutePoint origin = raw.first;
      final double cosLat = math.max(math.cos(origin.latitude * math.pi / 180), 1e-6);
      double planarMeters(RoutePoint a, RoutePoint b) {
        final double de = (b.longitude - a.longitude) *
            math.pi /
            180 *
            PolylineSmoother.earthRadiusKm *
            1000 *
            cosLat;
        final double dn = (b.latitude - a.latitude) *
            math.pi /
            180 *
            PolylineSmoother.earthRadiusKm *
            1000;
        return math.sqrt(de * de + dn * dn);
      }

      for (int i = 0; i < raw.length; i++) {
        expect(
          planarMeters(raw[i], smoothed[i]),
          lessThanOrEqualTo(cap + 1e-3),
          reason: 'vertex $i drifted beyond the smoothing cap',
        );
      }

      // Endpoints are anchored: the map route starts and ends exactly where the
      // recording did (trail-head accuracy).
      expect(smoothed.first.latitude, closeTo(raw.first.latitude, 1e-12));
      expect(smoothed.first.longitude, closeTo(raw.first.longitude, 1e-12));
      expect(smoothed.last.latitude, closeTo(raw.last.latitude, 1e-12));
      expect(smoothed.last.longitude, closeTo(raw.last.longitude, 1e-12));

      // The jitter was actually suppressed: the smoothed line is straighter
      // (smaller cross-track spread) than the raw one it came from.
      double rawSpread = 0;
      double smoothedSpread = 0;
      for (int i = 0; i < raw.length; i++) {
        rawSpread += (raw[i].latitude - 30.0).abs();
        smoothedSpread += (smoothed[i].latitude - 30.0).abs();
      }
      expect(smoothedSpread, lessThan(rawSpread));

      await engine.detach();
    });

    test('map vertices carry timestamps so the timeline matches the geometry',
        () async {
      final _RecordingStore store = _RecordingStore(await openBox('_map3'));
      final DailyTrackEngine engine = DailyTrackEngine(store: store);
      final DateTime base = _todayMorning();

      final List<DateTime> stamps = <DateTime>[
        for (int i = 0; i < 3; i++) base.add(Duration(seconds: 10 * i)),
      ];
      for (int i = 0; i < stamps.length; i++) {
        engine.recordPosition(
          _fix(30.0 + i * 0.001, 31.0, at: stamps[i], speed: 15),
        );
      }

      expect(
        engine.smoothedPath.map((RoutePoint p) => p.at).toList(),
        stamps,
        reason: 'the smoothed path must preserve every fix timestamp',
      );

      await engine.detach();
    });
  });

  group('Motion pipeline: classified event -> mapper -> log -> stream', () {
    test('every classified kind is mapped, recorded and emitted', () async {
      // Vehicle context is required for observeDrivingEvent to record.
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      analyzer.observeTransport(TransportMode.vehicle);

      final List<DrivingEvent> emitted = <DrivingEvent>[];
      final StreamSubscription<DrivingEvent> sub =
          analyzer.onEvent.listen(emitted.add);

      const List<MotionEventKind> kinds = <MotionEventKind>[
        MotionEventKind.hardBrake,
        MotionEventKind.hardAccel,
        MotionEventKind.sharpTurn,
        MotionEventKind.speedBump,
        MotionEventKind.pothole,
      ];
      final List<DrivingEventType> expected = <DrivingEventType>[
        DrivingEventType.harshBraking,
        DrivingEventType.harshAcceleration,
        DrivingEventType.sharpTurn,
        DrivingEventType.speedBump,
        DrivingEventType.pothole,
      ];

      for (int i = 0; i < kinds.length; i++) {
        final DrivingEvent? mapped = toDrivingEvent(
          MotionEvent(
            kind: kinds[i],
            confidence: 0.9,
            peakMps2: 4.0 + i,
            startedAt: DateTime(2026, 1, 1, 8, 0, i),
          ),
        );
        expect(mapped, isNotNull, reason: '${kinds[i]} must map to an event');
        expect(mapped!.type, expected[i]);
        expect(analyzer.observeDrivingEvent(mapped), isTrue);
      }

      await Future<void>.delayed(Duration.zero);
      expect(analyzer.events, hasLength(kinds.length));
      expect(
        analyzer.events.map((DrivingEvent e) => e.type).toList(),
        expected,
        reason: 'no kind may be silently dropped from the event log',
      );
      expect(emitted, hasLength(kinds.length));

      // smoothDrive is a state, not a maneuver: it must never reach the log.
      expect(
        toDrivingEvent(
          MotionEvent(
            kind: MotionEventKind.smoothDrive,
            confidence: 0,
            peakMps2: 0,
            startedAt: DateTime(2026, 1, 1),
          ),
        ),
        isNull,
      );

      await sub.cancel();
    });

    test('a classified event is suppressed outside a vehicle context', () {
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      // Default verdict is stationary -> the vehicle gate must hold the event
      // back rather than polluting the log.
      final DrivingEvent mapped = toDrivingEvent(
        MotionEvent(
          kind: MotionEventKind.pothole,
          confidence: 0.8,
          peakMps2: 6,
          startedAt: DateTime(2026, 1, 1),
        ),
      )!;
      expect(analyzer.observeDrivingEvent(mapped), isFalse);
      expect(analyzer.events, isEmpty);
    });

    test('magnitude survives the pipeline, not just the kind', () {
      final DrivingEvent? mapped = toDrivingEvent(
        MotionEvent(
          kind: MotionEventKind.sharpTurn,
          confidence: 0.85,
          peakMps2: 7.25,
          startedAt: DateTime(2026, 1, 1, 9),
        ),
      );
      expect(mapped, isNotNull);
      expect(mapped!.peakMps2, 7.25);
      // Lateral turns carry zero duration (instant classified crossing).
      expect(mapped.duration, Duration.zero);
    });
  });

  group('Adaptive profile inputs are live during a session', () {
    test('engine distance and path both advance from the same fix stream',
        () async {
      final _RecordingStore store = _RecordingStore(await openBox('_live'));
      final DailyTrackEngine engine = DailyTrackEngine(store: store);
      final DateTime base = _todayMorning();

      int notifications = 0;
      final StreamSubscription<void> sub = engine.changes.listen((_) {
        notifications += 1;
      });

      // ~96 m east per step, 5 s apart -> ~20 m/s, a plausible drive.
      for (int i = 0; i < 10; i++) {
        engine.recordPosition(
          _fix(30.0, 31.0 + i * 0.001, at: base.add(Duration(seconds: 5 * i)),
              speed: 20),
        );
      }

      await Future<void>.delayed(Duration.zero);

      // Both derived outputs advanced: the metric and the geometry are not
      // orphaned from one another.
      expect(engine.totalDistanceKm, greaterThan(0));
      expect(engine.dayPath, hasLength(10));
      expect(notifications, greaterThan(0));

      // The straight-line sanity check: 9 steps of ~96 m ≈ 0.87 km.
      final double straight = _metersBetween(engine.dayPath.first,
              engine.dayPath.last) /
          1000;
      final double drift = (engine.totalDistanceKm - straight).abs();
      expect(drift, lessThan(0.02), reason: 'distance and path agree');

      // max-speed is derived from the same fixes.
      expect(engine.maxSpeedKmh, greaterThan(50));

      await sub.cancel();
      await engine.detach();
    });
  });
}
