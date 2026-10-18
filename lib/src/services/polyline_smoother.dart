import 'dart:math' as math;

/// One vertex of a recorded route: WGS-84 coordinates plus the optional time
/// the fix was taken.
///
/// Deliberately not geolocator's `Position`: the smoother is pure geometry —
/// it never needs accuracy, speed or platform fields, and keeping its own
/// vertex type makes the filter trivially unit-testable and reusable for
/// anything that records a lat/lon trace.
class RoutePoint {
  const RoutePoint({
    required this.latitude,
    required this.longitude,
    this.at,
  });

  /// WGS-84 latitude in degrees.
  final double latitude;

  /// WGS-84 longitude in degrees.
  final double longitude;

  /// When this fix was taken, when known. Timestamps drive the filter's
  /// prediction step (see [PolylineSmoother.smooth]); a vertex without one is
  /// spaced by [PolylineSmoother.assumedInterval].
  final DateTime? at;

  @override
  bool operator ==(Object other) =>
      other is RoutePoint &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.at == at;

  @override
  int get hashCode => Object.hash(latitude, longitude, at);
}

/// GPS-jitter smoother for recorded routes: runs the fix sequence through a
/// per-axis Kalman filter (constant-velocity model, white-noise acceleration)
/// in a local tangent plane and returns a polyline with the jitter removed.
///
/// Raw GPS traces oscillate around the true path by several metres even while
/// the device stands still, so a stored route drawn straight from the fixes
/// looks hairy and its length is inflated. The filter here treats each fix as
/// a *noisy measurement* of the vehicle's true position: the constant-velocity
/// prediction follows genuine motion, while the measurement update pulls the
/// estimate back toward every new fix, attenuating the noise by roughly the
/// ratio of the measurement noise ([measurementNoiseM]) to the filter's
/// steady-state uncertainty.
///
/// Design decisions, in one place:
///
/// * **Local tangent plane, not raw lat/lon.** Kalman updates assume a linear
///   observation model; degrees of latitude/longitude are only locally
///   proportional to metres. The track is projected east/north about its first
///   valid fix (equirectangular, longitude unwrapped), filtered there, then
///   unprojected — the same reasoning `DeadReckoningService` uses for its
///   plane. Dateline crossings survive via the unwrapping; the projection is
///   accurate to well under a metre for city-to-metro-scale tracks.
/// * **Bounded correction ([maxCorrectionM]).** A filter that trusts its
///   model too much rounds off real corners. Every corrected vertex is
///   clamped to lie within [maxCorrectionM] of its raw measurement, so the
///   output can never wander far from where the GPS actually placed the
///   device — smoothing removes jitter, never geometry.
/// * **Gap reset ([maxGap]).** When the fixes stop for longer than [maxGap]
///   (app killed, tracking paused, long indoor stretch), the
///   constant-velocity model is meaningless across the hole: continuing it
///   would drag the post-gap fixes toward the pre-gap position. The filter
///   instead re-seeds on the first fix after the hole, so genuine displacement
///   across an outage is preserved exactly instead of smeared.
/// * **Anchored endpoints** ([anchorEndpoints], on by default): the first and
///   last vertices come back untouched, so the smoothed route still starts and
///   ends precisely where the recording did (trail-head accuracy matters for a
///   saved places app).
///
/// Pure, deterministic and offline: no clock, no platform channels, no
/// network, no persistence — the output contains nothing but geometry derived
/// from the input. Invalid vertices (non-finite, or outside the WGS-84 range)
/// are dropped rather than filtered.
class PolylineSmoother {
  const PolylineSmoother({
    this.measurementNoiseM = 8.0,
    this.processNoiseMps2 = 0.75,
    this.maxGap = const Duration(minutes: 2),
    this.maxCorrectionM = 30.0,
    this.assumedInterval = const Duration(seconds: 5),
    this.anchorEndpoints = true,
  });

  /// 1σ of the GPS measurement noise, in metres. 8 m is the typical civilian
  /// urban CEP and matches the trackers' ~10 m movement filter: noise below
  /// this is treated as jitter, motion above it as real travel.
  final double measurementNoiseM;

  /// 1σ of the model's acceleration (m/s²) — how much the velocity may
  /// legitimately change per second. 0.75 (≈0.08 g) is well above normal
  /// city driving, so genuine motion is followed while GPS noise is strongly
  /// attenuated; larger values follow corners more tightly and smooth less,
  /// smaller values smooth harder and lag more. Real corners never exceed
  /// [maxCorrectionM] lag regardless, because the output is clamped there.
  final double processNoiseMps2;

  /// Silence longer than this re-seeds the filter instead of predicting
  /// across the hole (see the class docs). Two minutes sits well beyond the
  /// trackers' 1 s / 5 s / 15 s sampling cadences, so normal tracking never
  /// trips it, while a genuine stop-and-resume does.
  final Duration maxGap;

  /// Hard cap on how far smoothing may move any single vertex away from its
  /// raw measurement, in metres.
  final double maxCorrectionM;

  /// Spacing assumed between consecutive fixes that carry no timestamp.
  final Duration assumedInterval;

  /// Whether the first and last vertices are returned exactly as recorded.
  final bool anchorEndpoints;

  /// Mean Earth radius (km) — the same constant `GapRecoveryService` uses.
  static const double earthRadiusKm = 6371.0088;

  static const double _degreesToRadians = math.pi / 180;
  static const double _radiansToDegrees = 180 / math.pi;

  /// Smooths [points] in place-order, preserving the vertex count (minus any
  /// invalid vertices) and returning a new list; the input is never mutated.
  List<RoutePoint> smooth(List<RoutePoint> points) {
    final List<RoutePoint> valid = <RoutePoint>[
      for (final RoutePoint point in points)
        if (_isValid(point)) point,
    ];
    if (valid.isEmpty) return const <RoutePoint>[];
    if (valid.length == 1) return <RoutePoint>[valid.first];

    final RoutePoint origin = valid.first;
    // Guard the unprojection at the poles, where a degree of longitude
    // collapses to nothing; 1e-6 keeps the maths finite without measurably
    // affecting any inhabited latitude.
    final double cosLatitude =
        math.max(math.cos(origin.latitude * _degreesToRadians), 1e-6);

    final _PlanarKalman filter = _PlanarKalman(
      processNoiseMps2: processNoiseMps2,
      measurementNoiseM: measurementNoiseM,
    );

    final List<RoutePoint> smoothed =
        List<RoutePoint>.filled(valid.length, origin);
    DateTime? previousAt;
    for (int i = 0; i < valid.length; i++) {
      final RoutePoint point = valid[i];
      final double eastM = (point.longitude - origin.longitude) *
          _degreesToRadians *
          earthRadiusKm *
          1000 *
          cosLatitude;
      final double northM = (point.latitude - origin.latitude) *
          _degreesToRadians *
          earthRadiusKm *
          1000;

      if (i == 0) {
        filter.seed(eastM: eastM, northM: northM);
        smoothed[i] = point;
        previousAt = point.at;
        continue;
      }

      final double dtSeconds = _stepSeconds(
        previous: previousAt,
        current: point.at,
      );
      previousAt = point.at;
      // A hole too long to model: re-seed on this fix so the displacement
      // across the gap survives unsmoothed (never dragged toward the past).
      if (dtSeconds > maxGap.inMicroseconds / Duration.microsecondsPerSecond) {
        filter.seed(eastM: eastM, northM: northM);
        smoothed[i] = point;
        continue;
      }

      filter.predict(dtSeconds);
      filter.correct(eastM: eastM, northM: northM);

      // Clamp the correction: smoothing may remove jitter, never geometry.
      final double de = filter.eastM - eastM;
      final double dn = filter.northM - northM;
      final double distanceM = math.sqrt(de * de + dn * dn);
      double eastOut = filter.eastM;
      double northOut = filter.northM;
      if (distanceM > maxCorrectionM && distanceM > 0) {
        eastOut = eastM + de / distanceM * maxCorrectionM;
        northOut = northM + dn / distanceM * maxCorrectionM;
      }
      smoothed[i] = RoutePoint(
        latitude: origin.latitude +
            northOut / (earthRadiusKm * 1000) * _radiansToDegrees,
        longitude: origin.longitude +
            eastOut / (earthRadiusKm * 1000 * cosLatitude) *
                _radiansToDegrees,
        at: point.at,
      );
    }

    if (anchorEndpoints) {
      smoothed[0] = valid.first;
      smoothed[smoothed.length - 1] = valid.last;
    }
    return smoothed;
  }

  /// Seconds between two fixes; falls back to [assumedInterval] whenever
  /// either timestamp is missing, and clamps backwards clock jumps to zero
  /// (predict nothing rather than something impossible).
  double _stepSeconds({
    required DateTime? previous,
    required DateTime? current,
  }) {
    if (previous == null || current == null) {
      return assumedInterval.inMicroseconds / Duration.microsecondsPerSecond;
    }
    final int delta = current.difference(previous).inMicroseconds;
    if (delta <= 0) return 0;
    return delta / Duration.microsecondsPerSecond;
  }

  bool _isValid(RoutePoint point) =>
      point.latitude.isFinite &&
      point.longitude.isFinite &&
      point.latitude >= -90 &&
      point.latitude <= 90 &&
      point.longitude >= -180 &&
      point.longitude <= 180;
}

/// Independent 1-D Kalman filter per planar axis — east and north never
/// interact (independent measurements, independent process noise), so each
/// axis carries its own `[position, velocity]` state and covariance
/// `[P00, P01, P11]` (P01 == P10, stored once).
///
/// Prediction uses the exact constant-velocity transition with a discrete
/// white-noise-acceleration process model; the correction is the closed-form
/// 2×2 update computed entirely from the pre-update covariance, so no
/// half-updated value can leak into the gain math.
class _PlanarKalman {
  _PlanarKalman({
    required this.processNoiseMps2,
    required this.measurementNoiseM,
  });

  final double processNoiseMps2;
  final double measurementNoiseM;

  double _eastM = 0;
  double _northM = 0;
  double _eastVelocity = 0;
  double _northVelocity = 0;

  // East-axis covariance.
  double _pee00 = 0;
  double _pee01 = 0;
  double _pee11 = 0;

  // North-axis covariance.
  double _pnn00 = 0;
  double _pnn01 = 0;
  double _pnn11 = 0;

  double get eastM => _eastM;

  double get northM => _northM;

  /// Re-seeds on a measurement with zero velocity and maximal uncertainty —
  /// used at session start and after any gap [PolylineSmoother.maxGap] long.
  void seed({required double eastM, required double northM}) {
    _eastM = eastM;
    _northM = northM;
    _eastVelocity = 0;
    _northVelocity = 0;
    final double variance = measurementNoiseM * measurementNoiseM;
    _pee00 = variance;
    _pee01 = 0;
    _pee11 = 0;
    _pnn00 = variance;
    _pnn01 = 0;
    _pnn11 = 0;
  }

  /// Advances the state by [dtSeconds]; `dt <= 0` is a no-op predict (a fix
  /// that arrives without elapsed time still gets corrected).
  void predict(double dtSeconds) {
    if (dtSeconds <= 0) return;
    final double q = processNoiseMps2 * processNoiseMps2;
    final double dt2 = dtSeconds * dtSeconds;
    final double qPosition = q * dt2 * dtSeconds / 3;
    final double qCross = q * dt2 / 2;
    final double qVelocity = q * dtSeconds;

    _eastM += _eastVelocity * dtSeconds;
    _pee00 += dtSeconds * (dtSeconds * _pee11 + 2 * _pee01) + qPosition;
    _pee01 += dtSeconds * _pee11 + qCross;
    _pee11 += qVelocity;

    _northM += _northVelocity * dtSeconds;
    _pnn00 += dtSeconds * (dtSeconds * _pnn11 + 2 * _pnn01) + qPosition;
    _pnn01 += dtSeconds * _pnn11 + qCross;
    _pnn11 += qVelocity;
  }

  /// Fuses one planar measurement, pulling each axis's estimate toward it by
  /// that axis's Kalman gain. All gain math consumes the pre-update
  /// covariance values passed in, so the two axes (and the two covariance
  /// rows) never see each other's half-updated state.
  void correct({required double eastM, required double northM}) {
    final double eastGainPosition = _positionGain(_pee00);
    final double eastGainVelocity = _velocityGain(_pee01, _pee00);
    final double eastResidual = eastM - _eastM;
    final double eastP01 = _pee01;
    _eastM += eastGainPosition * eastResidual;
    _eastVelocity += eastGainVelocity * eastResidual;
    _pee00 = (1 - eastGainPosition) * _pee00;
    _pee01 = (1 - eastGainPosition) * eastP01;
    _pee11 = _pee11 - eastGainVelocity * eastP01;

    final double northGainPosition = _positionGain(_pnn00);
    final double northGainVelocity = _velocityGain(_pnn01, _pnn00);
    final double northResidual = northM - _northM;
    final double northP01 = _pnn01;
    _northM += northGainPosition * northResidual;
    _northVelocity += northGainVelocity * northResidual;
    _pnn00 = (1 - northGainPosition) * _pnn00;
    _pnn01 = (1 - northGainPosition) * northP01;
    _pnn11 = _pnn11 - northGainVelocity * northP01;
  }

  /// Position-component Kalman gain for an axis with position variance [p00].
  double _positionGain(double p00) {
    final double innovation = p00 + measurementNoiseM * measurementNoiseM;
    return innovation > 0 ? p00 / innovation : 0;
  }

  /// Velocity-component Kalman gain for an axis with covariance pair
  /// ([p01], [p00]).
  double _velocityGain(double p01, double p00) {
    final double innovation = p00 + measurementNoiseM * measurementNoiseM;
    return innovation > 0 ? p01 / innovation : 0;
  }
}
