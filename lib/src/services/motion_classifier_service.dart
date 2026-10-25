import '../core/utils/geo_distance.dart';
import '../data/models/daily_motion_summary.dart';
import '../data/models/track_point.dart';
import '../data/models/trip_segment.dart';

/// Turns one day's raw [TrackPoint]s into the classified [TripSegment]s the
/// Motion history screen renders.
///
/// The pipeline is the classic three stages — filter, label, merge — and it is
/// deliberately **pure**: no clock, no platform channel, no storage, no
/// network. Feed it points and it returns segments; that is the whole contract,
/// which is what makes every threshold below directly testable
/// (`test/motion_classifier_service_test.dart`).
///
/// ```
/// TrackPoint[] → drop unusable → split at GPS holes → label each fix
///             → group → absorb short groups → merge neighbours → TripSegment[]
/// ```
///
/// ## Hybrid labelling: steps decide on foot, GPS decides in a vehicle
///
/// Walking and running are physical facts the hardware counts, not speeds the
/// GPS infers. Every fix therefore carries the steps taken since the previous
/// one (see `TrackPoint.steps`), and the label comes from that evidence first:
///
/// | steps measured | label                                              |
/// | -------------- | -------------------------------------------------- |
/// | `> 0`          | **running** at ≥ [runCadencePerMinute], else **walking** |
/// | `0` or `null`  | **vehicle** above [vehicleSpeedKmh], else **stationary** |
///
/// There is deliberately no speed band for feet. A GPS receiver cannot tell a
/// brisk walk from a traffic crawl, so a speed-only "walking" reading was always
/// a guess — and one that inflated a distance the pedometer never measured. Now
/// a fix is only ever on foot when the pedometer counted steps for it, and the
/// vehicle's distance is the GPS polyline it actually covered. A day recorded
/// without a pedometer (or by a build without one) therefore reports no walking;
/// `0` steps is an honest "not measured" rather than a fabricated gait.
///
/// Cadence is computed from the persisted per-fix step increments over a
/// trailing [cadenceWindow] (widened to at least one fix interval, so a
/// low-power 60 s cadence still measures a rate). It lives here, not in the
/// step meter, so it is recomputable from stored data and directly testable.
///
/// ## Thresholds
///
/// * **Stationary** — no steps and not vehicle speed, staying within
///   [stationaryRadiusMeters] of the group's first fix.
/// * **Vehicle** — above [vehicleSpeedKmh] with no step counted. A car's
///   vibration can occasionally nudge the pedometer, so a short step-bearing
///   stretch is absorbed into the surrounding drive ([minMovingSegment])
///   instead of splitting it.
/// * **Walking** — measured steps below the running cadence.
/// * **Running** — measured steps at or above [runCadencePerMinute].
/// * **Stopover** — a stationary group lasting at least [stopoverThreshold]
///   (3 minutes). Anything shorter is absorbed into a neighbour, so a red light
///   never becomes a fake stop and the route line stays continuous.
/// * **Moving blip** — a vehicle/walking group shorter than
///   [minMovingSegment] is folded into a neighbour too: creeping forward at
///   10 km/h for 20 seconds must not split one drive into three cards.
///
/// A hole longer than [maxGap] ends a segment instead of being averaged across:
/// an app that was killed for an hour must not report an hour-long drive.
class MotionClassifierService {
  const MotionClassifierService({
    this.maxAccuracyMeters = 35,
    this.vehicleSpeedKmh = 15,
    this.stopoverThreshold = const Duration(minutes: 3),
    this.minMovingSegment = const Duration(minutes: 1),
    this.stationaryRadiusMeters = 60,
    this.maxGap = const Duration(minutes: 10),
    this.minStepMeters = 3,
  });

  /// Fixes whose reported horizontal accuracy is worse than this are ignored.
  /// `0` means "not reported" and is accepted, so legacy points still classify.
  final double maxAccuracyMeters;

  /// Above this speed a fix without measured steps counts as a vehicle. With
  /// measured steps the count, not this threshold, decides.
  final double vehicleSpeedKmh;

  /// Minimum stationary duration that becomes an explicit stopover card.
  final Duration stopoverThreshold;

  /// Minimum duration of a vehicle/walking/running stretch; shorter ones are
  /// absorbed.
  final Duration minMovingSegment;

  /// How far a fix may stray from a stopover's first point and still belong to
  /// it. Guards against two separate stops being welded together by a
  /// stationary *speed* reading while the position actually moved.
  final double stationaryRadiusMeters;

  /// Longer silence than this breaks the day into separate segments: with no
  /// fixes in between, the elapsed time is not evidence of travel.
  final Duration maxGap;

  /// Fix-to-fix steps shorter than this are GPS jitter and add no distance
  /// (the same rule the trackers use to accumulate `total_km`).
  final int minStepMeters;

  /// Speeds above this (km/h) are receiver glitches, never travel.
  static const double maxPlausibleSpeedKmh = 180;

  /// Steps per minute at or above which a walk becomes a run.
  ///
  /// A brisk walk sits around 100–120 steps/min; a jog starts near 130. The
  /// threshold is deliberately at the top of the walking band so a fast walk is
  /// never labelled a run.
  static const double runCadencePerMinute = 120;

  /// The trailing window the cadence is averaged over. It is widened to at
  /// least one fix interval, so a 60 s low-power cadence still measures a rate
  /// instead of reporting "unknown".
  static const Duration cadenceWindow = Duration(seconds: 20);

  /// Classifies [points] for the calendar day [date].
  ///
  /// Never throws: unusable input degrades to
  /// [DailyMotionSummary.empty] — a day with no evidence is shown as empty,
  /// never invented.
  DailyMotionSummary classify({
    required DateTime date,
    required List<TrackPoint> points,
  }) {
    final List<TrackPoint> usable = _usableSorted(points);
    if (usable.length < 2) return DailyMotionSummary.empty(date);

    final List<_Draft> drafts = <_Draft>[];
    for (final List<TrackPoint> run in _runs(usable)) {
      if (run.length < 2) continue;
      drafts.addAll(_labelRun(run));
    }
    if (drafts.isEmpty) return DailyMotionSummary.empty(date);

    _absorbShortGroups(drafts);
    final List<_Draft> merged = _mergeNeighbours(drafts);

    final List<TripSegment> segments = <TripSegment>[
      for (final _Draft draft in merged)
        if (draft.duration >= stopoverThreshold || draft.type != MotionType.stationary)
          _segmentOf(draft),
    ];
    return DailyMotionSummary.classified(date: date, segments: segments);
  }

  // -------------------------------------------------------------------------
  // Stage 1 — filter
  // -------------------------------------------------------------------------

  /// Drops malformed, redundant and untrustworthy fixes, then orders what is
  /// left chronologically.
  List<TrackPoint> _usableSorted(List<TrackPoint> points) {
    final List<TrackPoint> clean = <TrackPoint>[
      for (final TrackPoint point in points)
        if (_isUsable(point)) point,
    ];
    clean.sort(
      (TrackPoint a, TrackPoint b) => a.timestamp.compareTo(b.timestamp),
    );
    // Drop same-instant duplicates: a repeated persisted fix would otherwise
    // occupy zero time and corrupt the speed derivation.
    final List<TrackPoint> unique = <TrackPoint>[];
    for (final TrackPoint point in clean) {
      if (unique.isNotEmpty &&
          unique.last.timestamp == point.timestamp) {
        continue;
      }
      unique.add(point);
    }
    return unique;
  }

  bool _isUsable(TrackPoint point) {
    final double accuracy = point.accuracy;
    if (accuracy > 0 && accuracy > maxAccuracyMeters) return false;
    // A point without a real timestamp cannot be placed on the timeline, so it
    // cannot be classified (legacy route vertices may lack one).
    if (point.timestamp.millisecondsSinceEpoch <= 0) return false;
    return point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude >= -90 &&
        point.latitude <= 90 &&
        point.longitude >= -180 &&
        point.longitude <= 180;
  }

  /// Splits the day wherever the fix stream went quiet for longer than
  /// [maxGap] (or the clock went backwards).
  List<List<TrackPoint>> _runs(List<TrackPoint> points) {
    final List<List<TrackPoint>> runs = <List<TrackPoint>>[];
    List<TrackPoint> current = <TrackPoint>[points.first];
    for (int i = 1; i < points.length; i++) {
      final Duration gap = points[i].timestamp.difference(
        points[i - 1].timestamp,
      );
      if (gap > maxGap || gap.isNegative) {
        runs.add(current);
        current = <TrackPoint>[points[i]];
      } else {
        current.add(points[i]);
      }
    }
    runs.add(current);
    return runs;
  }

  // -------------------------------------------------------------------------
  // Stage 2 — label
  // -------------------------------------------------------------------------

  /// Groups one uninterrupted run into consecutive same-motion stretches.
  List<_Draft> _labelRun(List<TrackPoint> run) {
    final List<double> speeds = _speedsOf(run);
    final List<double?> cadences = _cadencesOf(run);

    final List<_Draft> drafts = <_Draft>[];
    _Draft? current;
    for (int i = 0; i < run.length; i++) {
      final MotionType label = _labelOf(
        speedKmh: speeds[i],
        steps: run[i].steps,
        cadencePerMinute: cadences[i],
      );
      // A stopover is one *place*: a stationary reading that has drifted away
      // from where the group started ends the stop rather than extending it.
      final bool drifted = label == MotionType.stationary &&
          current != null &&
          current.type == MotionType.stationary &&
          _metres(current.first, run[i]) > stationaryRadiusMeters;
      if (current == null || current.type != label || drifted) {
        current = _Draft(label);
        drafts.add(current);
      }
      current.add(run[i]);
    }
    return drafts;
  }

  /// Per-fix speed in km/h: the receiver's Doppler report when it exists,
  /// otherwise the distance/time step to the previous fix (which is what a
  /// legacy, speed-less route still carries).
  ///
  /// A reported `0` is a *measurement* — parked — and must not be replaced by a
  /// derived speed, or GPS jitter would read as 30 km/h. That distinction is
  /// what [TrackPoint.hasSpeed] records.
  List<double> _speedsOf(List<TrackPoint> run) {
    final List<double> speeds = List<double>.filled(run.length, 0);
    for (int i = 0; i < run.length; i++) {
      final TrackPoint point = run[i];
      if (point.hasSpeed) {
        final double kmh = point.speed * 3.6;
        speeds[i] = kmh <= maxPlausibleSpeedKmh ? kmh : 0;
        continue;
      }
      if (i == 0) continue;
      final int milliseconds =
          point.timestamp.difference(run[i - 1].timestamp).inMilliseconds;
      if (milliseconds <= 0) continue;
      final double metres = _metres(run[i - 1], point);
      final double kmh = (metres / milliseconds) * 3600;
      speeds[i] = kmh <= maxPlausibleSpeedKmh ? kmh : maxPlausibleSpeedKmh;
    }
    return speeds;
  }

  /// Trailing step cadence, in steps per minute, for every fix of [run].
  ///
  /// The window is [cadenceWindow] but never shorter than one fix interval, so
  /// a 60 s low-power cadence still produces a rate. Entries are `null` when
  /// the fix carries no step measurement, or when there is no elapsed time to
  /// divide by (the first fix of a run).
  List<double?> _cadencesOf(List<TrackPoint> run) {
    final List<double?> cadences = List<double?>.filled(run.length, null);
    for (int i = 1; i < run.length; i++) {
      if (run[i].steps == null) continue;
      // Walk backwards while inside the window, but always include the
      // previous fix so a sparse stream still yields a rate.
      int start = i - 1;
      while (start > 0 &&
          run[i].timestamp.difference(run[start - 1].timestamp) <=
              cadenceWindow) {
        start -= 1;
      }
      final int milliseconds = run[i].timestamp
          .difference(run[start].timestamp)
          .inMilliseconds;
      if (milliseconds <= 0) continue;
      // Steps of indices start+1…i are exactly the increments counted between
      // the window's first fix and the current one.
      int steps = 0;
      bool measured = false;
      for (int j = start + 1; j <= i; j++) {
        final int? increment = run[j].steps;
        if (increment == null) continue;
        steps += increment;
        measured = true;
      }
      if (!measured) continue;
      cadences[i] = steps / (milliseconds / Duration.millisecondsPerMinute);
    }
    return cadences;
  }

  /// The verdict for one fix, in priority order:
  ///
  /// 1. **Measured steps.** A fix the pedometer counted steps for is on foot —
  ///    running when the trailing cadence reached [runCadencePerMinute],
  ///    otherwise walking. This outranks speed on purpose: the count is a
  ///    measurement, whereas a walking-range Doppler reading is what a car in
  ///    traffic and a GPS glitch also produce.
  /// 2. **No steps.** Nothing was counted for the fix, so the phone was either
  ///    riding or standing still; only speed above [vehicleSpeedKmh] can make
  ///    that a vehicle.
  ///
  /// A `null` count (no pedometer, denied permission, or a record written
  /// before steps were stored) behaves exactly like a measured zero: the day
  /// reports no walking rather than inventing a gait from velocity.
  MotionType _labelOf({
    required double speedKmh,
    required int? steps,
    required double? cadencePerMinute,
  }) {
    final int? counted = steps;
    if (counted != null && counted > 0) {
      final double cadence = cadencePerMinute ?? 0;
      return cadence >= runCadencePerMinute
          ? MotionType.running
          : MotionType.walking;
    }
    return speedKmh > vehicleSpeedKmh
        ? MotionType.vehicle
        : MotionType.stationary;
  }


  // -------------------------------------------------------------------------
  // Stage 3 — merge
  // -------------------------------------------------------------------------

  /// Folds groups shorter than their type's minimum into a neighbour.
  ///
  /// Preference order — same type, then the earlier neighbour, then the later
  /// one — keeps the route line continuous: a 40-second red light inside a
  /// drive disappears into that drive instead of becoming its own card, and a
  /// 20-second crawl at walking speed does not split the drive in three.
  void _absorbShortGroups(List<_Draft> drafts) {
    bool changed = true;
    while (changed && drafts.length > 1) {
      changed = false;
      for (int i = 0; i < drafts.length; i++) {
        final _Draft draft = drafts[i];
        final Duration minimum = draft.type == MotionType.stationary
            ? stopoverThreshold
            : minMovingSegment;
        if (draft.duration >= minimum) continue;

        int target = i - 1;
        if (i > 0 && drafts[i - 1].type == draft.type) {
          target = i - 1;
        } else if (i + 1 < drafts.length &&
            drafts[i + 1].type == draft.type) {
          target = i + 1;
        } else if (i == 0) {
          target = 1;
        }
        drafts[target].absorb(draft);
        drafts.removeAt(i);
        changed = true;
        break;
      }
    }
  }

  /// Joins neighbouring groups of the same motion type — the last step of
  /// segmentation, so one drive that briefly wobbled between two labels is
  /// still one card.
  ///
  /// Groups separated by more than [maxGap] are never joined: there is no
  /// evidence the vehicle kept moving while the fixes were silent, and a
  /// merged segment would report a duration nobody measured.
  List<_Draft> _mergeNeighbours(List<_Draft> drafts) {
    final List<_Draft> merged = <_Draft>[];
    for (final _Draft draft in drafts) {
      if (merged.isNotEmpty &&
          merged.last.type == draft.type &&
          _joinedGap(merged.last, draft) <= maxGap) {
        merged.last.absorb(draft);
      } else {
        merged.add(draft);
      }
    }
    return merged;
  }

  Duration _joinedGap(_Draft left, _Draft right) {
    final DateTime leftEnd = left.last.timestamp;
    final DateTime rightStart = right.first.timestamp;
    return rightStart.difference(leftEnd).abs();
  }

  // -------------------------------------------------------------------------
  // Output
  // -------------------------------------------------------------------------

  TripSegment _segmentOf(_Draft draft) {
    final List<TrackPoint> points = draft.points;
    final DateTime start = points.first.timestamp;
    final DateTime end = points.last.timestamp;
    final Duration duration = end.difference(start);

    // A stopover covers no ground by definition: GPS drift while parked must
    // not be reported as distance travelled. Its step count is deliberately
    // dropped too — a couple of phantom steps while parked is not a walk.
    if (draft.type == MotionType.stationary) {
      return TripSegment(
        type: draft.type,
        startTime: start,
        endTime: end,
        distanceInMeters: 0,
        averageSpeedKmH: 0,
        points: points,
      );
    }

    double metres = 0;
    for (int i = 1; i < points.length; i++) {
      final Duration gap = points[i].timestamp.difference(
        points[i - 1].timestamp,
      );
      if (gap > maxGap) continue;
      final double step = _metres(points[i - 1], points[i]);
      if (step >= minStepMeters) metres += step;
    }

    final int? steps = _stepTotalOf(points);
    // A walk or run *is* its step count: `steps × stride` is a physical
    // measurement, whereas a GPS polyline on foot is mostly noise. The label
    // only reaches here with measured steps, so the polyline above is a
    // defensive fallback for a draft that absorbed a step-less neighbour.
    if ((draft.type == MotionType.walking || draft.type == MotionType.running) &&
        steps != null &&
        steps > 0) {
      metres = steps *
          (draft.type == MotionType.running
              ? TripSegment.runningStrideMeters
              : TripSegment.walkingStrideMeters);
    }

    final double hours =
        duration.inMilliseconds / Duration.millisecondsPerHour;
    return TripSegment(
      type: draft.type,
      startTime: start,
      endTime: end,
      distanceInMeters: metres,
      averageSpeedKmH: hours > 0 ? (metres / 1000) / hours : 0,
      points: points,
      steps: steps,
    );
  }

  /// Steps measured across [points], or `null` when none of them carries a
  /// measurement (a record from before the pedometer existed).
  static int? _stepTotalOf(List<TrackPoint> points) {
    int? total;
    for (final TrackPoint point in points) {
      final int? steps = point.steps;
      if (steps == null) continue;
      total = (total ?? 0) + steps;
    }
    return total;
  }

  /// Great-circle distance between two fixes, in metres.
  static double _metres(TrackPoint a, TrackPoint b) =>
      haversineKm(a.latitude, a.longitude, b.latitude, b.longitude) * 1000;
}

/// A mutable run of fixes that share a motion type, before it becomes an
/// immutable [TripSegment].
class _Draft {
  _Draft(this.type);

  final MotionType type;
  final List<TrackPoint> points = <TrackPoint>[];

  TrackPoint get first => points.first;

  TrackPoint get last => points.last;

  Duration get duration => last.timestamp.difference(first.timestamp);

  void add(TrackPoint point) => points.add(point);

  /// Takes over [other]'s fixes, keeping chronological order.
  void absorb(_Draft other) {
    points.addAll(other.points);
    points.sort(
      (TrackPoint a, TrackPoint b) => a.timestamp.compareTo(b.timestamp),
    );
  }
}
