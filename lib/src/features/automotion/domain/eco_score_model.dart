import 'package:flutter/foundation.dart';
import '../../../services/motion_profiler.dart';
import '../../../services/motion_score.dart';

/// Real-time Eco-Driving and Safety Score representation.
@immutable
class EcoScoreModel {
  const EcoScoreModel({
    required this.score,
    required this.band,
    required this.smoothnessPercentage,
    required this.harshAccelCount,
    required this.harshBrakeCount,
    required this.sharpTurnCount,
    required this.totalEvents,
    this.currentGForce = 1.0,
    this.maxLateralGForce = 0.0,
  });

  /// Overall eco-safety score (0-100).
  final int score;

  /// Score band classification (excellent, good, fair, poor).
  final MotionScoreBand band;

  /// Smoothness factor percentage (0-100%).
  final double smoothnessPercentage;

  final int harshAccelCount;
  final int harshBrakeCount;
  final int sharpTurnCount;
  final int totalEvents;

  final double currentGForce;
  final double maxLateralGForce;

  /// Default clean eco-score state for a new trip.
  static const EcoScoreModel clean = EcoScoreModel(
    score: 100,
    band: MotionScoreBand.excellent,
    smoothnessPercentage: 100.0,
    harshAccelCount: 0,
    harshBrakeCount: 0,
    sharpTurnCount: 0,
    totalEvents: 0,
  );

  /// Computes an [EcoScoreModel] from a base [MotionScore] and live telemetry measurements.
  factory EcoScoreModel.fromMotionScore(
    MotionScore motionScore, {
    double currentG = 1.0,
    double maxLatG = 0.0,
  }) {
    final int accelCount =
        motionScore.tallies[DrivingEventType.harshAcceleration] ?? 0;
    final int brakeCount =
        motionScore.tallies[DrivingEventType.harshBraking] ?? 0;
    final int turnCount =
        motionScore.tallies[DrivingEventType.sharpTurn] ?? 0;

    // Smoothness percentage correlates with the clean score ratio.
    final double smoothness = (motionScore.score / 100.0 * 100.0).clamp(0.0, 100.0);

    return EcoScoreModel(
      score: motionScore.score,
      band: motionScore.band,
      smoothnessPercentage: smoothness,
      harshAccelCount: accelCount,
      harshBrakeCount: brakeCount,
      sharpTurnCount: turnCount,
      totalEvents: motionScore.total,
      currentGForce: currentG,
      maxLateralGForce: maxLatG,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EcoScoreModel &&
      other.score == score &&
      other.band == band &&
      other.smoothnessPercentage == smoothnessPercentage &&
      other.harshAccelCount == harshAccelCount &&
      other.harshBrakeCount == harshBrakeCount &&
      other.sharpTurnCount == sharpTurnCount &&
      other.currentGForce == currentGForce &&
      other.maxLateralGForce == maxLateralGForce;

  @override
  int get hashCode => Object.hash(
        score,
        band,
        smoothnessPercentage,
        harshAccelCount,
        harshBrakeCount,
        sharpTurnCount,
        currentGForce,
        maxLateralGForce,
      );
}
