import 'daily_gps_summary.dart';
import 'trip_segment.dart';

/// One day of classified motion: every [TripSegment] of that calendar day plus
/// the four counters the history header and Smart Insights read.
///
/// The *segments* are pure derived state — recomputed from the day's stored
/// track points on demand, never persisted — so adding them changes no Hive
/// schema. The counters are the same four numbers the tracker persists in
/// `DailyGpsSummary` (`walk_km`, `run_km`, `vehicle_km`, `step_count`); see
/// [DailyMotionSummary.fromRecord].
///
/// The counters are **not** a second opinion: walking and running distance is
/// `steps × stride`, vehicle distance is the GPS polyline of the drives, and the
/// classifier that produces the segments produces these numbers from the same
/// fixes. [DailyMotionSummary.classified] derives them from the segments so the
/// timeline and the header can never disagree; [DailyMotionSummary.fromRecord]
/// exists for a day whose track points are gone (a pruned or pre-classification
/// record), where the persisted counters are the only evidence left.
class DailyMotionSummary {
  const DailyMotionSummary({
    required this.date,
    required this.segments,
    this.walkingDistanceKm = 0,
    this.runningDistanceKm = 0,
    this.vehicleDistanceKm = 0,
    this.stepCount = 0,
    this.walkingDuration = Duration.zero,
    this.runningDuration = Duration.zero,
    this.vehicleDuration = Duration.zero,
    this.stopoverDuration = Duration.zero,
  });

  /// An empty day (nothing recorded, or a day whose points all failed the
  /// accuracy filter).
  factory DailyMotionSummary.empty(DateTime date) =>
      DailyMotionSummary(date: date, segments: const <TripSegment>[]);

  /// Rolls a classified day up into its four counters, so the header can never
  /// report a number the timeline does not contain.
  factory DailyMotionSummary.classified({
    required DateTime date,
    required List<TripSegment> segments,
  }) {
    double walking = 0;
    double running = 0;
    double vehicle = 0;
    int steps = 0;
    Duration walkingTime = Duration.zero;
    Duration runningTime = Duration.zero;
    Duration vehicleTime = Duration.zero;
    Duration stopoverTime = Duration.zero;
    for (final TripSegment segment in segments) {
      switch (segment.type) {
        case MotionType.walking:
          walking += segment.distanceKm;
          walkingTime += segment.duration;
          steps += segment.steps ?? 0;
        case MotionType.running:
          running += segment.distanceKm;
          runningTime += segment.duration;
          steps += segment.steps ?? 0;
        case MotionType.vehicle:
          vehicle += segment.distanceKm;
          vehicleTime += segment.duration;
        case MotionType.stationary:
          stopoverTime += segment.duration;
      }
    }
    return DailyMotionSummary(
      date: date,
      segments: segments,
      walkingDistanceKm: walking,
      runningDistanceKm: running,
      vehicleDistanceKm: vehicle,
      stepCount: steps,
      walkingDuration: walkingTime,
      runningDuration: runningTime,
      vehicleDuration: vehicleTime,
      stopoverDuration: stopoverTime,
    );
  }

  /// The day exactly as the tracker persisted it, for the case where its track
  /// points are no longer available.
  ///
  /// Counters come straight from the stored record, so nothing is re-derived
  /// from evidence that is gone. A record written before a field existed reads
  /// back as zero, which is the honest answer: that day measured nothing we can
  /// still show.
  factory DailyMotionSummary.fromRecord(DailyGpsSummary record) =>
      DailyMotionSummary(
        date: record.date,
        segments: const <TripSegment>[],
        walkingDistanceKm: record.walkKm,
        runningDistanceKm: record.runKm,
        vehicleDistanceKm: record.vehicleKm,
        stepCount: record.stepCount,
        walkingDuration: Duration(seconds: record.walkDurationSeconds),
        runningDuration: Duration(seconds: record.runDurationSeconds),
        vehicleDuration: Duration(seconds: record.vehicleDurationSeconds),
      );

  /// The calendar day this summary belongs to, normalised to local midnight.
  final DateTime date;

  /// Every classified segment of the day, in chronological order.
  final List<TripSegment> segments;

  /// Distance walked, in kilometres — `steps × 0.75 m` from the pedometer.
  final double walkingDistanceKm;

  /// Distance run, in kilometres — `steps × 0.95 m` from the pedometer.
  final double runningDistanceKm;

  /// Distance covered in a vehicle, in kilometres — the GPS polyline of the
  /// day's drives.
  final double vehicleDistanceKm;

  /// Steps the hardware counted today (0 when the device has no pedometer, or
  /// the day predates one).
  final int stepCount;

  /// Time spent walking.
  final Duration walkingDuration;

  /// Time spent running.
  final Duration runningDuration;

  /// Time spent in a vehicle.
  final Duration vehicleDuration;

  /// Time spent in a stopover (a stationary segment of 3 minutes or more — see
  /// `MotionClassifierService.stopoverThreshold`).
  final Duration stopoverDuration;

  /// Segments of one motion type, in chronological order.
  List<TripSegment> segmentsOf(MotionType type) => <TripSegment>[
        for (final TripSegment segment in segments)
          if (segment.type == type) segment,
      ];

  /// Total time covered by the day's segments.
  Duration get totalDuration =>
      walkingDuration + runningDuration + vehicleDuration + stopoverDuration;

  /// Total distance across every motion type, in kilometres.
  double get totalDistanceKm =>
      walkingDistanceKm + runningDistanceKm + vehicleDistanceKm;

  /// True when the day has no motion at all — no segments, no distance and no
  /// measured steps.
  bool get isEmpty =>
      segments.isEmpty && totalDistanceKm <= 0 && stepCount == 0;

  @override
  String toString() =>
      'DailyMotionSummary(${date.toIso8601String()}, ${segments.length} '
      'segments, ${totalDistanceKm.toStringAsFixed(2)} km, $stepCount steps)';
}
