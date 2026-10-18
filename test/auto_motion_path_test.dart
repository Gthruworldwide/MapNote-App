import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/src/core/config/app_config.dart';
import 'package:routenote/src/data/local/auto_motion_data_source.dart';
import 'package:routenote/src/data/models/daily_gps_summary.dart';
import 'package:routenote/src/services/daily_track_engine.dart';
import 'package:routenote/src/services/gap_recovery_service.dart';
import 'package:routenote/src/services/motion_profiler.dart';
import 'package:routenote/src/services/polyline_smoother.dart';

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

/// Store that records every write instead of touching Hive, so the engine's
/// fire-and-forget persists can be observed synchronously without waiting on
/// disk (the override appends before its first await point).
class _RecordingStore extends AutoMotionDataSource {
  _RecordingStore(super.box);

  final List<DailyGpsSummary> saved = <DailyGpsSummary>[];

  @override
  Future<void> save(DailyGpsSummary summary) async {
    saved.add(summary);
  }
}

/// A [PolylineSmoother] that returns its input untouched, so a test can drive
/// tens of thousands of engine fixes without paying for the Kalman pass (the
/// engine smooths on every persist).
class _PassthroughSmoother extends PolylineSmoother {
  const _PassthroughSmoother();

  @override
  List<RoutePoint> smooth(List<RoutePoint> points) => points;
}

/// Today at 08:00 local: a same-day timestamp base that can never cross local
/// midnight no matter when the suite runs — the only wall-clock fact these
/// tests rely on.
DateTime _todayMorning() =>
    DailyGpsSummary.dayOf(DateTime.now()).add(const Duration(hours: 8));

/// Forty fixes heading straight east along lat 30.0 (0.001° ≈ 96 m every
/// 5 s) with the classic ±0.00009° (~±10 m) cross-track GPS wobble — the raw
/// trace whose jitter must never reach the dashboard or disk. Timestamps run
/// from [base] so no fix can roll the engine over a calendar day.
List<Position> _jitteryFixes(DateTime base) => <Position>[
      for (int i = 0; i < 40; i++)
        _fix(
          30.0 + (i.isEven ? 0.00009 : -0.00009),
          31.0 + i * 0.001,
          at: base.add(Duration(seconds: 5 * i)),
        ),
    ];

/// Distance between two vertices in metres — reuses the trackers' canonical
/// great-circle implementation so the tests measure exactly like production.
double _metersBetween(RoutePoint a, RoutePoint b) =>
    GapRecoveryService.haversineKm(
          a.latitude,
          a.longitude,
          b.latitude,
          b.longitude,
        ) *
        1000;

/// How far a point sits north/south of the horizontal line through [lineLat],
/// in metres (positive = north of the line).
double _crossTrackNorthM(RoutePoint point, double lineLat) =>
    (point.latitude - lineLat) *
    (math.pi / 180) *
    PolylineSmoother.earthRadiusKm *
    1000;

void main() {
  late Directory tempDir;
  final List<Box<dynamic>> openBoxes = <Box<dynamic>>[];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('routenote_path_');
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

  group('DailyTrackEngine path recording', () {
    test('accepted fixes land in dayPath in order with their fix timestamps',
        () async {
      final _RecordingStore store = _RecordingStore(await openBox('_path'));
      final DailyTrackEngine engine = DailyTrackEngine(store: store);
      final DateTime base = _todayMorning();

      engine.recordPosition(_fix(30.0, 31.0, at: base));
      engine.recordPosition(
        _fix(30.001, 31.0, at: base.add(const Duration(seconds: 5))),
      );
      engine.recordPosition(
        _fix(30.002, 31.0, at: base.add(const Duration(seconds: 10))),
      );

      expect(engine.dayPath, <RoutePoint>[
        RoutePoint(latitude: 30.0, longitude: 31.0, at: base),
        RoutePoint(
          latitude: 30.001,
          longitude: 31.0,
          at: base.add(const Duration(seconds: 5)),
        ),
        RoutePoint(
          latitude: 30.002,
          longitude: 31.0,
          at: base.add(const Duration(seconds: 10)),
        ),
      ]);
      // The vertex keeps the fix's own timestamp: the smoother's per-step dt
      // and the persisted [lat, lon, epoch-ms] triples both read from it.
      expect(engine.dayPath.first.at, base);
      expect(engine.dayPath.last.at, base.add(const Duration(seconds: 10)));
      expect(engine.dayPath, hasLength(3));
    });

    test('a fix without usable accuracy never touches the path or storage',
        () async {
      final _RecordingStore store =
          _RecordingStore(await openBox('_path_reject'));
      final DailyTrackEngine engine = DailyTrackEngine(store: store);
      final DateTime base = _todayMorning();

      // Both rejections, before any fix was ever accepted.
      engine.recordPosition(_fix(30.0, 31.0, at: base, accuracy: 50));
      engine.recordPosition(_fix(30.0, 31.0, at: base, hasAccuracy: false));
      expect(engine.dayPath, isEmpty);
      expect(store.saved, isEmpty, reason: 'a rejected fix does not persist');

      // …and after a good fix, both the path and the saved summaries stay
      // pinned to accepted fixes only.
      engine.recordPosition(
        _fix(30.001, 31.0, at: base.add(const Duration(seconds: 5))),
      );
      engine.recordPosition(
        _fix(
          30.002,
          31.0,
          at: base.add(const Duration(seconds: 10)),
          accuracy: 50,
        ),
      );
      engine.recordPosition(
        _fix(
          30.003,
          31.0,
          at: base.add(const Duration(seconds: 15)),
          hasAccuracy: false,
        ),
      );
      expect(engine.dayPath, hasLength(1));
      expect(store.saved, hasLength(1));
    });
  });

  group('DailyTrackEngine path smoothing', () {
    test('smoothedPath anchors the endpoints and suppresses the raw jitter',
        () async {
      final _RecordingStore store =
          _RecordingStore(await openBox('_smooth_jitter'));
      final DailyTrackEngine engine = DailyTrackEngine(store: store);
      for (final Position fix in _jitteryFixes(_todayMorning())) {
        engine.recordPosition(fix);
      }

      final List<RoutePoint> raw = engine.dayPath;
      final List<RoutePoint> smoothed = engine.smoothedPath;
      expect(smoothed, hasLength(raw.length));
      // Anchors: the smoothed route still starts and ends exactly where the
      // recording did.
      expect(smoothed.first, raw.first);
      expect(smoothed.last, raw.last);

      // Same idiom as polyline_smoother_test: sum-of-squares about the true
      // line proves the intermediate vertices straightened, while every
      // vertex stays inside the correction clamp.
      double inputSumSquares = 0;
      double outputSumSquares = 0;
      for (int i = 0; i < raw.length; i++) {
        final double input = _crossTrackNorthM(raw[i], 30.0);
        final double output = _crossTrackNorthM(smoothed[i], 30.0);
        inputSumSquares += input * input;
        outputSumSquares += output * output;
        expect(_metersBetween(smoothed[i], raw[i]), lessThanOrEqualTo(30.5));
      }
      final double inputRmsM = math.sqrt(inputSumSquares / raw.length);
      final double outputRmsM = math.sqrt(outputSumSquares / raw.length);
      expect(inputRmsM, greaterThan(9.5), reason: 'raw wobble is ~10 m');
      expect(
        outputRmsM,
        lessThan(0.6 * inputRmsM),
        reason: 'the engine keeps well under half the jitter',
      );
    });

    test('a straight, noise-free path comes back essentially unchanged',
        () async {
      final _RecordingStore store =
          _RecordingStore(await openBox('_smooth_clean'));
      final DailyTrackEngine engine = DailyTrackEngine(store: store);
      final DateTime base = _todayMorning();

      for (int i = 0; i < 10; i++) {
        engine.recordPosition(
          _fix(30.0, 31.0 + i * 0.001, at: base.add(Duration(seconds: 5 * i))),
        );
      }

      final List<RoutePoint> raw = engine.dayPath;
      final List<RoutePoint> smoothed = engine.smoothedPath;
      expect(smoothed, hasLength(raw.length));
      expect(smoothed.first, raw.first);
      expect(smoothed.last, raw.last);
      for (int i = 1; i < raw.length - 1; i++) {
        expect(
          _crossTrackNorthM(smoothed[i], 30.0).abs(),
          lessThan(0.01),
          reason: 'vertex $i must stay on the line',
        );
        expect(_metersBetween(smoothed[i], raw[i]), lessThan(30.5));
      }
    });
  });

  group('DailyTrackEngine path persistence', () {
    test('the saved summary carries the smoothed path, never the raw one',
        () async {
      final _RecordingStore store =
          _RecordingStore(await openBox('_persist_path'));
      final DailyTrackEngine engine = DailyTrackEngine(store: store);
      for (final Position fix in _jitteryFixes(_todayMorning())) {
        engine.recordPosition(fix);
      }

      // _RecordingStore appends synchronously inside save(), so the last
      // entry is exactly what the final fix persisted (its path was captured
      // synchronously, before the unawaited write resolved).
      expect(store.saved, isNotEmpty);
      final DailyGpsSummary last = store.saved.last;
      expect(last.date, DailyGpsSummary.dayOf(DateTime.now()));
      expect(last.path, isNotNull);
      final List<RoutePoint> persisted = last.path!;
      expect(persisted, engine.smoothedPath, reason: 'disk gets the smoother');
      expect(persisted, hasLength(engine.dayPath.length));
      expect(
        persisted,
        isNot(equals(engine.dayPath)),
        reason: 'disk never gets the raw jitter',
      );
    });

    test('a day flushed with zero accepted fixes stores a null path, never an empty list',
        () async {
      final _RecordingStore store =
          _RecordingStore(await openBox('_persist_empty'));
      final DailyTrackEngine engine = DailyTrackEngine(store: store);
      final DateTime today = DailyGpsSummary.dayOf(DateTime.now());
      final DateTime tomorrow = today.add(const Duration(days: 1));

      // The first fix already sits on tomorrow: today is flushed on the way
      // into the rollover while it still holds zero accepted fixes.
      engine.recordPosition(_fix(30.0, 31.0, at: tomorrow));

      expect(store.saved, hasLength(2));
      final DailyGpsSummary outgoing = store.saved.first;
      expect(outgoing.date, today);
      expect(outgoing.path, isNull, reason: 'no fixes yet — null, not []');
      expect(outgoing.toMap()['path'], isNull);
      expect(store.saved.last.date, tomorrow);
      expect(store.saved.last.path, hasLength(1));
    });
  });

  group('DailyTrackEngine day rollover', () {
    test('crossing midnight saves yesterday with its path and starts today fresh',
        () async {
      final _RecordingStore store =
          _RecordingStore(await openBox('_rollover_path'));
      final DailyTrackEngine engine = DailyTrackEngine(store: store);
      final DateTime today = DailyGpsSummary.dayOf(DateTime.now());
      final DateTime yesterday = today.subtract(const Duration(days: 1));
      final DateTime yesterdayLate =
          yesterday.add(const Duration(hours: 23, minutes: 59));
      final List<DateTime> yesterdayStamps = <DateTime>[
        yesterdayLate,
        yesterdayLate.add(const Duration(seconds: 30)),
        yesterdayLate.add(const Duration(seconds: 50)),
      ];

      engine.recordPosition(_fix(0, 0, at: yesterdayStamps[0]));
      engine.recordPosition(_fix(0.0005, 0, at: yesterdayStamps[1]));
      engine.recordPosition(_fix(0.001, 0, at: yesterdayStamps[2]));
      // The first fix already sits on yesterday, so today (still empty) is
      // flushed on the way *into* the rollover; this final fix rolls back.
      final DateTime todayFirst = today.add(const Duration(minutes: 1));
      engine.recordPosition(_fix(0.0015, 0, at: todayFirst));

      // Yesterday's summary carries yesterday's route: three vertices, the
      // anchored endpoints exactly as recorded, every timestamp preserved.
      final List<DailyGpsSummary> yesterdaySaved = store.saved
          .where((DailyGpsSummary s) => s.date == yesterday)
          .toList();
      expect(yesterdaySaved, hasLength(4));
      expect(yesterdaySaved.last.path, isNotNull);
      final List<RoutePoint> yesterdayPath = yesterdaySaved.last.path!;
      expect(yesterdayPath, hasLength(3));
      expect(
        yesterdayPath.first,
        RoutePoint(latitude: 0, longitude: 0, at: yesterdayStamps[0]),
      );
      expect(
        yesterdayPath.last,
        RoutePoint(latitude: 0.001, longitude: 0, at: yesterdayStamps[2]),
      );
      for (int i = 0; i < yesterdayPath.length; i++) {
        expect(yesterdayPath[i].at, yesterdayStamps[i]);
      }

      // Today started fresh: the pre-switch flush stored a null path, and the
      // only summary written since holds today's own single fix — yesterday's
      // route never leaks across the boundary.
      final List<DailyGpsSummary> todaySaved =
          store.saved.where((DailyGpsSummary s) => s.date == today).toList();
      expect(todaySaved, hasLength(2));
      expect(store.saved.first.date, today,
          reason: 'the empty day is flushed before the switch');
      expect(todaySaved.first.path, isNull);
      expect(todaySaved.last.path, hasLength(1));
      expect(
        todaySaved.last.path!.single,
        RoutePoint(latitude: 0.0015, longitude: 0, at: todayFirst),
      );
      expect(engine.dayPath, hasLength(1));
    });
  });

  group('DailyTrackEngine restart restore', () {
    test('a fresh engine resumes the stored route and its live path wins the next resync',
        () async {
      final AutoMotionDataSource store =
          AutoMotionDataSource(await openBox('_restore_path'));
      final DateTime today = DailyGpsSummary.dayOf(DateTime.now());
      final DateTime stamp = today.add(const Duration(hours: 8));
      // Exactly-representable at the 5-decimal grid the map codec rounds to,
      // so the round-tripped route compares verbatim against the source.
      const List<double> lats = <double>[30.0, 30.001, 30.002, 30.003, 30.004];
      final List<RoutePoint> route = <RoutePoint>[
        for (int i = 0; i < lats.length; i++)
          RoutePoint(
            latitude: lats[i],
            longitude: 31.0,
            at: stamp.add(Duration(minutes: i)),
          ),
      ];
      await store.save(DailyGpsSummary(date: today, totalKm: 1.25, path: route));

      final DailyTrackEngine fresh = DailyTrackEngine(store: store);
      expect(fresh.dayPath, isEmpty, reason: 'a fresh engine starts empty');
      await fresh.resyncFromStore();

      expect(fresh.totalDistanceKm, 1.25);
      expect(
        fresh.dayPath,
        store.summaryFor(today)!.path,
        reason: 'the stored route resumes verbatim',
      );
      expect(fresh.dayPath, route);

      // A live fix appends to the restored route…
      final Position live = _fix(30.005, 31.0, at: today.add(const Duration(hours: 9)));
      fresh.recordPosition(live);
      final RoutePoint liveVertex = RoutePoint(
        latitude: live.latitude,
        longitude: live.longitude,
        at: live.timestamp,
      );
      expect(fresh.dayPath, hasLength(route.length + 1));
      expect(fresh.dayPath.first, route.first);
      expect(fresh.dayPath.last, liveVertex);

      // …and the next resync keeps the live in-memory path instead of
      // replacing it with what is (still) on disk.
      await fresh.resyncFromStore();
      expect(fresh.dayPath, hasLength(route.length + 1));
      expect(fresh.dayPath.last, liveVertex);
      expect(fresh.dayPath.first, route.first);

      // Let the fire-and-forget write land before tearDown closes the box.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  });

  group('DailyTrackEngine path cap', () {
    test('reaching maxPathPoints halves the path, keeping every even vertex',
        () async {
      expect(DailyTrackEngine.maxPathPoints, 4096);
      final _RecordingStore store =
          _RecordingStore(await openBox('_decimate'));
      // The passthrough keeps the 4097 per-fix persists cheap; decimation
      // itself lives in the engine, not the smoother.
      final DailyTrackEngine engine = DailyTrackEngine(
        store: store,
        smoother: const _PassthroughSmoother(),
      );
      final DateTime base = _todayMorning();

      // 4097 accepted fixes, ~1 m apart and 3 s apart in time: the 4097th
      // lands on a path already at the cap, so the pre-append halving runs
      // exactly once (4096 → 2048) and the new fix brings it to 2049.
      final List<RoutePoint> fed = <RoutePoint>[];
      for (int i = 0; i <= DailyTrackEngine.maxPathPoints; i++) {
        final RoutePoint point = RoutePoint(
          latitude: 30.0 + i * 0.000009,
          longitude: 31.0,
          at: base.add(Duration(seconds: 3 * i)),
        );
        fed.add(point);
        engine.recordPosition(_fix(point.latitude, point.longitude, at: point.at));
      }

      expect(engine.dayPath, hasLength(2049));
      // The retained vertices are exactly the even indices of the pre-halving
      // list, plus the fix that triggered the append.
      expect(engine.dayPath.first, fed[0]);
      expect(engine.dayPath[1], fed[2]);
      expect(engine.dayPath[2], fed[4]);
      expect(engine.dayPath.last, fed[DailyTrackEngine.maxPathPoints]);
    });
  });

  group('DailyTrackEngine analyzer feed', () {
    test('a single fix speed leaves the acceleration EMA null', () async {
      final _RecordingStore store = _RecordingStore(await openBox('_accel_seed'));
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      final DailyTrackEngine engine =
          DailyTrackEngine(store: store, behavior: analyzer);
      final DateTime base = _todayMorning();

      expect(analyzer.instantAccelerationMps2, isNull);
      engine.recordPosition(_fix(30.0, 31.0, at: base, speed: 5));
      expect(
        analyzer.instantAccelerationMps2,
        isNull,
        reason: 'one reading cannot be differentiated',
      );
    });

    test('two fix speeds two seconds apart seed the EMA with the raw delta',
        () async {
      final _RecordingStore store = _RecordingStore(await openBox('_accel_feed'));
      final MotionBehaviorAnalyzer analyzer = MotionBehaviorAnalyzer();
      final DailyTrackEngine engine =
          DailyTrackEngine(store: store, behavior: analyzer);
      final DateTime base = _todayMorning();

      engine.recordPosition(_fix(30.0, 31.0, at: base, speed: 0));
      engine.recordPosition(
        _fix(30.0001, 31.0, at: base.add(const Duration(seconds: 2)), speed: 8),
      );

      // The analyzer differentiates on FIX timestamps, not the wall clock:
      // (8 − 0) m/s over 2 s = 4.0, and the first delta seeds the EMA
      // directly instead of blending with a previous estimate.
      expect(analyzer.instantAccelerationMps2, 4.0);
    });
  });

  group('DailyGpsSummary path serialisation', () {
    test('toMap → fromMap round-trips the path with timestamps at 5 decimals',
        () {
      final DateTime day = DateTime(2026, 10, 11);
      final DateTime at = DateTime(2026, 10, 11, 8, 30);
      final DailyGpsSummary summary = DailyGpsSummary(
        date: day,
        totalKm: 1.5,
        maxSpeedKmh: 42,
        lastLatitude: 30.1,
        lastLongitude: 31.2,
        lastFixAt: at,
        path: <RoutePoint>[
          RoutePoint(latitude: 30.123456789, longitude: 31.987654321, at: at),
          RoutePoint(
            latitude: 30.0,
            longitude: 31.5,
            at: at.add(const Duration(minutes: 5)),
          ),
        ],
      );

      final Map<String, dynamic> map = summary.toMap();
      expect(map['date'], '2026-10-11');
      // [lat, lon, epoch-ms] triples, coordinates rounded to 5 decimals
      // (~1.1 m), timestamps exact.
      expect(map['path'], <List<Object?>>[
        <Object?>[30.12346, 31.98765, at.millisecondsSinceEpoch],
        <Object?>[
          30.0,
          31.5,
          at.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
        ],
      ]);

      final DailyGpsSummary restored = DailyGpsSummary.fromMap(map);
      expect(restored.date, day);
      expect(restored.totalKm, 1.5);
      expect(restored.maxSpeedKmh, 42);
      expect(restored.lastLatitude, 30.1);
      expect(restored.lastLongitude, 31.2);
      expect(restored.lastFixAt, at);
      expect(restored.path, isNotNull);
      final List<RoutePoint> path = restored.path!;
      expect(path, hasLength(2));
      expect(path.first, RoutePoint(latitude: 30.12346, longitude: 31.98765, at: at));
      expect(
        path.last,
        RoutePoint(
          latitude: 30.0,
          longitude: 31.5,
          at: at.add(const Duration(minutes: 5)),
        ),
      );
    });

    test('a legacy map without the path key parses back with a null path', () {
      final DateTime day = DateTime(2026, 10, 11);
      final DailyGpsSummary pathless = DailyGpsSummary(date: day, totalKm: 3);
      // A path-less summary serialises the key as null — never an empty list.
      expect(pathless.toMap()['path'], isNull);
      expect(DailyGpsSummary.fromMap(pathless.toMap()).path, isNull);

      // A record written before the field existed has no key at all; the
      // tolerant parser still yields null instead of failing the restore.
      final Map<String, dynamic> legacy = pathless.toMap()..remove('path');
      expect(legacy.containsKey('path'), isFalse);
      expect(DailyGpsSummary.fromMap(legacy).path, isNull);
    });

    test('a wrong-typed path value degrades to null', () {
      final DailyGpsSummary summary = DailyGpsSummary(
        date: DateTime(2026, 10, 11),
        path: const <RoutePoint>[RoutePoint(latitude: 30.0, longitude: 31.0)],
      );
      final Map<String, dynamic> map = summary.toMap();
      expect(map['path'], isNotNull);

      map['path'] = 'garbage';
      expect(DailyGpsSummary.fromMap(map).path, isNull);
      map['path'] = 42;
      expect(DailyGpsSummary.fromMap(map).path, isNull);
    });

    test('malformed vertex entries are skipped while valid ones are kept', () {
      final DateTime epoch = DateTime.fromMillisecondsSinceEpoch(1728000000);
      final Map<String, dynamic> map =
          DailyGpsSummary(date: DateTime(2026, 10, 11)).toMap();
      map['path'] = <Object?>[
        <Object?>[30.1, 31.1, epoch.millisecondsSinceEpoch], // intact triple
        'not-a-list', // wrong container type → skipped
        <Object?>[30.2], // too short → skipped
        <Object?>['lat', 'lon'], // non-numeric coordinates → skipped
        42, // wrong entry type → skipped
        <Object?>[30.3, 31.3, 'not-a-time'], // coordinates kept, time dropped
        <Object?>[30.4, 31.4], // coordinate pair with no time
      ];

      final List<RoutePoint>? parsed = DailyGpsSummary.fromMap(map).path;
      expect(parsed, isNotNull);
      final List<RoutePoint> path = parsed!;
      expect(path, hasLength(3));
      expect(path[0], RoutePoint(latitude: 30.1, longitude: 31.1, at: epoch));
      expect(path[1], const RoutePoint(latitude: 30.3, longitude: 31.3));
      expect(path[2], const RoutePoint(latitude: 30.4, longitude: 31.4));
    });

    test('summaries differing only in their path still compare equal', () {
      final DateTime day = DateTime(2026, 10, 11);
      final DailyGpsSummary oneVertex = DailyGpsSummary(
        date: day,
        totalKm: 2,
        path: const <RoutePoint>[RoutePoint(latitude: 30.0, longitude: 31.0)],
      );
      final DailyGpsSummary twoVertices = DailyGpsSummary(
        date: day,
        totalKm: 2,
        path: const <RoutePoint>[
          RoutePoint(latitude: 30.5, longitude: 31.5),
          RoutePoint(latitude: 30.6, longitude: 31.6),
        ],
      );

      expect(oneVertex, twoVertices);
      expect(oneVertex.hashCode, twoVertices.hashCode);

      // …while the metrics still drive identity.
      final DailyGpsSummary differentMetrics =
          DailyGpsSummary(date: day, totalKm: 9);
      expect(oneVertex, isNot(equals(differentMetrics)));
    });
  });
}
