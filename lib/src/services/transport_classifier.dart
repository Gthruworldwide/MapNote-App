import 'dart:async';
import 'dart:math' as math;

import 'motion_sensor_hub.dart';

/// How the device is moving, as judged from the accelerometer (plus the GPS
/// Doppler speed when it is available).
enum TransportMode {
  /// Not moving (or the residual is sensor noise only).
  stationary,

  /// On foot: the residual carries the ~1–3 Hz rhythm of human steps.
  walking,

  /// In a road vehicle: broadband vibration / low-frequency body sway.
  vehicle,

  /// On a train or subway: fast, but a much smoother ride than a road
  /// vehicle — speed is high while the acceleration residual stays mild.
  train,
}

/// On-device transport-mode classifier: accelerometer window → FFT → mode.
///
/// The window's gravity-removed residual RMS separates "still" from "moving";
/// the dominant frequency of the residual (radix-2 FFT) separates the rhythmic
/// cadence of walking from the broadband rumble of wheels; and the GPS
/// Doppler speed — fused through [observeSpeed], never required — separates a
/// smooth high-speed ride (train) from a road vehicle and settles ambiguous
/// cases (a phone resting on a dashboard at motorway speed is in a vehicle,
/// not stationary).
///
/// Pure Dart and stream-driven: tests feed synthetic waveforms through
/// [feed] and assert the verdicts; production subscribes to the
/// accelerometer feed of `MotionSensorHub` in [start]. No location, identity
/// or user content is ever produced or stored — only the enum.
class TransportClassifier {
  TransportClassifier({
    required this._accelerometer,
    this.windowSize = 64,
    this.stationaryRms = 0.28,
    this.minPeakRatio = 0.18,
    this.minWalkingHz = 0.9,
    this.maxWalkingHz = 3.0,
    this.speedHintTtl = const Duration(seconds: 30),
    DateTime Function()? clock,
  })  : assert(windowSize >= 16 && (windowSize & (windowSize - 1)) == 0),
        _clock = clock ?? DateTime.now;

  /// Samples per analysis window; must be a power of two for the FFT. At the
  /// Android `SENSOR_DELAY_UI` rate (~16 Hz) 64 samples ≈ 4 s, giving 0.25 Hz
  /// bin resolution — enough to tell a 2 Hz step cadence from vehicle sway.
  final int windowSize;

  /// Residual RMS (m/s²) below which the device counts as stationary —
  /// identical to the trackers' `MotionClassifier.vibrationThreshold`, so the
  /// two classifiers agree on "moving at all".
  final double stationaryRms;

  /// Fraction of the window's spectral power that must sit in the dominant
  /// bin for that frequency to count as a *rhythm* (steps) rather than noise.
  final double minPeakRatio;

  /// Lower bound of the human step-cadence band (Hz).
  final double minWalkingHz;

  /// Upper bound of the human step-cadence band (Hz).
  final double maxWalkingHz;

  /// How long a Doppler speed reading stays fresh enough to steer a verdict.
  final Duration speedHintTtl;

  final Stream<AccelerometerSample> _accelerometer;
  final DateTime Function() _clock;

  /// Highway speed (km/h) above which a *smooth* ride is a train, not a car.
  static const double trainSpeedKmh = 55;

  /// Speed (km/h) above which the device cannot be walking; anything at or
  /// over this that is not stationary is a ride.
  static const double ridingSpeedKmh = 15;

  /// Residual RMS (m/s²) below which a fast ride still counts as "smooth"
  /// (steel-on-steel) rather than road vibration.
  static const double smoothRideRms = 0.9;

  /// Dominant frequency (Hz) below which a fast ride's motion is slow body
  /// sway rather than engine/road rumble.
  static const double slowSwayHz = 0.8;

  final List<double> _residuals = <double>[];
  final List<DateTime> _stamps = <DateTime>[];

  TransportMode _mode = TransportMode.stationary;
  double? _dominantHz;
  double? _rms;
  double? _speedMps;
  DateTime? _speedAt;

  StreamSubscription<AccelerometerSample>? _subscription;
  final StreamController<TransportMode> _modes =
      StreamController<TransportMode>.broadcast();

  /// Current verdict; [TransportMode.stationary] until a full window has been
  /// analysed.
  TransportMode get mode => _mode;

  /// Dominant residual frequency of the last analysed window (Hz), or `null`.
  double? get dominantFrequencyHz => _dominantHz;

  /// Residual RMS of the last analysed window (m/s²), or `null`.
  double? get residualRms => _rms;

  /// Emits whenever the verdict changes (broadcast; buffers nothing).
  Stream<TransportMode> get modes => _modes.stream;

  /// True while the accelerometer stream is subscribed.
  bool get isRunning => _subscription != null;

  /// Subscribes to the accelerometer feed. Idempotent.
  Future<void> start() async {
    if (isRunning) return;
    try {
      _subscription = _accelerometer.listen(
        (AccelerometerSample sample) =>
            feed(sample.x, sample.y, sample.z, at: sample.at),
      );
    } catch (_) {
      // Stream unavailable: stay in the conservative stationary default.
    }
  }

  /// Unsubscribes and clears the window (see AGENT_SKILLS: sensor streams
  /// must be cancelled on stop/dispose).
  Future<void> stop() async {
    final StreamSubscription<AccelerometerSample>? subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    _residuals.clear();
    _stamps.clear();
  }

  /// Fuses a GPS Doppler speed (m/s) so fast/slow verdicts can use it.
  void observeSpeed(double metersPerSecond, {DateTime? at}) {
    if (!metersPerSecond.isFinite || metersPerSecond < 0) return;
    _speedMps = metersPerSecond;
    _speedAt = at ?? _clock();
  }

  /// Feeds one raw accelerometer sample (m/s², gravity included). Once the
  /// window is full it is analysed and [mode] updated (announced on [modes]
  /// when it changed).
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
    final TransportMode verdict = analyse(
      residuals: _residuals,
      stamps: _stamps,
      speedMps: _freshSpeedMps(stamp),
    );
    _dominantHz = dominantFrequencyHzOf(residuals: _residuals, stamps: _stamps);
    _rms = rmsOf(_residuals);
    if (verdict != _mode) {
      _mode = verdict;
      if (!_modes.isClosed) _modes.add(verdict);
    }
  }

  /// Weight of each sample in the gravity estimate (0…1), matching the
  /// trackers' `MotionClassifier.gravityAdaptation`.
  static const double gravityAdaptation = 0.1;

  double _gravity = 0;
  bool _gravitySeeded = false;

  double? _freshSpeedMps(DateTime at) {
    final DateTime? speedAt = _speedAt;
    final double? speedMps = _speedMps;
    if (speedAt == null || speedMps == null) return null;
    if (at.difference(speedAt).abs() > speedHintTtl) return null;
    return speedMps;
  }

  /// The window's verdict. Pure function of the window plus an optional fresh
  /// speed hint — exposed for direct unit testing with synthetic waveforms.
  ///
  /// Decision order:
  ///
  /// 1. Residual below [stationaryRms]: still — unless the GPS insists the
  ///    device is doing [ridingSpeedKmh] (a smooth ride can read this quiet).
  /// 2. Fast ([trainSpeedKmh]) *and* smooth (low RMS, slow dominant
  ///    frequency): [TransportMode.train].
  /// 3. At or above [ridingSpeedKmh]: [TransportMode.vehicle] — the device
  ///    cannot be walking, and the residual proves it is not still.
  /// 4. A dominant frequency inside the step-cadence band with enough
  ///    spectral concentration: [TransportMode.walking].
  /// 5. Anything else that is not still: [TransportMode.vehicle] — broadband
  ///    wheel/engine vibration without a cadence.
  TransportMode analyse({
    required List<double> residuals,
    required List<DateTime> stamps,
    required double? speedMps,
  }) {
    final double rms = rmsOf(residuals);
    final double speedKmh = speedMps == null ? 0 : speedMps * 3.6;
    if (rms < stationaryRms) {
      return speedKmh >= ridingSpeedKmh
          ? TransportMode.vehicle
          : TransportMode.stationary;
    }
    final double? dominantHz = dominantFrequencyHzOf(
      residuals: residuals,
      stamps: stamps,
    );
    if (speedKmh >= trainSpeedKmh &&
        rms <= smoothRideRms &&
        dominantHz != null &&
        dominantHz < slowSwayHz) {
      return TransportMode.train;
    }
    if (speedKmh >= ridingSpeedKmh) return TransportMode.vehicle;
    if (dominantHz != null &&
        dominantHz >= minWalkingHz &&
        dominantHz <= maxWalkingHz &&
        peakRatioOf(residuals: residuals, stamps: stamps) >= minPeakRatio) {
      return TransportMode.walking;
    }
    return TransportMode.vehicle;
  }

  /// Root-mean-square of a residual window (m/s²).
  static double rmsOf(List<double> residuals) {
    double sumSquares = 0;
    for (final double residual in residuals) {
      sumSquares += residual * residual;
    }
    return math.sqrt(sumSquares / residuals.length);
  }

  /// Dominant frequency (Hz) of a residual window, estimated from the sample
  /// timestamps and the magnitude spectrum of a radix-2 FFT. Returns `null`
  /// for degenerate windows (no usable sample spacing).
  static double? dominantFrequencyHzOf({
    required List<double> residuals,
    required List<DateTime> stamps,
  }) {
    final _Spectrum? spectrum = _spectrumOf(residuals: residuals, stamps: stamps);
    return spectrum?.dominantHz;
  }

  /// Fraction of the window's spectral power concentrated in its dominant
  /// bin — high for a rhythmic cadence, low for broadband rumble.
  static double peakRatioOf({
    required List<double> residuals,
    required List<DateTime> stamps,
  }) {
    return _spectrumOf(residuals: residuals, stamps: stamps)?.peakRatio ?? 0;
  }

  /// Transforms one residual window: removes the mean (DC), zero-pads to the
  /// next power of two, runs the in-place radix-2 FFT and reports the
  /// dominant bin's frequency and its share of the (positive-frequency)
  /// power. `null` when the timestamps give no usable sample rate.
  static _Spectrum? _spectrumOf({
    required List<double> residuals,
    required List<DateTime> stamps,
  }) {
    if (residuals.length < 4 || stamps.length != residuals.length) return null;
    final double windowSeconds =
        stamps.last.difference(stamps.first).inMicroseconds / 1e6;
    if (windowSeconds <= 0) return null;
    final double sampleRateHz = (residuals.length - 1) / windowSeconds;
    if (!sampleRateHz.isFinite || sampleRateHz <= 0) return null;

    int size = 1;
    while (size < residuals.length) {
      size <<= 1;
    }
    double mean = 0;
    for (final double r in residuals) {
      mean += r;
    }
    mean /= residuals.length;
    final List<double> real = List<double>.filled(size, 0);
    final List<double> imag = List<double>.filled(size, 0);
    for (int i = 0; i < residuals.length; i++) {
      real[i] = residuals[i] - mean;
    }
    _fftInPlace(real, imag);

    double totalPower = 0;
    double peakPower = 0;
    int peakBin = 0;
    final int half = size ~/ 2;
    for (int k = 1; k < half; k++) {
      final double power = real[k] * real[k] + imag[k] * imag[k];
      totalPower += power;
      if (power > peakPower) {
        peakPower = power;
        peakBin = k;
      }
    }
    if (totalPower <= 0 || peakPower <= 0) return null;
    return _Spectrum(
      dominantHz: peakBin * sampleRateHz / size,
      peakRatio: peakPower / totalPower,
    );
  }

  /// In-place iterative radix-2 Cooley–Tukey FFT. [size] must be a power of
  /// two (callers zero-pad).
  static void _fftInPlace(List<double> real, List<double> imag) {
    final int size = real.length;
    // Bit-reversal permutation.
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
    // Butterfly stages.
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
}

/// Dominant frequency and spectral concentration of one analysed window.
class _Spectrum {
  const _Spectrum({required this.dominantHz, required this.peakRatio});

  final double dominantHz;
  final double peakRatio;
}
