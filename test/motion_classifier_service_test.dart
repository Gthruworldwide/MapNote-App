import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/data/models/daily_motion_summary.dart';
import 'package:routenote/src/data/models/track_point.dart';
import 'package:routenote/src/data/models/trip_segment.dart';
import 'package:routenote/src/services/motion_classifier_service.dart';

/// Metres per degree of latitude at the test latitude (~30°). Good enough to
/// build a physically consistent route: the classifier's own haversine math
/// decides the distances.
const double _metresPerDegreeLat = 111_320;

final DateTime _day = DateTime(2026, 10, 20);
final DateTime _morning = DateTime(2026, 10, 20, 8);

/// A straight northbound track of [seconds] at [speedMps], one fix every 5 s.
///
/// Speed is stamped on the fix (the Doppler case). Pass `reportedSpeed: false`
/// to build a speed-less track instead, which is what a summary recorded before
/// per-fix speeds existed looks like.
///
/// No fix carries a step count, so every fix is labelled by speed alone:
/// above [MotionClassifierService.vehicleSpeedKmh] it is a drive, otherwise it
/// is a stopover. That is the deliberate consequence of the hybrid rule — a
/// GPS-only track can no longer claim to be walking.
List<TrackPoint> _track({
  required DateTime start,
  required int seconds,
  required double speedMps,
  double latitude = 30.0444,
  double longitude = 31.2357,
  bool reportedSpeed = true,
  String activity = '',
  double accuracy = 5,
}) {
  final List<TrackPoint> points = <TrackPoint>[];
  for (int offset = 0; offset <= seconds; offset += 5) {
    points.add(
      TrackPoint(
        latitude: latitude + (speedMps * offset) / _metresPerDegreeLat,
        longitude: longitude,
        timestamp: start.add(Duration(seconds: offset)),
        speed: reportedSpeed ? speedMps : 0,
        hasSpeed: reportedSpeed,
        accuracy: accuracy,
        detectedActivity: activity,
      ),
    );
  }
  return points;
}

/// A parked track: same place, no speed, for [seconds].
///
/// [jitterDegrees] drifts the coordinates, which is what a stationary receiver
/// actually reports and what the stopover-radius rule has to tolerate.
List<TrackPoint> _parked({
  required DateTime start,
  required int seconds,
  double latitude = 30.0444,
  double longitude = 31.2357,
  double jitterDegrees = 0,
  String activity = TrackPoint.still,
  double accuracy = 5,
}) {
  final List<TrackPoint> points = <TrackPoint>[];
  for (int offset = 0; offset <= seconds; offset += 5) {
    // Alternate sides so the parked track wanders instead of repeating a point.
    final bool north = (offset ~/ 5).isEven;
    points.add(
      TrackPoint(
        latitude: latitude + (north ? jitterDegrees : 0),
        longitude: longitude,
        timestamp: start.add(Duration(seconds: offset)),
        speed: 0,
        hasSpeed: true,
        accuracy: accuracy,
        detectedActivity: activity,
      ),
    );
  }
  return points;
}

/// A track that carries a **measured** step count, one fix every 5 s.
///
/// Every fix after the first states how many steps the hardware counted since
/// the previous one, which is exactly what `StepMeter.drain` persists. With 5 s
/// fixes, [stepsPerFix] converts straight into cadence: `stepsPerFix * 12`
/// steps per minute, so 8 → 96/min (a walk) and 14 → 168/min (a run).
///
/// The first fix carries no measurement (`null`), because the meter only learns
/// its baseline from the first sample it sees. It is therefore labelled by speed
/// alone — a stopover at walking pace — and the merge stage folds that single
/// fix into the first real gait group.
List<TrackPoint> _gait({
  required DateTime start,
  required int seconds,
  required double speedMps,
  required int stepsPerFix,
  double latitude = 30.0444,
  double longitude = 31.2357,
}) {
  final List<TrackPoint> points = <TrackPoint>[];
  int index = 0;
  for (int offset = 0; offset <= seconds; offset += 5) {
    points.add(
      TrackPoint(
        latitude: latitude + (speedMps * offset) / _metresPerDegreeLat,
        longitude: longitude,
        timestamp: start.add(Duration(seconds: offset)),
        speed: speedMps,
        hasSpeed: true,
        accuracy: 5,
        steps: index == 0 ? null : stepsPerFix,
      ),
    );
    index += 1;
  }
  return points;
}

DailyMotionSummary _classify(
  List<TrackPoint> points, {
  MotionClassifierService service = const MotionClassifierService(),
}) => service.classify(date: _day, points: points);

void main() {
  group('MotionClassifierService — happy path', () {
    test('a steady drive is one vehicle segment with its distance and speed',
        () {
      // 10 minutes at 20 m/s = 72 km/h ≈ 12 km, no steps counted.
      final DailyMotionSummary summary = _classify(
        _track(start: _morning, seconds: 600, speedMps: 20),
      );

      expect(summary.segments, hasLength(1));
      final TripSegment drive = summary.segments.single;
      expect(drive.type, MotionType.vehicle);
      expect(drive.duration, const Duration(minutes: 10));
      expect(drive.distanceKm, closeTo(12.0, 0.2));
      expect(drive.averageSpeedKmH, closeTo(72, 2));
      expect(summary.vehicleDistanceKm, closeTo(12.0, 0.2));
      expect(summary.vehicleDuration, const Duration(minutes: 10));
      expect(summary.stopoverDuration, Duration.zero);
      expect(summary.isEmpty, isFalse);
    });

    test('movement with no measured steps is a stopover, never a walk', () {
      // 4 minutes at 1.4 m/s (5 km/h) with no step samples. A GPS receiver
      // cannot tell a walk from drift, so the day reports a stopover and zero
      // walking rather than inventing a gait — and a distance — nobody measured.
      final DailyMotionSummary summary = _classify(
        _track(start: _morning, seconds: 240, speedMps: 1.4),
      );

      expect(summary.segments, hasLength(1));
      final TripSegment stop = summary.segments.single;
      expect(stop.type, MotionType.stationary);
      expect(stop.distanceInMeters, 0);
      expect(summary.walkingDistanceKm, 0);
      expect(summary.stepCount, 0);
      expect(summary.stopoverDuration, const Duration(minutes: 4));
      expect(summary.isEmpty, isFalse);
    });
  });

  group('MotionClassifierService — steps decide on foot', () {
    test('a measured walk uses the step count, not the GPS polyline', () {
      // 4 minutes at 1.4 m/s ≈ 336 m of GPS, but 48 × 8 = 384 steps are the
      // physical truth: 384 × 0.75 m = 288 m.
      final DailyMotionSummary summary = _classify(
        _gait(
          start: _morning,
          seconds: 240,
          speedMps: 1.4,
          stepsPerFix: 8,
        ),
      );

      expect(summary.segments, hasLength(1));
      final TripSegment walk = summary.segments.single;
      expect(walk.type, MotionType.walking);
      expect(walk.steps, 384);
      expect(walk.distanceInMeters, closeTo(288, 1));
      expect(
        walk.distanceInMeters,
        closeTo(384 * TripSegment.walkingStrideMeters, 1e-6),
      );
      expect(summary.walkingDistanceKm, closeTo(0.288, 0.01));
      expect(summary.runningDistanceKm, 0);
      expect(summary.stepCount, 384);
    });

    test('a cadence above the run threshold is a run at the running stride',
        () {
      // 14 steps per 5 s = 168 steps/min, comfortably a jog. 48 × 14 = 672
      // steps × 0.95 m = 638 m.
      final DailyMotionSummary summary = _classify(
        _gait(
          start: _morning,
          seconds: 240,
          speedMps: 3,
          stepsPerFix: 14,
        ),
      );

      expect(summary.segments, hasLength(1));
      final TripSegment run = summary.segments.single;
      expect(run.type, MotionType.running);
      expect(run.steps, 672);
      expect(run.distanceInMeters, closeTo(638.4, 1));
      expect(
        run.distanceInMeters,
        closeTo(672 * TripSegment.runningStrideMeters, 1e-6),
      );
      expect(summary.runningDistanceKm, closeTo(0.638, 0.01));
      expect(summary.walkingDistanceKm, 0);
      expect(summary.stepCount, 672);
    });

    test('a brisk walk stays a walk just below the run threshold', () {
      // 9 steps per 5 s = 108 steps/min: a fast walk, never a run.
      final DailyMotionSummary summary = _classify(
        _gait(
          start: _morning,
          seconds: 240,
          speedMps: 1.6,
          stepsPerFix: 9,
        ),
      );

      expect(summary.segments.single.type, MotionType.walking);
    });

    test('a measured zero at vehicle speed is a drive', () {
      // 72 km/h with no step counted: nothing travelled on foot, so the GPS
      // polyline is a drive — the one case speed still classifies.
      final DailyMotionSummary summary = _classify(
        _gait(
          start: _morning,
          seconds: 300,
          speedMps: 20,
          stepsPerFix: 0,
        ),
      );

      expect(summary.segments, hasLength(1));
      final TripSegment drive = summary.segments.single;
      expect(drive.type, MotionType.vehicle);
      expect(drive.steps, 0);
      // A vehicle has no stride: its distance is the road it covered.
      expect(drive.distanceInMeters, closeTo(6000, 20));
      expect(summary.vehicleDistanceKm, closeTo(6.0, 0.05));
      expect(summary.walkingDistanceKm, 0);
      expect(summary.stepCount, 0);
    });

    test('a sparse step count is still a walk, because it is a measurement',
        () {
      // 1 step per 5 s = 12 steps/min. That is a slow shuffle or a phone
      // rattling in a pocket, but the pedometer did count it. The old cadence
      // floor that discarded it also discarded real slow walks; short *groups*
      // are filtered by duration instead (`minMovingSegment`).
      final DailyMotionSummary summary = _classify(
        _gait(
          start: _morning,
          seconds: 300,
          speedMps: 1,
          stepsPerFix: 1,
        ),
      );

      expect(summary.segments.single.type, MotionType.walking);
      expect(summary.segments.single.steps, 60);
      // The distance is the 60 measured steps at the walking stride.
      expect(summary.segments.single.distanceInMeters, closeTo(45, 1e-6));
      expect(summary.stepCount, 60);
    });

    test('a parked track with zero steps is a stopover with no step count', () {
      final DailyMotionSummary summary = _classify(
        _gait(
          start: _morning,
          seconds: 360,
          speedMps: 0,
          stepsPerFix: 0,
        ),
      );

      expect(summary.segments, hasLength(1));
      final TripSegment stop = summary.segments.single;
      expect(stop.type, MotionType.stationary);
      expect(stop.distanceInMeters, 0);
      // A stopover covers no ground, so its steps are dropped entirely rather
      // than reported as a zero-step walk.
      expect(stop.steps, isNull);
      expect(summary.stepCount, 0);
      expect(summary.stopoverDuration, const Duration(minutes: 6));
    });

    test('a walk followed by a drive splits on the step evidence', () {
      final List<TrackPoint> walk = _gait(
        start: _morning,
        seconds: 120,
        speedMps: 1.4,
        stepsPerFix: 8,
      );
      final double endLatitude = walk.last.latitude;
      final List<TrackPoint> drive = _gait(
        start: _morning.add(const Duration(seconds: 125)),
        seconds: 120,
        speedMps: 20,
        stepsPerFix: 0,
        latitude: endLatitude,
      );

      final DailyMotionSummary summary = _classify(
        <TrackPoint>[...walk, ...drive],
      );

      expect(summary.segments, hasLength(2));
      expect(summary.segments.first.type, MotionType.walking);
      expect(summary.segments.last.type, MotionType.vehicle);
      expect(summary.walkingDistanceKm, greaterThan(0));
      expect(summary.vehicleDistanceKm, greaterThan(0));
      expect(summary.walkingDuration, const Duration(minutes: 2));
      expect(summary.stepCount, 192);
    });
  });

  group('MotionClassifierService — stopovers', () {
    test('a six-minute stop splits the day into drive / stopover / drive', () {
      final List<TrackPoint> points = <TrackPoint>[
        ..._track(start: _morning, seconds: 300, speedMps: 20),
        ..._parked(
          start: _morning.add(const Duration(seconds: 305)),
          seconds: 360,
          latitude: 30.0444 + (20 * 300) / _metresPerDegreeLat,
        ),
        ..._track(
          start: _morning.add(const Duration(seconds: 670)),
          seconds: 300,
          speedMps: 20,
          latitude:
              30.0444 + (20 * 300) / _metresPerDegreeLat +
              // The receiver drifted a metre while parked; the drive resumes
              // from where the car actually is.
              1 / _metresPerDegreeLat,
        ),
      ];

      final DailyMotionSummary summary = _classify(points);

      expect(
        summary.segments.map((TripSegment s) => s.type).toList(),
        <MotionType>[
          MotionType.vehicle,
          MotionType.stationary,
          MotionType.vehicle,
        ],
      );
      final TripSegment stop = summary.segmentsOf(MotionType.stationary).single;
      expect(stop.duration, const Duration(minutes: 6));
      // A stop covers no ground, no matter how much the receiver wandered.
      expect(stop.distanceInMeters, 0);
      expect(stop.averageSpeedKmH, 0);
      expect(summary.stopoverDuration, const Duration(minutes: 6));
      expect(summary.segmentsOf(MotionType.vehicle), hasLength(2));
    });

    test('a stop under three minutes is not a stopover', () {
      // Drive, pause for 2 minutes at a light, drive on.
      final List<TrackPoint> points = <TrackPoint>[
        ..._track(start: _morning, seconds: 180, speedMps: 20),
        ..._parked(
          start: _morning.add(const Duration(seconds: 185)),
          seconds: 120,
          latitude: 30.0444 + (20 * 180) / _metresPerDegreeLat,
        ),
        ..._track(
          start: _morning.add(const Duration(seconds: 310)),
          seconds: 180,
          speedMps: 20,
          latitude: 30.0444 + (20 * 180) / _metresPerDegreeLat,
        ),
      ];

      final DailyMotionSummary summary = _classify(points);

      expect(summary.segments, hasLength(1));
      expect(summary.segments.single.type, MotionType.vehicle);
      // The whole span stays one drive: the light's two minutes are inside it.
      expect(
        summary.segments.single.duration,
        const Duration(minutes: 8, seconds: 10),
      );
      expect(summary.stopoverDuration, Duration.zero);
    });

    test('a stopover tolerates sub-60 m GPS jitter without splitting', () {
      final List<TrackPoint> summaryPoints = <TrackPoint>[
        ..._track(start: _morning, seconds: 120, speedMps: 20),
        ..._parked(
          start: _morning.add(const Duration(seconds: 125)),
          seconds: 300,
          latitude: 30.0444 + (20 * 120) / _metresPerDegreeLat,
          // ~40 m of wander at this latitude.
          jitterDegrees: 0.0004,
        ),
        ..._track(
          start: _morning.add(const Duration(seconds: 430)),
          seconds: 120,
          speedMps: 20,
          latitude: 30.0444 + (20 * 120) / _metresPerDegreeLat,
        ),
      ];

      final DailyMotionSummary summary = _classify(summaryPoints);

      expect(summary.segmentsOf(MotionType.stationary), hasLength(1));
      expect(summary.segmentsOf(MotionType.vehicle), hasLength(2));
    });
  });

  group('MotionClassifierService — blips and short stretches', () {
    test('a red light under a minute is absorbed into the drive', () {
      final List<TrackPoint> points = <TrackPoint>[
        ..._track(start: _morning, seconds: 180, speedMps: 20),
        ..._parked(
          start: _morning.add(const Duration(seconds: 185)),
          seconds: 40,
          latitude: 30.0444 + (20 * 180) / _metresPerDegreeLat,
        ),
        ..._track(
          start: _morning.add(const Duration(seconds: 230)),
          seconds: 180,
          speedMps: 20,
          latitude: 30.0444 + (20 * 180) / _metresPerDegreeLat,
        ),
      ];

      final DailyMotionSummary summary = _classify(points);

      expect(summary.segments, hasLength(1));
      expect(summary.segments.single.type, MotionType.vehicle);
      expect(summary.stopoverDuration, Duration.zero);
    });

    test('a 20-second crawl at walking speed does not split one drive', () {
      final List<TrackPoint> points = <TrackPoint>[
        ..._track(start: _morning, seconds: 120, speedMps: 20),
        ..._track(
          start: _morning.add(const Duration(seconds: 125)),
          seconds: 20,
          speedMps: 1.5,
          latitude: 30.0444 + (20 * 120) / _metresPerDegreeLat,
        ),
        ..._track(
          start: _morning.add(const Duration(seconds: 150)),
          seconds: 120,
          speedMps: 20,
          latitude: 30.0444 + (20 * 120 + 1.5 * 20) / _metresPerDegreeLat,
        ),
      ];

      final DailyMotionSummary summary = _classify(points);

      expect(summary.segments, hasLength(1));
      expect(summary.segments.single.type, MotionType.vehicle);
    });

    test('a genuine walk of several minutes stays its own segment', () {
      const double driveEndMetres = 20 * 180;
      final double driveEnd = 30.0444 + driveEndMetres / _metresPerDegreeLat;
      final List<TrackPoint> points = <TrackPoint>[
        ..._track(start: _morning, seconds: 180, speedMps: 20),
        // 305 s of gait: the first fix carries no sample, so the walking group
        // itself spans exactly five minutes.
        ..._gait(
          start: _morning.add(const Duration(seconds: 185)),
          seconds: 305,
          speedMps: 1.4,
          stepsPerFix: 8,
          latitude: driveEnd,
        ),
        ..._track(
          start: _morning.add(const Duration(seconds: 495)),
          seconds: 180,
          speedMps: 20,
          latitude: driveEnd + (1.4 * 305) / _metresPerDegreeLat,
        ),
      ];

      final DailyMotionSummary summary = _classify(points);

      expect(
        summary.segments.map((TripSegment s) => s.type).toList(),
        <MotionType>[MotionType.vehicle, MotionType.walking, MotionType.vehicle],
      );
      expect(
        summary.segmentsOf(MotionType.walking).single.duration,
        const Duration(minutes: 5),
      );
      expect(summary.walkingDuration, const Duration(minutes: 5));
    });
  });

  group('MotionClassifierService — evidence quality', () {
    test('a sensor activity hint is not motion evidence on its own', () {
      // The platform claims `In_Vehicle` while the GPS reads 3.6 km/h and the
      // pedometer counted nothing. Neither reading supports a drive, so the
      // fix is a stopover — there is no hint short-circuit any more.
      final DailyMotionSummary summary = _classify(
        _track(
          start: _morning,
          seconds: 300,
          speedMps: 1,
          activity: TrackPoint.inVehicle,
        ),
      );

      expect(summary.segments.single.type, MotionType.stationary);
      expect(summary.vehicleDistanceKm, 0);
    });

    test('a Still hint does not stop a measured drive', () {
      final DailyMotionSummary summary = _classify(
        _track(
          start: _morning,
          seconds: 60,
          speedMps: 20,
          activity: TrackPoint.still,
        ),
      );

      expect(summary.segments.single.type, MotionType.vehicle);
    });

    test('fixes with poor accuracy are dropped', () {
      final DailyMotionSummary summary = _classify(
        _track(start: _morning, seconds: 300, speedMps: 20, accuracy: 120),
      );

      expect(summary.isEmpty, isTrue);
    });

    test('a bad-accuracy fix in the middle does not create a gap segment', () {
      final List<TrackPoint> points = _track(
        start: _morning,
        seconds: 300,
        speedMps: 20,
      );
      points[20] = TrackPoint(
        latitude: points[20].latitude,
        longitude: points[20].longitude,
        timestamp: points[20].timestamp,
        speed: points[20].speed,
        hasSpeed: points[20].hasSpeed,
        accuracy: 500,
        detectedActivity: '',
      );

      final DailyMotionSummary summary = _classify(points);

      expect(summary.segments, hasLength(1));
      expect(summary.segments.single.type, MotionType.vehicle);
    });

    test('a speed-less stored route still classifies from geometry', () {
      // The legacy shape: parsed path vertices, no speed, no accuracy.
      final DailyMotionSummary summary = _classify(
        _track(
          start: _morning,
          seconds: 300,
          speedMps: 20,
          reportedSpeed: false,
          accuracy: 0,
        ),
      );

      expect(summary.segments, hasLength(1));
      expect(summary.segments.single.type, MotionType.vehicle);
      expect(summary.segments.single.averageSpeedKmH, closeTo(72, 2));
    });
  });

  group('MotionClassifierService — interruptions and bad input', () {
    test('a GPS hole longer than the gap limit ends the segment', () {
      final List<TrackPoint> points = <TrackPoint>[
        ..._track(start: _morning, seconds: 120, speedMps: 20),
        // The app was killed for half an hour, then tracking resumed 20 km on.
        ..._track(
          start: _morning.add(const Duration(minutes: 32)),
          seconds: 120,
          speedMps: 20,
          latitude: 30.0444 + 20_000 / _metresPerDegreeLat,
        ),
      ];

      final DailyMotionSummary summary = _classify(points);

      expect(summary.segments, hasLength(2));
      // The silence is not reported as driving time: 4 minutes recorded, not 34.
      expect(summary.vehicleDuration, const Duration(minutes: 4));
      // And the jump between the two halves is not counted as distance.
      expect(summary.vehicleDistanceKm, closeTo(4.8, 0.2));
    });

    test('an empty day is empty', () {
      expect(_classify(const <TrackPoint>[]).isEmpty, isTrue);
    });

    test('a single fix is not a segment', () {
      expect(
        _classify(_track(start: _morning, seconds: 0, speedMps: 20)).isEmpty,
        isTrue,
      );
    });

    test('out-of-range coordinates and untimed fixes are ignored', () {
      final List<TrackPoint> points = <TrackPoint>[
        ..._track(start: _morning, seconds: 60, speedMps: 20),
        TrackPoint(
          latitude: 999,
          longitude: 31.2357,
          timestamp: _day,
          speed: 20,
          accuracy: 5,
          detectedActivity: '',
        ),
        TrackPoint(
          latitude: 30.0444,
          longitude: 31.2357,
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
          speed: 20,
          accuracy: 5,
          detectedActivity: '',
        ),
      ];

      final DailyMotionSummary summary = _classify(points);

      expect(summary.segments, hasLength(1));
      expect(summary.segments.single.type, MotionType.vehicle);
    });

    test('out-of-order fixes are classified chronologically', () {
      final List<TrackPoint> points = _track(
        start: _morning,
        seconds: 300,
        speedMps: 20,
      ).reversed.toList();

      final DailyMotionSummary summary = _classify(points);

      expect(summary.segments, hasLength(1));
      expect(summary.segments.single.startTime, _morning);
      expect(summary.segments.single.endTime,
          _morning.add(const Duration(seconds: 300)));
    });
  });

  group('MotionClassifierService — thresholds are injectable', () {
    test('a raised vehicle threshold reclassifies a slow drive as a stopover',
        () {
      const MotionClassifierService service = MotionClassifierService(
        vehicleSpeedKmh: 60,
      );
      // 36 km/h: a drive by default, below this stricter instance's threshold.
      // With no measured steps the fix cannot be a walk, so it is a stopover.
      final DailyMotionSummary summary = _classify(
        _track(start: _morning, seconds: 300, speedMps: 10),
        service: service,
      );

      expect(summary.segments.single.type, MotionType.stationary);
      expect(summary.vehicleDistanceKm, 0);
    });

    test('a longer stopover threshold absorbs a five-minute stop', () {
      const MotionClassifierService service = MotionClassifierService(
        stopoverThreshold: Duration(minutes: 10),
      );
      final List<TrackPoint> points = <TrackPoint>[
        ..._track(start: _morning, seconds: 120, speedMps: 20),
        ..._parked(
          start: _morning.add(const Duration(seconds: 125)),
          seconds: 300,
          latitude: 30.0444 + (20 * 120) / _metresPerDegreeLat,
        ),
        ..._track(
          start: _morning.add(const Duration(seconds: 430)),
          seconds: 120,
          speedMps: 20,
          latitude: 30.0444 + (20 * 120) / _metresPerDegreeLat,
        ),
      ];

      final DailyMotionSummary summary = _classify(points, service: service);

      expect(summary.segments, hasLength(1));
      expect(summary.segments.single.type, MotionType.vehicle);
    });
  });
}
