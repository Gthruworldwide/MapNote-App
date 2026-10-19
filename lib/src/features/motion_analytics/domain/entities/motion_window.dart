/// One sample of the classifier's sliding window, already rotated into the
/// vehicle frame with gravity removed (m/s², see `GravityAlignmentCalculator`).
class MotionWindowSample {
  const MotionWindowSample({
    required this.lateral,
    required this.vertical,
    required this.longitudinal,
    required this.at,
  });

  /// `X_car` — lateral (positive to the driver's left).
  final double lateral;

  /// `Y_car` — vertical (positive up).
  final double vertical;

  /// `Z_car` — longitudinal (positive forward).
  final double longitudinal;

  /// When the sample was captured.
  final DateTime at;
}

/// A fixed-length sliding window of vehicle-frame samples: the classifier's
/// input, and the shape a trained model must be built for.
///
/// The contract is [sampleCount] samples at [sampleRateHz] — 2.56 s of driving
/// — in capture order (oldest first). A TFLite model's input tensor is
/// therefore `[1, 128, 3]` float32 with the channels ordered
/// `[lateral, vertical, longitudinal]`.
class MotionWindow {
  const MotionWindow(this.samples);

  /// An empty window (nothing buffered yet).
  static const MotionWindow empty = MotionWindow(<MotionWindowSample>[]);

  /// Samples per inference — 128 at [sampleRateHz] is 2.56 s.
  static const int sampleCount = 128;

  /// Nominal sampling rate of the accelerator feed the window is built from.
  static const int sampleRateHz = 50;

  /// How long a full window spans.
  static Duration get windowSpan => Duration(
    microseconds: sampleCount * 1000000 ~/ sampleRateHz,
  );

  /// Oldest → newest.
  final List<MotionWindowSample> samples;

  /// Whether enough samples have accumulated to classify.
  bool get isFull => samples.length == sampleCount;

  /// Wall-clock span between the first and last sample (`Duration.zero` for a
  /// window with fewer than two samples).
  Duration get span => samples.length < 2
      ? Duration.zero
      : samples.last.at.difference(samples.first.at);

  /// The `X_car` channel, in order.
  List<double> get lateral =>
      <double>[for (final MotionWindowSample sample in samples) sample.lateral];

  /// The `Y_car` channel, in order.
  List<double> get vertical =>
      <double>[for (final MotionWindowSample sample in samples) sample.vertical];

  /// The `Z_car` channel, in order.
  List<double> get longitudinal => <double>[
    for (final MotionWindowSample sample in samples) sample.longitudinal,
  ];

  @override
  String toString() =>
      'MotionWindow(${samples.length}/$sampleCount samples, ${span.inMilliseconds} ms)';
}
