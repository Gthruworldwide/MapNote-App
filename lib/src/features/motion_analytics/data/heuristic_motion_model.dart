import 'dart:math' as math;

import '../domain/entities/motion_event.dart';
import '../domain/entities/motion_window.dart';
import '../domain/services/motion_model.dart';

/// Builds the model the app ships: the deterministic feature classifier.
///
/// Deliberately a **top-level function**: the inference isolate is spawned with
/// this tear-off, so it can rebuild the model on its own side (a live TFLite
/// interpreter could never be sent across the boundary — a builder must be).
/// Switching the whole pipeline to a trained model means pointing
/// `motionModelBuilder` at a builder that loads the `.tflite` asset; nothing
/// else in the pipeline changes.
MotionModel buildHeuristicMotionModel() => const HeuristicMotionModel();

/// The deterministic classifier that ships in the app today: it reads the
/// vehicle-frame window (see `GravityAlignmentCalculator`) and applies physical
/// thresholds to the three axes.
///
/// Why not a model file: the repo has no trained weights, and inventing some
/// would emit confident nonsense. This implementation is honest — every rule
/// below is a documented, reproducible measurement on `X_car` / `Y_car` /
/// `Z_car` — and it sits behind [MotionModel], the exact seam a trained
/// `tflite_flutter` model plugs into (see [MotionModel] for the tensor
/// contract and `decodeMotionScores` for the shared output decoding).
///
/// The rules, all in m/s² on gravity-free vehicle axes:
///
/// * **hardBrake** — `Z_car` at or below `-`[hardBrakeThresholdMps2] for at
///   least [sustainedSamples] samples. *Sustained*, because a single
///   longitudinal spike is road noise; braking holds.
/// * **hardAccel** — the mirror image on `+Z_car`.
/// * **sharpTurn** — `|X_car|` beyond [sharpTurnThresholdMps2] for at least
///   [sustainedTurnSamples] samples: cornering lasts, a lane-change twitch does
///   not.
/// * **speedBump** — a *brief* upward `Y_car` impulse (at or above
///   [bumpThresholdMps2] for at most [impulseMaxSamples] samples). The brevity
///   test is what separates a bump from a sustained climb such as a ramp.
/// * **pothole** — the downward mirror (`-Y_car`).
/// * **smoothDrive** — nothing above the calm thresholds
///   ([calmThresholdMps2] / [calmVerticalThresholdMps2]): a genuinely smooth
///   stretch. Reported only when no maneuver fired, so it means "nothing
///   happened", never "and also nothing happened".
///
/// A window may yield more than one maneuver (braking into a corner is real);
/// `MLClassifierIsolate` de-duplicates repeated kinds across overlapping
/// windows. Confidence is a normalised margin past the threshold
/// ([confidenceSpanMps2]), never a claim about the driver.
class HeuristicMotionModel extends MotionModel {
  const HeuristicMotionModel({
    this.hardBrakeThresholdMps2 = 2.5,
    this.hardAccelThresholdMps2 = 2.5,
    this.sharpTurnThresholdMps2 = 2.0,
    this.bumpThresholdMps2 = 3.0,
    this.calmThresholdMps2 = 1.2,
    this.calmVerticalThresholdMps2 = 2.0,
    this.sustainedSamples = 12,
    this.sustainedTurnSamples = 25,
    this.impulseMaxSamples = 20,
    this.confidenceSpanMps2 = 5.0,
  }) : assert(sustainedSamples > 0),
       assert(sustainedTurnSamples > 0),
       assert(impulseMaxSamples > 0),
       assert(confidenceSpanMps2 > 0);

  /// Sustained `Z_car` deceleration that counts as hard braking.
  final double hardBrakeThresholdMps2;

  /// Sustained `Z_car` acceleration that counts as a harsh launch.
  final double hardAccelThresholdMps2;

  /// Sustained `|X_car|` that counts as cornering.
  final double sharpTurnThresholdMps2;

  /// `|Y_car|` impulse that counts as a bump or pothole.
  final double bumpThresholdMps2;

  /// Busiest `|X_car|` / `|Z_car|` a window may reach and still be calm.
  final double calmThresholdMps2;

  /// Busiest `|Y_car|` a window may reach and still be calm — road noise is
  /// larger vertically, so this is looser than [calmThresholdMps2].
  final double calmVerticalThresholdMps2;

  /// Samples at or past a longitudinal threshold before it counts as
  /// sustained (12 = 0.24 s at [MotionWindow.sampleRateHz]).
  final int sustainedSamples;

  /// Samples at or past the lateral threshold before it counts as cornering
  /// (25 = 0.5 s).
  final int sustainedTurnSamples;

  /// Longest vertical excursion still treated as an impulse (20 = 0.4 s).
  final int impulseMaxSamples;

  /// Margin past a threshold that saturates confidence at 1.0.
  final double confidenceSpanMps2;

  @override
  String get id => 'heuristic-v1';

  @override
  List<MotionEventKind> get labels => MotionEventKind.values;

  @override
  List<MotionPrediction> infer(MotionWindow window) {
    if (window.samples.isEmpty) return const <MotionPrediction>[];

    final List<double> lateral = window.lateral;
    final List<double> vertical = window.vertical;
    final List<double> longitudinal = window.longitudinal;
    final List<MotionPrediction> predictions = <MotionPrediction>[];

    // Longitudinal: braking and accelerating are the two signs of Z_car.
    final double deepest = _smallest(longitudinal);
    if (-deepest >= hardBrakeThresholdMps2 &&
        _atOrBelow(longitudinal, -hardBrakeThresholdMps2) >= sustainedSamples) {
      predictions.add(
        MotionPrediction(
          kind: MotionEventKind.hardBrake,
          confidence: _confidence(-deepest - hardBrakeThresholdMps2),
          peakMps2: deepest,
        ),
      );
    }
    final double strongest = _largest(longitudinal);
    if (strongest >= hardAccelThresholdMps2 &&
        _atOrAbove(longitudinal, hardAccelThresholdMps2) >= sustainedSamples) {
      predictions.add(
        MotionPrediction(
          kind: MotionEventKind.hardAccel,
          confidence: _confidence(strongest - hardAccelThresholdMps2),
          peakMps2: strongest,
        ),
      );
    }

    // Lateral: the sign of the largest excursion keeps left and right apart.
    final double hardestTurn = _largestByMagnitude(lateral);
    if (hardestTurn.abs() >= sharpTurnThresholdMps2 &&
        _beyond(lateral, sharpTurnThresholdMps2) >= sustainedTurnSamples) {
      predictions.add(
        MotionPrediction(
          kind: MotionEventKind.sharpTurn,
          confidence: _confidence(hardestTurn.abs() - sharpTurnThresholdMps2),
          peakMps2: hardestTurn,
        ),
      );
    }

    // Vertical: brief upward impulse is a bump, brief downward is a pothole.
    final double upwardImpulse = _largest(vertical);
    final int upwardSamples = _atOrAbove(vertical, bumpThresholdMps2);
    if (upwardImpulse >= bumpThresholdMps2 &&
        upwardSamples >= 1 &&
        upwardSamples <= impulseMaxSamples) {
      predictions.add(
        MotionPrediction(
          kind: MotionEventKind.speedBump,
          confidence: _confidence(upwardImpulse - bumpThresholdMps2),
          peakMps2: upwardImpulse,
        ),
      );
    }
    final double downwardImpulse = _smallest(vertical);
    final int downwardSamples = _atOrBelow(vertical, -bumpThresholdMps2);
    if (downwardImpulse <= -bumpThresholdMps2 &&
        downwardSamples >= 1 &&
        downwardSamples <= impulseMaxSamples) {
      predictions.add(
        MotionPrediction(
          kind: MotionEventKind.pothole,
          confidence: _confidence(-downwardImpulse - bumpThresholdMps2),
          peakMps2: downwardImpulse,
        ),
      );
    }

    if (predictions.isEmpty) {
      // Nothing crossed a threshold: how calm was it, relative to the ceiling
      // of "calm"? The busiest axis decides.
      final double busiest = math.max(
        _largestByMagnitude(lateral).abs() / calmThresholdMps2,
        math.max(
          _largestByMagnitude(longitudinal).abs() / calmThresholdMps2,
          _largestByMagnitude(vertical).abs() / calmVerticalThresholdMps2,
        ),
      );
      predictions.add(
        MotionPrediction(
          kind: MotionEventKind.smoothDrive,
          confidence: (1 - busiest).clamp(0.0, 1.0),
          peakMps2: 0,
        ),
      );
    }

    predictions.sort(
      (MotionPrediction a, MotionPrediction b) =>
          b.confidence.compareTo(a.confidence),
    );
    return predictions;
  }

  /// A margin past a threshold as confidence: saturates at 1.0 within
  /// [confidenceSpanMps2] and never leaves `[0, 1]`.
  double _confidence(double excess) =>
      (excess / confidenceSpanMps2).clamp(0.0, 1.0);

  static double _largest(List<double> values) {
    double best = values.first;
    for (final double value in values) {
      if (value > best) best = value;
    }
    return best;
  }

  static double _smallest(List<double> values) {
    double best = values.first;
    for (final double value in values) {
      if (value < best) best = value;
    }
    return best;
  }

  /// The value with the largest magnitude, keeping its sign.
  static double _largestByMagnitude(List<double> values) {
    double best = values.first;
    for (final double value in values) {
      if (value.abs() > best.abs()) best = value;
    }
    return best;
  }

  static int _atOrAbove(List<double> values, double threshold) {
    int count = 0;
    for (final double value in values) {
      if (value >= threshold) count++;
    }
    return count;
  }

  static int _atOrBelow(List<double> values, double threshold) {
    int count = 0;
    for (final double value in values) {
      if (value <= threshold) count++;
    }
    return count;
  }

  /// Samples whose magnitude reaches [threshold], either sign.
  static int _beyond(List<double> values, double threshold) {
    int count = 0;
    for (final double value in values) {
      if (value.abs() >= threshold) count++;
    }
    return count;
  }
}
