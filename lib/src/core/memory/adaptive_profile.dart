/// Anonymous numbers the analytics pipeline has learned about *this device*.
///
/// The whole point of the adaptive profile is that one phone's vehicle
/// vibration, and one mounting's noise floor, are not another's. A cradle that
/// rattles at 0.4 m/s² and a magnet mount that rattles at 0.15 m/s² should not
/// share a threshold; learning the baseline locally makes the classifier sharper
/// on each device without a cloud model or an account.
///
/// **Privacy by construction.** Every field is a scalar derived from the
/// accelerometer. There is no field that could hold a place name, a note, a
/// coordinate, a timestamp of where the user was, or an account id — so a
/// stolen profile file reveals a mounting's vibration character and nothing
/// about the person. The box is encrypted anyway (see
/// [AdaptiveProfileKeyStore]), but the schema is designed so that even a leak
/// would be harmless.
class AdaptiveProfile {
  const AdaptiveProfile({
    this.vibrationBaselineMps2 = 0,
    this.vibrationSamples = 0,
    this.noiseFloorMps2 = 0,
    this.noiseSamples = 0,
    this.brakeThresholdMps2 = 4.0,
    this.accelThresholdMps2 = 3.5,
    this.bumpThresholdMps2 = 3.0,
    this.drivesObserved = 0,
    this.revision = 1,
  });

  /// The default profile: the documented physical thresholds, unadapted.
  static const AdaptiveProfile defaults = AdaptiveProfile();

  /// Exponential moving average of the residual RMS seen while driving (m/s²).
  /// This is the device's *characteristic* vibration for the current mounting.
  final double vibrationBaselineMps2;

  /// How many windows contributed to [vibrationBaselineMps2]. Kept so a single
  /// first sample cannot masquerade as a well-learned baseline.
  final int vibrationSamples;

  /// The quietest steady residual observed while stationary on the mounting —
  /// the sensor's own noise floor, which bounds how small a real threshold can
  /// usefully be.
  final double noiseFloorMps2;

  /// Samples contributing to [noiseFloorMps2].
  final int noiseSamples;

  /// Adapted hard-braking threshold (m/s²), never below the physical floor.
  final double brakeThresholdMps2;

  /// Adapted harsh-acceleration threshold (m/s²).
  final double accelThresholdMps2;

  /// Adapted speed-bump / pothole threshold (m/s²).
  final double bumpThresholdMps2;

  /// How many drives have contributed, i.e. how much this profile is trustworthy.
  final int drivesObserved;

  /// Schema revision, so a future change can migrate instead of mis-reading.
  final int revision;

  /// Whether the profile has seen enough to be trusted over the defaults.
  bool get isTrustworthy => drivesObserved >= minDrivesForTrust;

  /// Drives needed before learned thresholds are used at all.
  static const int minDrivesForTrust = 3;

  /// How much each new drive's baseline moves the learned one. Slow on purpose:
  /// a single unusual drive (rental car, rough road) must not recalibrate the
  /// device permanently.
  static const double adaptationRate = 0.25;

  /// Blend one observed drive into the profile.
  ///
  /// Pure: returns a new profile, so a caller can decide whether to persist it
  /// (e.g. only after a *completed*, plausible drive) without mutating shared
  /// state.
  AdaptiveProfile learn({
    double? vibrationRms,
    double? noiseFloor,
    int? brakeEvents,
    int? accelEvents,
  }) {
    double nextBaseline = vibrationBaselineMps2;
    int nextSamples = vibrationSamples;
    if (vibrationRms != null && vibrationRms.isFinite && vibrationRms >= 0) {
      nextBaseline = vibrationSamples == 0
          ? vibrationRms
          : vibrationBaselineMps2 +
              (vibrationRms - vibrationBaselineMps2) * adaptationRate;
      nextSamples = vibrationSamples + 1;
    }

    double nextNoise = noiseFloorMps2;
    int nextNoiseSamples = noiseSamples;
    if (noiseFloor != null && noiseFloor.isFinite && noiseFloor >= 0) {
      // The *minimum* steady residual: a noise floor only goes down as more
      // evidence arrives, because the quietest the sensor ever got is the floor.
      nextNoise = noiseSamples == 0
          ? noiseFloor
          : (noiseFloor < noiseFloorMps2 ? noiseFloor : noiseFloorMps2);
      nextNoiseSamples = noiseSamples + 1;
    }

    // Thresholds are nudged up only when the baseline is *high* — a noisy
    // mounting raises the bar so real events are not buried in rattle. They are
    // never adapted below the documented physical minima, because those encode
    // real vehicle dynamics a noisy phone must not be allowed to erase.
    final double nextBrake =
        _adaptThreshold(brakeThresholdMps2, nextBaseline, minBrakeMps2);
    final double nextAccel =
        _adaptThreshold(accelThresholdMps2, nextBaseline, minAccelMps2);
    final double nextBump =
        _adaptThreshold(bumpThresholdMps2, nextBaseline, minBumpMps2);

    return AdaptiveProfile(
      vibrationBaselineMps2: nextBaseline,
      vibrationSamples: nextSamples,
      noiseFloorMps2: nextNoise,
      noiseSamples: nextNoiseSamples,
      brakeThresholdMps2: nextBrake,
      accelThresholdMps2: nextAccel,
      bumpThresholdMps2: nextBump,
      drivesObserved: drivesObserved + 1,
      revision: revision,
    );
  }

  /// Physical floors the adapted thresholds may never cross.
  static const double minBrakeMps2 = 3.0;
  static const double minAccelMps2 = 2.5;
  static const double minBumpMps2 = 2.0;

  /// Raises [current] toward `baseline * 2`, clamped between [floor] and a
  /// sane ceiling, so a noisy mounting widens the trigger band but a quiet one
  /// never narrows it below the documented physics.
  static double _adaptThreshold(double current, double baseline, double floor) {
    if (baseline <= 0) return current;
    // A mounting whose characteristic vibration is `baseline` needs a trigger
    // clear of the rattle; twice the baseline is the documented heuristic, and
    // the EMA smooths it so one rough drive cannot jump the threshold.
    final double target = baseline * 2;
    final double adapted = current + (target - current) * adaptationRate;
    final double ceiling = floor * 4;
    final double raised = adapted < current ? current : adapted;
    return raised.clamp(floor, ceiling);
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'vibrationBaselineMps2': vibrationBaselineMps2,
        'vibrationSamples': vibrationSamples,
        'noiseFloorMps2': noiseFloorMps2,
        'noiseSamples': noiseSamples,
        'brakeThresholdMps2': brakeThresholdMps2,
        'accelThresholdMps2': accelThresholdMps2,
        'bumpThresholdMps2': bumpThresholdMps2,
        'drivesObserved': drivesObserved,
        'revision': revision,
      };

  /// Rebuilds a profile from stored values, tolerating missing or malformed
  /// fields by falling back to the default for that field.
  ///
  /// A profile is a cache of numbers, never a source of truth, so a partially
  /// corrupt record degrades field-by-field instead of failing the load.
  static AdaptiveProfile fromMap(Map<String, dynamic> map) {
    double number(String key, double fallback) {
      final Object? value = map[key];
      if (value is num && value.isFinite) return value.toDouble();
      return fallback;
    }

    int integer(String key, int fallback) {
      final Object? value = map[key];
      if (value is num) return value.toInt();
      return fallback;
    }

    return AdaptiveProfile(
      vibrationBaselineMps2:
          number('vibrationBaselineMps2', defaults.vibrationBaselineMps2),
      vibrationSamples: integer('vibrationSamples', 0),
      noiseFloorMps2: number('noiseFloorMps2', defaults.noiseFloorMps2),
      noiseSamples: integer('noiseSamples', 0),
      brakeThresholdMps2:
          number('brakeThresholdMps2', defaults.brakeThresholdMps2),
      accelThresholdMps2:
          number('accelThresholdMps2', defaults.accelThresholdMps2),
      bumpThresholdMps2: number('bumpThresholdMps2', defaults.bumpThresholdMps2),
      drivesObserved: integer('drivesObserved', 0),
      revision: integer('revision', defaults.revision),
    );
  }

  @override
  String toString() => 'AdaptiveProfile(base: '
      '${vibrationBaselineMps2.toStringAsFixed(3)}, drives: $drivesObserved)';
}
