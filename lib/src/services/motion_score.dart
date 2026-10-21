import '../features/motion_analytics/domain/entities/motion_event.dart';
import 'motion_profiler.dart';

/// Where a trip's driving score sits on the quality ladder.
enum MotionScoreBand {
  /// A calm trip: almost no harsh input for the distance covered.
  excellent,

  /// Moderately smooth: the odd maneuver, nothing alarming.
  good,

  /// Rough: several harsh maneuvers, or a high rate for the distance.
  fair,

  /// Punishing: maneuver-rich driving over a short distance.
  poor,
}

/// The current trip's driving score and per-kind maneuver tallies.
///
/// A **presentation-only** summary computed from the location-free
/// [DrivingEvent] log. It carries no coordinates, no identity and nothing that
/// could describe where a maneuver happened — the same discipline the events
/// themselves follow (AGENT_SKILLS.md §5).
class MotionScore {
  const MotionScore({
    required this.score,
    required this.band,
    required this.total,
    required this.tallies,
  });

  /// 0–100, higher is smoother. Starts at 100 and is debited per maneuver.
  final int score;

  /// Which [MotionScoreBand] [score] falls in.
  final MotionScoreBand band;

  /// How many maneuvers the trip recorded.
  final int total;

  /// Maneuvers by kind. Every [DrivingEventType] maps to a count (possibly 0)
  /// so the summary sheet can render a stable row per kind.
  final Map<DrivingEventType, int> tallies;

  /// A trip with no maneuvers at all.
  static const MotionScore empty = MotionScore(
    score: 100,
    band: MotionScoreBand.excellent,
    total: 0,
    tallies: <DrivingEventType, int>{},
  );

  /// Whether any maneuver was recorded.
  bool get isClean => total == 0;

  /// Debited per maneuver, by how much it says about the driving.
  ///
  /// Braking and potholes cost more than a turn: a turn is a fact of the road,
  /// while a hard brake is usually a reaction to speed carried into a hazard.
  /// A pothole is not the driver's fault, but it *is* a road-surface hazard
  /// worth surfacing, so it is priced with the road, not the driver.
  static const int _brakingCost = 6;
  static const int _accelerationCost = 5;
  static const int _potholeCost = 4;
  static const int _turnCost = 3;
  static const int _bumpCost = 2;

  /// A short trip cannot absorb many maneuvers before its *rate* is alarming,
  /// so the debit is scaled by how far the maneuver count sits above what this
  /// distance could reasonably contain.
  static const double _freeEventsPerKm = 1.5;

  /// Never return 0: a score of zero reads as "broken", and even a dreadful
  /// trip deserves a floor to improve from.
  static const int _floor = 5;

  /// Scores a trip's maneuvers over its recorded distance.
  ///
  /// [distanceKm] softens the debit for long trips: the same event count over a
  /// long drive is far less significant than over a short one. A non-finite or
  /// negative distance is treated as zero (the strictest case).
  static MotionScore from(
    List<DrivingEvent> events, {
    required double distanceKm,
  }) {
    final Map<DrivingEventType, int> tallies = <DrivingEventType, int>{
      for (final DrivingEventType type in DrivingEventType.values) type: 0,
    };
    double rawDebit = 0;
    for (final DrivingEvent event in events) {
      tallies[event.type] = (tallies[event.type] ?? 0) + 1;
      rawDebit += _costOf(event.type);
    }

    final int total = events.length;
    if (total == 0) {
      return MotionScore(
        score: 100,
        band: MotionScoreBand.excellent,
        total: 0,
        tallies: tallies,
      );
    }

    // Distance absorbs maneuvers: the first `distanceKm * freeEventsPerKm`
    // events are the baseline noise of that distance, and only the excess is
    // charged in full. Half credit for the baseline keeps a long trip from
    // scoring identically to a parked one.
    final double safeKm = distanceKm.isFinite && distanceKm > 0
        ? distanceKm
        : 0;
    final double allowance = safeKm * _freeEventsPerKm;
    final double baseline = allowance < total ? allowance : total.toDouble();
    final double excess = total - baseline;
    final double charged = baseline * 0.5 + excess;

    // Scale the per-event cost by what fraction of the count was charged, so a
    // 40 km drive with 4 events is not punished like 4 events in 200 m.
    final double effectiveDebit = total == 0
        ? 0
        : rawDebit * (charged / total);

    final int score = (100 - effectiveDebit).round().clamp(_floor, 100);
    return MotionScore(
      score: score,
      band: _bandOf(score),
      total: total,
      tallies: tallies,
    );
  }

  /// The same score computed from the on-device [MotionEvent] taxonomy, for
  /// callers that have not been mapped into [DrivingEvent] yet.
  static MotionScore fromMotionEvents(
    List<MotionEvent> events, {
    required double distanceKm,
  }) {
    // `smoothDrive` is a driving state, not a maneuver, and is never tallied.
    final List<DrivingEvent> mapped = <DrivingEvent>[
      for (final MotionEvent event in events)
        if (event.kind != MotionEventKind.smoothDrive)
          DrivingEvent(
            type: _drivingTypeOf(event.kind),
            peakMps2: event.peakMps2,
            startedAt: event.startedAt,
            duration: Duration.zero,
          ),
    ];
    return from(mapped, distanceKm: distanceKm);
  }

  static DrivingEventType _drivingTypeOf(MotionEventKind kind) =>
      switch (kind) {
        MotionEventKind.hardBrake => DrivingEventType.harshBraking,
        MotionEventKind.hardAccel => DrivingEventType.harshAcceleration,
        MotionEventKind.sharpTurn => DrivingEventType.sharpTurn,
        MotionEventKind.speedBump => DrivingEventType.speedBump,
        MotionEventKind.pothole => DrivingEventType.pothole,
        MotionEventKind.smoothDrive => DrivingEventType.harshAcceleration,
      };

  static double _costOf(DrivingEventType type) => switch (type) {
    DrivingEventType.harshBraking => _brakingCost.toDouble(),
    DrivingEventType.harshAcceleration => _accelerationCost.toDouble(),
    DrivingEventType.pothole => _potholeCost.toDouble(),
    DrivingEventType.sharpTurn => _turnCost.toDouble(),
    DrivingEventType.speedBump => _bumpCost.toDouble(),
  };

  static MotionScoreBand _bandOf(int score) {
    if (score >= 85) return MotionScoreBand.excellent;
    if (score >= 70) return MotionScoreBand.good;
    if (score >= 50) return MotionScoreBand.fair;
    return MotionScoreBand.poor;
  }

  @override
  bool operator ==(Object other) =>
      other is MotionScore &&
      other.score == score &&
      other.total == total &&
      other.band == band;

  @override
  int get hashCode => Object.hash(score, total, band);
}
