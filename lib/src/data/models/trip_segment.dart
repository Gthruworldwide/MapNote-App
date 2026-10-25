import 'track_point.dart';

/// How a [TripSegment] was travelled, as classified by
/// `MotionClassifierService`.
///
/// The enum is the single vocabulary shared by the timeline cards, the map's
/// palette (`AppColors.motionDrive` / `motionWalk` / `motionRun` /
/// `motionStop` via `MotionTypePresentation`) and the quick-stats bar, so a
/// segment can never render as "vehicle" in one surface and "walking" in
/// another.
enum MotionType {
  /// In a road vehicle: GPS speed above `MotionClassifierService.vehicleSpeedKmh`
  /// with **no** step counted for the fix. A vehicle has no stride, so its
  /// distance is the GPS polyline it actually covered.
  vehicle,

  /// On foot at a walking cadence: the hardware pedometer counted steps for the
  /// fix and the trailing cadence is below
  /// `MotionClassifierService.runCadencePerMinute`.
  walking,

  /// On foot at a running cadence: the pedometer counted steps and the trailing
  /// cadence reached `MotionClassifierService.runCadencePerMinute`.
  running,

  /// A stopover: no steps counted and not vehicle speed, staying inside
  /// `MotionClassifierService.stationaryRadiusMeters` for at least
  /// `MotionClassifierService.stopoverThreshold`.
  stationary,
}

/// One classified stretch of the day: a drive, a walk, a run or a stopover.
///
/// Derived state only — segments are recomputed from the day's stored
/// [TrackPoint]s on demand and never persisted, so this type adds no Hive
/// schema. Everything it exposes is geometry, a duration, a motion kind and a
/// step count: no place names beyond a reverse-geocoded stopover label, and no
/// identity (AGENT_SKILLS.md §5).
class TripSegment {
  const TripSegment({
    required this.type,
    required this.startTime,
    required this.endTime,
    required this.distanceInMeters,
    required this.averageSpeedKmH,
    required this.points,
    this.stopoverName,
    this.steps,
  });

  /// How this stretch was travelled.
  final MotionType type;

  /// Timestamp of the segment's first point.
  final DateTime startTime;

  /// Timestamp of the segment's last point.
  final DateTime endTime;

  /// Distance covered inside the segment, in metres.
  ///
  /// A walk or run measured by the pedometer reports its step-derived distance
  /// ([walkingStrideMeters] / [runningStrideMeters] per step); every other
  /// segment reports the haversine polyline length (jitter below
  /// `MotionClassifierService.minStepMeters` ignored).
  final double distanceInMeters;

  /// Distance divided by elapsed time, in km/h. Zero for a stopover.
  final double averageSpeedKmH;

  /// The segment's own points, in chronological order. Stopover segments keep
  /// every point so the map can pin the place, and moving segments keep the
  /// full polyline.
  final List<TrackPoint> points;

  /// Reverse-geocoded name of a stopover, when one has been resolved. Always
  /// `null` for moving segments.
  final String? stopoverName;

  /// Steps counted by the hardware pedometer during this segment, or `null`
  /// when the device has no step sensor (or the record predates it).
  ///
  /// A walking or running segment always carries a measurement: steps are the
  /// only thing that can label a fix on foot. Vehicle and stopover segments
  /// carry `null` — they cover no ground on foot.
  final int? steps;

  /// Elapsed time from [startTime] to [endTime].
  Duration get duration => endTime.difference(startTime);

  /// Distance in kilometres, for display.
  double get distanceKm => distanceInMeters / 1000;

  /// Mean adult walking stride — the conversion the pedometer distance uses.
  static const double walkingStrideMeters = 0.75;

  /// Mean adult running stride — longer than a walking step, which is why the
  /// same step count covers more ground at a run.
  static const double runningStrideMeters = 0.95;

  /// A copy carrying a resolved stopover name (see `MilestoneNameResolver`).
  TripSegment withStopoverName(String? name) => TripSegment(
        type: type,
        startTime: startTime,
        endTime: endTime,
        distanceInMeters: distanceInMeters,
        averageSpeedKmH: averageSpeedKmH,
        points: points,
        stopoverName: name ?? stopoverName,
        steps: steps,
      );

  @override
  bool operator ==(Object other) =>
      other is TripSegment &&
      other.type == type &&
      other.startTime == startTime &&
      other.endTime == endTime &&
      other.distanceInMeters == distanceInMeters &&
      other.averageSpeedKmH == averageSpeedKmH &&
      other.stopoverName == stopoverName &&
      other.steps == steps &&
      other.points.length == points.length;

  @override
  int get hashCode => Object.hash(
        type,
        startTime,
        endTime,
        distanceInMeters,
        averageSpeedKmH,
        stopoverName,
        steps,
        points.length,
      );

  @override
  String toString() =>
      'TripSegment(${type.name}, ${startTime.toIso8601String()} → '
      '${endTime.toIso8601String()}, ${distanceKm.toStringAsFixed(2)} km, '
      '${steps ?? '—'} steps)';
}
