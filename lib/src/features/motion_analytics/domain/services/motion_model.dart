import 'dart:math' as math;

import '../entities/motion_event.dart';
import '../entities/motion_window.dart';

/// One class the model scored above its decision threshold.
class MotionPrediction {
  const MotionPrediction({
    required this.kind,
    required this.confidence,
    required this.peakMps2,
  });

  /// The predicted class.
  final MotionEventKind kind;

  /// Confidence in `[0, 1]`.
  final double confidence;

  /// Signed peak on [kind]'s deciding axis (see
  /// [decidingAxisPeak]); zero for [MotionEventKind.smoothDrive].
  final double peakMps2;

  @override
  bool operator ==(Object other) =>
      other is MotionPrediction &&
      other.kind == kind &&
      other.confidence == confidence &&
      other.peakMps2 == peakMps2;

  @override
  int get hashCode => Object.hash(kind, confidence, peakMps2);

  @override
  String toString() =>
      'MotionPrediction(${kind.modelLabel}, ${confidence.toStringAsFixed(2)}, '
      '${peakMps2.toStringAsFixed(1)})';
}

/// A maneuver classifier over one vehicle-frame [MotionWindow].
///
/// # This is the seam for a trained model
///
/// The whole pipeline — gravity alignment, the 50 Hz/128-sample buffer, the
/// background isolate, event de-duplication and the analyzer bridge — only ever
/// talks to this interface. Swapping in a TFLite model therefore means writing
/// **one** new implementation (load the interpreter + run the tensor) and
/// handing it to `MLClassifierIsolate`: nothing else changes.
///
/// The input/output contract a trained model must honour:
///
/// * **Input** — `[1, 128, 3]` float32, one second-major row per sample, the
///   channels ordered `[lateral, vertical, longitudinal]` (`X_car`, `Y_car`,
///   `Z_car`), in m/s² with gravity already removed. Build it from
///   `window.lateral` / `vertical` / `longitudinal`.
/// * **Output** — one score per class in [labels] order. Soft-max the raw
///   logits and hand the probabilities to [decodeMotionScores], which applies
///   the shared threshold, the label mapping and the peak extraction, so the
///   decode side needs no new code either.
abstract class MotionModel {
  const MotionModel();

  /// Stable identifier of the implementation — surfaces in diagnostics and
  /// tests ("heuristic-v1", "motion-cnn-v2", …).
  String get id;

  /// Class order of the output: `labels[i]` is the class whose score sits at
  /// index `i`. Must match the trained model's label file.
  List<MotionEventKind> get labels;

  /// Classifies one window.
  ///
  /// Must be **pure and isolate-safe**: it runs on a background isolate, so it
  /// may touch nothing but its argument and plain Dart — no platform channels,
  /// no file system, no widget tree. Implementations never throw for
  /// ordinary input; a window they cannot classify yields an empty list.
  List<MotionPrediction> infer(MotionWindow window);
}

/// Builds a [MotionModel] **on the far side of an isolate boundary**.
///
/// Must be a top-level function or a static method: a spawned isolate can only
/// reach entry points, and a live TFLite interpreter can never itself cross an
/// isolate boundary — so the model is rebuilt inside the worker from this
/// tear-off instead of being sent.
typedef MotionModelBuilder = MotionModel Function();

/// The signed peak of [kind]'s deciding axis over [window] (m/s²).
///
/// * [MotionEventKind.hardBrake] / [MotionEventKind.pothole] peak *negative*:
///   the strongest braking / downward impulse.
/// A maneuver's peak is taken on the axis that *decides* it, in the direction
/// that decides it — never the plain maximum, or a left turn would be reported
/// with the magnitude of an unrelated right-hand twitch.
///
/// * [MotionEventKind.hardBrake] / [MotionEventKind.pothole] peak on the most
///   *negative* reading: the strongest braking / downward impulse.
/// * [MotionEventKind.hardAccel] / [MotionEventKind.speedBump] on the most
///   *positive*.
/// * [MotionEventKind.sharpTurn] takes the `X_car` value with the largest
///   *magnitude*, keeping the sign that tells left from right.
/// * [MotionEventKind.smoothDrive] has no deciding axis and reports zero.
double decidingAxisPeak(MotionEventKind kind, MotionWindow window) {
  final List<double> channel = switch (kind) {
    MotionEventKind.hardBrake ||
    MotionEventKind.hardAccel ||
    MotionEventKind.smoothDrive => window.longitudinal,
    MotionEventKind.sharpTurn => window.lateral,
    MotionEventKind.speedBump || MotionEventKind.pothole => window.vertical,
  };
  if (channel.isEmpty) return 0;
  if (kind == MotionEventKind.smoothDrive) return 0;

  if (kind == MotionEventKind.sharpTurn) {
    double strongest = channel.first;
    for (final double value in channel) {
      if (value.abs() > strongest.abs()) strongest = value;
    }
    return strongest;
  }

  final bool negative =
      kind == MotionEventKind.hardBrake || kind == MotionEventKind.pothole;
  double peak = channel.first;
  for (final double value in channel) {
    if (negative ? value < peak : value > peak) peak = value;
  }
  return peak;
}

/// Decodes a trained model's score vector into predictions.
///
/// This is the shared output half of the model contract (see [MotionModel]):
/// apply it to the soft-maxed output tensor and the TFLite implementation needs
/// no decoding logic of its own. Classes scoring at or above [minConfidence] are
/// returned strongest first, with their deciding-axis peak taken from [window].
///
/// Non-finite scores are ignored, so a degenerate tensor produces no events
/// instead of throwing on a background isolate.
List<MotionPrediction> decodeMotionScores({
  required List<double> scores,
  required List<MotionEventKind> labels,
  required MotionWindow window,
  double minConfidence = 0.5,
}) {
  final List<MotionPrediction> predictions = <MotionPrediction>[];
  final int count = math.min(scores.length, labels.length);
  for (int index = 0; index < count; index++) {
    final double score = scores[index];
    if (!score.isFinite || score < minConfidence) continue;
    final MotionEventKind kind = labels[index];
    predictions.add(
      MotionPrediction(
        kind: kind,
        confidence: score.clamp(0.0, 1.0),
        peakMps2: decidingAxisPeak(kind, window),
      ),
    );
  }
  predictions.sort(
    (MotionPrediction a, MotionPrediction b) =>
        b.confidence.compareTo(a.confidence),
  );
  return predictions;
}
