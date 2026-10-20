import 'dart:async';
import 'dart:math' as math;

/// What the device is doing right now, as judged by `ActivityStateManager`.
///
/// The three states exist to answer one question: **is it worth paying for
/// high-frequency motion analysis?** Indoors, walking around with the phone in
/// a pocket, the answer is no — the vehicle classifier would burn CPU, heat and
/// battery classifying a gait it can never call a maneuver.
enum ActivityState {
  /// Still, or on foot: the accelerometer may be watched cheaply, but no
  /// vehicle analysis runs at all.
  stationaryOrWalking,

  /// Something just changed — the device is between a known still state and a
  /// confirmed vehicle. Ambiguous evidence is *not* enough to start analysis.
  transitioning,

  /// Confirmed in a road vehicle: analysis runs.
  vehicleDriving,
}

/// Gatekeeper that decides whether on-device motion analysis should run.
///
/// The problem it solves is battery and thermal drain. Walking indoors produces
/// exactly the kind of broadband accelerometer residual a naive classifier
/// treats as "motion", so a phone in a pocket can keep a 50 Hz analysis pipeline
/// (and its background isolate) awake indefinitely for no benefit. The gate
/// therefore runs two cheap tests and only opens for a **confirmed vehicle**:
///
/// * **Speed.** A Doppler speed above [vehicleSpeedKmh] (15 km/h) is the one
///   piece of evidence walking can never produce. It is necessary but not
///   sufficient: a phone on a train, a bus or a dashboard at 40 km/h would
///   otherwise open the gate on speed alone.
/// * **Vehicle-range vibration, held.** The gravity-removed residual must stay
///   inside the vehicle band (RMS at or above [vibrationRms] m/s², and *not*
///   concentrated in the step-cadence band) for a continuous
///   [vehicleConfirmDuration] (5 s). The *hold* is what rejects a single pothole
///   or a stumble, and the step-cadence rejection is what separates a vehicle
///   from a walker whose arm swings at 2 Hz.
///
/// Leaving the vehicle state is deliberately slower than entering it (see
/// [autoStandbyDuration]): analysis must not stop the instant a traffic light
/// turns red, because that is exactly when braking and launch maneuvers happen.
/// It stops only when the evidence has been *consistently* pedestrian or still
/// for two minutes — or immediately when the mode is turned off outright.
///
/// Pure Dart and deterministic under injected timestamps: [evaluate] and
/// [observeSpeed] take the clock's value, and `feed` timestamps samples, so
/// tests advance time without sleeping. It reads only magnitudes and speeds —
/// never a location — so nothing it sees can leak where the user is.
class ActivityStateManager {
  ActivityStateManager({
    this.vehicleSpeedKmh = 15,
    this.vibrationRms = 0.28,
    this.vehicleConfirmDuration = const Duration(seconds: 5),
    this.autoStandbyDuration = const Duration(minutes: 2),
    this.windowSize = 32,
    this.minWalkingHz = 0.5,
    this.maxWalkingHz = 3.0,
    this.stepPeakRatio = 0.35,
    this.stepRejectionSamples = 4,
    this.speedHintTtl = const Duration(seconds: 30),
    this.vibrationSampleGap = const Duration(seconds: 2),
    DateTime Function()? clock,
  })  : assert(vehicleSpeedKmh > 0),
        assert(vibrationRms > 0),
        assert(windowSize > 0),
        assert(minWalkingHz > 0 && minWalkingHz < maxWalkingHz),
        assert(stepPeakRatio > 0 && stepPeakRatio <= 1),
        assert(stepRejectionSamples > 0),
        _clock = clock ?? DateTime.now;

  /// Doppler speed (km/h) above which the device cannot be on foot. The same
  /// boundary as `TransportClassifier.ridingSpeedKmh`, so the two agree on
  /// "walking is impossible at this speed".
  final double vehicleSpeedKmh;

  /// [vehicleSpeedKmh] in m/s — the unit the evidence actually arrives in, so
  /// boundary comparisons never round-trip through km/h.
  double get vehicleSpeedMps => vehicleSpeedKmh / 3.6;

  /// Gravity-removed residual RMS (m/s²) at or above which the accelerometer
  /// confirms real dynamics — the trackers' and classifiers' shared "moving"
  /// floor.
  final double vibrationRms;

  /// How long vehicle-range vibration must **hold continuously** before the
  /// gate opens (5 s). A single pothole, a stumble or a snatched phone is a
  /// spike, not a drive.
  final Duration vehicleConfirmDuration;

  /// How long pedestrian/still evidence must persist before the gate closes
  /// again (2 min). Deliberately far longer than the entry hold: stopping
  /// analysis at a red light would miss the braking and launch maneuvers that
  /// happen exactly there.
  final Duration autoStandbyDuration;

  /// Samples per residual window (the vibration judgement's horizon).
  final int windowSize;

  /// Lower bound of the human step-cadence band (Hz).
  final double minWalkingHz;

  /// Upper bound of the human step-cadence band (Hz).
  final double maxWalkingHz;

  /// Fraction of window power concentrated in a step-band bin before the window
  /// is called a *gait* rather than vehicle rumble.
  final double stepPeakRatio;

  /// Consecutive step-cadence windows before the evidence counts as walking.
  final int stepRejectionSamples;

  /// How long a Doppler speed stays fresh enough to steer a verdict.
  final Duration speedHintTtl;

  /// Longest gap between vibration windows that still counts as *continuous*
  /// evidence; a bigger hole restarts the hold.
  final Duration vibrationSampleGap;

  final DateTime Function() _clock;

  final List<double> _residuals = <double>[];
  final List<DateTime> _stamps = <DateTime>[];
  final StreamController<ActivityState> _states =
      StreamController<ActivityState>.broadcast();

  ActivityState _state = ActivityState.stationaryOrWalking;
  DateTime? _vehicleEvidenceSince;
  DateTime? _pedestrianEvidenceSince;
  DateTime? _lastVibrationAt;
  int _stepWindows = 0;
  double? _speedMps;
  DateTime? _speedAt;
  int _transitions = 0;

  /// Current state; [ActivityState.stationaryOrWalking] until vehicle evidence
  /// confirms — analysis is off by default, never on by accident.
  ActivityState get state => _state;

  /// True only in [ActivityState.vehicleDriving] — the single condition under
  /// which high-frequency analysis may run.
  bool get isAnalysisEnabled => _state == ActivityState.vehicleDriving;

  /// Whether the current state allows analysis (see [isAnalysisEnabled]).
  bool get allowsAnalysis => isAnalysisEnabled;

  /// Emits on every state change (broadcast; buffers nothing).
  Stream<ActivityState> get states => _states.stream;

  /// How many times the state has changed since construction (diagnostics).
  int get transitionCount => _transitions;

  /// Residual RMS of the latest window (m/s²), or `null` until one is full.
  double? get lastVibrationRms =>
      _residuals.isEmpty ? null : math.sqrt(_rmsSquared(_residuals) / _residuals.length);

  /// Latest Doppler speed (m/s), or `null` when none was observed.
  double? get lastSpeedMps => _speedMps;

  /// How long vehicle-range vibration has held, or `Duration.zero`.
  Duration get vehicleEvidenceAge {
    final DateTime? since = _vehicleEvidenceSince;
    final DateTime? now = _lastVibrationAt;
    if (since == null || now == null) return Duration.zero;
    return now.difference(since);
  }

  /// How long pedestrian/still evidence has held, or `Duration.zero`.
  Duration get pedestrianEvidenceAge {
    final DateTime? since = _pedestrianEvidenceSince;
    final DateTime? now = _lastVibrationAt ?? _speedAt;
    if (since == null || now == null) return Duration.zero;
    return now.difference(since);
  }

  /// Feeds one raw accelerometer sample (m/s², gravity included).
  ///
  /// Cheap by design: this is the only work the gate does while the phone sits
  /// in a pocket, and it is a gravity EMA plus one RMS/Frequency judgement per
  /// window — no isolate, no model, no allocation per sample beyond one double.
  void feed(double x, double y, double z, {DateTime? at}) {
    final DateTime stamp = at ?? _clock();
    final double magnitude = math.sqrt(x * x + y * y + z * z);
    if (!_gravitySeeded) {
      _gravity = magnitude;
      _gravitySeeded = true;
    }
    final double residual = magnitude - _gravity;
    _gravity += (magnitude - _gravity) * gravityAdaptation;
    _residuals.add(residual);
    _stamps.add(stamp);
    if (_residuals.length > windowSize) {
      _residuals.removeAt(0);
      _stamps.removeAt(0);
    }
    if (_residuals.length < windowSize) return;
    _evaluateWindow(stamp);
  }

  /// Fuses a GPS Doppler speed (m/s) so the speed test can use it.
  void observeSpeed(double metersPerSecond, {DateTime? at}) {
    if (!metersPerSecond.isFinite || metersPerSecond < 0) return;
    _speedMps = metersPerSecond;
    _speedAt = at ?? _clock();
  }

  /// Re-evaluates the state at [at] without new samples — used when a speed
  /// reading alone is the deciding evidence, and by tests stepping the clock.
  void evaluate({DateTime? at}) {
    if (_residuals.isEmpty && _speedMps == null) return;
    _transition(_classify(at ?? _clock()), at ?? _clock());
  }

  /// Forces the gate shut immediately, with no evidence window: the user
  /// switched vehicle mode off, or the trip ended. Cheap and idempotent — the
  /// point of the gate is to stop paying for analysis *now*, not in two
  /// minutes.
  void suspend() {
    _stepWindows = 0;
    _vehicleEvidenceSince = null;
    _pedestrianEvidenceSince = null;
    _lastVibrationAt = null;
    _transition(ActivityState.stationaryOrWalking, _clock());
  }

  /// Forgets every buffer and returns to the default state. Used when a new
  /// trip starts, so no evidence from the previous drive can leak across.
  void reset() {
    _residuals.clear();
    _stamps.clear();
    _gravity = 0;
    _gravitySeeded = false;
    _speedMps = null;
    _speedAt = null;
    _transition(ActivityState.stationaryOrWalking, _clock());
    _stepWindows = 0;
    _vehicleEvidenceSince = null;
    _pedestrianEvidenceSince = null;
    _lastVibrationAt = null;
  }

  /// Releases the state stream. The manager is unusable afterwards.
  Future<void> dispose() async => _states.close();

  /// Weight of each sample in the gate's gravity estimate, matching
  /// `TransportClassifier.gravityAdaptation` so "residual" means the same
  /// thing everywhere in the app.
  static const double gravityAdaptation = 0.1;

  double _gravity = 0;
  bool _gravitySeeded = false;

  void _evaluateWindow(DateTime at) {
    final double rms = lastVibrationRms ?? 0;
    final bool inVehicleBand = rms >= vibrationRms;
    final bool stepLike = _isStepCadence();
    _stepWindows = stepLike ? _stepWindows + 1 : 0;

    final double? speedMps = _freshSpeedMps(at);
    // Compared in m/s rather than through a km/h round-trip: `15 / 3.6 * 3.6`
    // does not return exactly `15.0` in binary floating point, so a km/h
    // comparison would let the exact boundary through.
    final bool fastEnough = speedMps != null && speedMps > vehicleSpeedMps;

    // The *only* combination that opens the gate: fast enough to rule out
    // walking, and broadband (non-step) vibration in the vehicle range.
    if (fastEnough && inVehicleBand && !stepLike) {
      final DateTime? since = _vehicleEvidenceSince;
      final DateTime? lastAt = _lastVibrationAt;
      final bool continuous = since != null &&
          lastAt != null &&
          at.difference(lastAt) <= vibrationSampleGap;
      _vehicleEvidenceSince = continuous ? since : at;
      _lastVibrationAt = at;
    } else {
      _vehicleEvidenceSince = null;
    }

    // Pedestrian/still evidence: not fast, or a gait is recognisable.
    if (!fastEnough || stepLike) {
      final DateTime? since = _pedestrianEvidenceSince;
      final DateTime? lastAt = _lastVibrationAt;
      final bool continuous = since != null &&
          lastAt != null &&
          at.difference(lastAt) <= vibrationSampleGap;
      _pedestrianEvidenceSince = continuous ? since : at;
    } else {
      _pedestrianEvidenceSince = null;
    }
    _lastVibrationAt = at;

    _transition(_classify(at), at);
  }

  /// The state implied by the evidence accumulated so far, at [at].
  ActivityState _classify(DateTime at) {
    final DateTime? vehicleSince = _vehicleEvidenceSince;
    if (vehicleSince != null &&
        at.difference(vehicleSince) >= vehicleConfirmDuration) {
      return ActivityState.vehicleDriving;
    }

    final DateTime? pedestrianSince = _pedestrianEvidenceSince;
    final bool pedestrianLongEnough = pedestrianSince != null &&
        at.difference(pedestrianSince) >= autoStandbyDuration;
    final bool stepOrStill = _stepWindows >= stepRejectionSamples ||
        ((_freshSpeedMps(at) ?? 0) <= vehicleSpeedMps);

    // Leaving the vehicle state needs *sustained* pedestrian evidence, so a
    // red light or a lift bridge cannot switch analysis off.
    if (_state == ActivityState.vehicleDriving) {
      if (pedestrianLongEnough && stepOrStill) {
        return ActivityState.stationaryOrWalking;
      }
      return ActivityState.vehicleDriving;
    }

    // Anything else is ambiguous: from a cold start with no vehicle proof the
    // honest answer is "not driving", and analysis stays off. A hold created by
    // *this* window is not yet evidence of anything — a single spike would
    // otherwise flicker through `transitioning` on the way past.
    if (vehicleSince == null || !at.isAfter(vehicleSince)) {
      return ActivityState.stationaryOrWalking;
    }
    return ActivityState.transitioning;
  }

  void _transition(ActivityState next, DateTime at) {
    if (next == _state) return;
    _state = next;
    _transitions += 1;
    if (!_states.isClosed) _states.add(next);
  }

  double? _freshSpeedMps(DateTime at) {
    final DateTime? speedAt = _speedAt;
    final double? speedMps = _speedMps;
    if (speedAt == null || speedMps == null) return null;
    if (at.difference(speedAt).abs() > speedHintTtl) return null;
    return speedMps;
  }

  /// Whether the current window looks like a human gait: enough of its power
  /// concentrated inside the step-cadence band (0.5–3 Hz).
  ///
  /// This is the *step pattern rejection* the gate is built around — the same
  /// spectral idea `TransportClassifier` uses, applied to a deliberately
  /// narrower band, because here a false "walking" on a real drive is expensive
  /// (it would switch analysis off) and a false "vehicle" indoors is expensive
  /// too.
  bool _isStepCadence() {
    if (_residuals.length < 8 || _stamps.length != _residuals.length) {
      return false;
    }
    final double span = _stamps.last.difference(_stamps.first).inMicroseconds /
        Duration.microsecondsPerSecond;
    if (span <= 0) return false;
    final double sampleRateHz = (_residuals.length - 1) / span;
    if (!sampleRateHz.isFinite || sampleRateHz <= 0) return false;

    int size = 1;
    while (size < _residuals.length) {
      size <<= 1;
    }
    double mean = 0;
    for (final double residual in _residuals) {
      mean += residual;
    }
    mean /= _residuals.length;
    final List<double> real = List<double>.filled(size, 0);
    final List<double> imag = List<double>.filled(size, 0);
    for (int index = 0; index < _residuals.length; index++) {
      real[index] = _residuals[index] - mean;
    }
    _fftInPlace(real, imag);

    double totalPower = 0;
    double stepPower = 0;
    final int half = size ~/ 2;
    for (int bin = 1; bin < half; bin++) {
      final double hz = bin * sampleRateHz / size;
      final double power = real[bin] * real[bin] + imag[bin] * imag[bin];
      totalPower += power;
      if (hz >= minWalkingHz && hz <= maxWalkingHz) stepPower += power;
    }
    if (totalPower <= 0) return false;
    return stepPower / totalPower >= stepPeakRatio;
  }

  /// In-place iterative radix-2 Cooley–Tukey FFT ([size] is a power of two).
  static void _fftInPlace(List<double> real, List<double> imag) {
    final int size = real.length;
    for (int i = 1, j = 0; i < size; i++) {
      int bit = size >> 1;
      for (; (j & bit) != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final double tempReal = real[i];
        real[i] = real[j];
        real[j] = tempReal;
        final double tempImag = imag[i];
        imag[i] = imag[j];
        imag[j] = tempImag;
      }
    }
    for (int length = 2; length <= size; length <<= 1) {
      final double angle = -2 * math.pi / length;
      final double wReal = math.cos(angle);
      final double wImag = math.sin(angle);
      for (int i = 0; i < size; i += length) {
        double curReal = 1;
        double curImag = 0;
        final int halfLength = length >> 1;
        for (int k = 0; k < halfLength; k++) {
          final double uReal = real[i + k];
          final double uImag = imag[i + k];
          final double vSourceReal = real[i + k + halfLength];
          final double vSourceImag = imag[i + k + halfLength];
          final double vReal = vSourceReal * curReal - vSourceImag * curImag;
          final double vImag = vSourceReal * curImag + vSourceImag * curReal;
          real[i + k] = uReal + vReal;
          imag[i + k] = uImag + vImag;
          real[i + k + halfLength] = uReal - vReal;
          imag[i + k + halfLength] = uImag - vImag;
          final double nextReal = curReal * wReal - curImag * wImag;
          curImag = curReal * wImag + curImag * wReal;
          curReal = nextReal;
        }
      }
    }
  }

  static double _rmsSquared(List<double> values) {
    double sum = 0;
    for (final double value in values) {
      sum += value * value;
    }
    return sum;
  }
}
