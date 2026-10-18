import 'dart:math' as math;

/// Verdict on one GPS gap: the straight-line displacement between the last
/// accepted fix (point A) and the first accepted fix after an outage
/// (point B), the average speed that displacement implies over the gap, and
/// therefore how much of it may be appended to the day's total distance.
class GapVerdict {
  const GapVerdict({
    required this.crossingKm,
    required this.impliedSpeedKmh,
    required this.recoveredKm,
    this.crossingBearingDegrees,
  });

  /// Straight-line A→B distance in km (Haversine). Never negative.
  final double crossingKm;

  /// Average speed the crossing implies: `crossingKm / gapHours`, or `null`
  /// when the gap is not positive (there is no elapsed time to divide by).
  final double? impliedSpeedKmh;

  /// The distance appended to today's total: [crossingKm] when the implied
  /// speed is plausible travel, `0` when the gap is too short or too fast to
  /// be trusted (teleports, clock jumps, implausible fixes).
  final double recoveredKm;

  /// Initial bearing from A to B in degrees (0 = north, clockwise), or `null`
  /// when not computed. This is the displacement *direction*, kept for
  /// diagnostics and future heading-aware consumers.
  final double? crossingBearingDegrees;

  /// Whether any distance was recovered.
  bool get recovered => recoveredKm > 0;
}

/// Decides whether skipped GPS distance — measured across an *explicitly
/// observed* outage (GPS switched off, provider error, direct call) — is
/// plausible travel and may be appended to the day's total.
///
/// This service is pure arithmetic: [DailyTrackEngine] owns the outage flag,
/// the last-accepted-fix bookkeeping and the `todayDistance` accumulator, and
/// calls [judge] / [judgeFix] to make the recovery decision. Keeping the rule
/// here makes it unit-testable without a stream, a store or a platform
/// channel, and keeps both trackers (GPS + AutoMotion) on one implementation.
///
/// The rule, in one sentence: **recover the A→B crossing only when the average
/// speed it implies over the gap is at most [maxPlausibleSpeedKmh]** — a
/// 45-minute gap may legitimately span 30 km, but never 300 km, and a
/// 1-second GPS reacquisition may only have moved tens of metres.
///
/// Note this service deliberately arms nothing: a *silent* gap (no outage
/// observed, fixes just stopped arriving) is judged by the engine's ordinary
/// bridging rules instead — silence alone is not evidence of travel.
class GapRecoveryService {
  const GapRecoveryService({this.maxPlausibleSpeedKmh = 160});

  /// Highest average speed a gap crossing may imply and still be appended,
  /// in km/h: motorway travel plus margin. Anything faster is treated as a
  /// teleport (clock jump, spurious fix, imported position) and recovered as
  /// zero — the gap is *not* bridged.
  final double maxPlausibleSpeedKmh;

  /// Judges a gap from its elapsed time and pre-measured A→B crossing
  /// distance. The caller (the track engine) has already measured the
  /// crossing; this decides whether it is plausible travel.
  GapVerdict judge({
    required Duration gap,
    required double crossingKm,
  }) {
    if (gap <= Duration.zero) {
      return GapVerdict(crossingKm: crossingKm, impliedSpeedKmh: null, recoveredKm: 0);
    }
    final double crossing = math.max(0, crossingKm);
    final double gapHours = gap.inMicroseconds / Duration.microsecondsPerHour;
    final double impliedSpeedKmh = crossing / gapHours;
    final bool plausible = impliedSpeedKmh <= maxPlausibleSpeedKmh;
    return GapVerdict(
      crossingKm: crossing,
      impliedSpeedKmh: impliedSpeedKmh,
      recoveredKm: plausible ? crossing : 0,
    );
  }

  /// Convenience overload that measures the gap itself from the two fixes:
  /// Haversine distance, implied average speed, and the initial bearing
  /// (displacement direction) A→B.
  GapVerdict judgeFix({
    required DateTime lastFixAt,
    required double lastLatitude,
    required double lastLongitude,
    required DateTime resumedAt,
    required double resumedLatitude,
    required double resumedLongitude,
  }) {
    final double crossingKm = haversineKm(
      lastLatitude,
      lastLongitude,
      resumedLatitude,
      resumedLongitude,
    );
    final GapVerdict verdict = judge(
      gap: resumedAt.difference(lastFixAt),
      crossingKm: crossingKm,
    );
    return GapVerdict(
      crossingKm: verdict.crossingKm,
      impliedSpeedKmh: verdict.impliedSpeedKmh,
      recoveredKm: verdict.recoveredKm,
      crossingBearingDegrees: initialBearingDegrees(
        lastLatitude,
        lastLongitude,
        resumedLatitude,
        resumedLongitude,
      ),
    );
  }

  /// Great-circle distance between two WGS-84 points, in kilometres
  /// (Haversine; Earth radius 6371.0088 km — the mean radius, same constant
  /// the trackers' shared [DailyTrackEngine.distanceKmBetween] uses).
  static double haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadiusKm = 6371.0088;
    const double degreesToRadians = math.pi / 180;
    final double phi1 = lat1 * degreesToRadians;
    final double phi2 = lat2 * degreesToRadians;
    final double deltaPhi = (lat2 - lat1) * degreesToRadians;
    final double deltaLambda = (lon2 - lon1) * degreesToRadians;
    final double a = math.sin(deltaPhi / 2) * math.sin(deltaPhi / 2) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.sin(deltaLambda / 2) *
            math.sin(deltaLambda / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Initial bearing from A to B in degrees clockwise from true north
  /// (0° = north, 90° = east). Standard spherical initial bearing formula.
  static double initialBearingDegrees(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double degreesToRadians = math.pi / 180;
    const double radiansToDegrees = 180 / math.pi;
    final double phi1 = lat1 * degreesToRadians;
    final double phi2 = lat2 * degreesToRadians;
    final double deltaLambda = (lon2 - lon1) * degreesToRadians;
    final double y = math.sin(deltaLambda) * math.cos(phi2);
    final double x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);
    final double bearingRadians = math.atan2(y, x);
    final double bearingDegrees = bearingRadians * radiansToDegrees;
    return (bearingDegrees + 360) % 360;
  }
}
