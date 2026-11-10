import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routenote/src/features/automotion/domain/eco_score_model.dart';
import 'package:routenote/src/features/automotion/widgets/eco_driving_dashboard_card.dart';
import 'package:routenote/src/features/automotion/widgets/score_gauge_widget.dart';
import 'package:routenote/src/services/motion_score.dart';
import 'package:routenote/src/services/motion_profiler.dart';
import 'package:routenote/l10n/generated/app_localizations.dart';

void main() {
  test('EcoScoreModel computes scores and metrics correctly from MotionScore', () {
    final motionScore = MotionScore(
      score: 85,
      band: MotionScoreBand.good,
      total: 3,
      tallies: {
        DrivingEventType.harshAcceleration: 1,
        DrivingEventType.harshBraking: 1,
        DrivingEventType.sharpTurn: 1,
      },
    );

    final ecoScore = EcoScoreModel.fromMotionScore(
      motionScore,
      currentG: 1.25,
      maxLatG: 0.35,
    );

    expect(ecoScore.score, 85);
    expect(ecoScore.band, MotionScoreBand.good);
    expect(ecoScore.smoothnessPercentage, 85.0);
    expect(ecoScore.harshAccelCount, 1);
    expect(ecoScore.harshBrakeCount, 1);
    expect(ecoScore.sharpTurnCount, 1);
    expect(ecoScore.currentGForce, 1.25);
    expect(ecoScore.maxLateralGForce, 0.35);
  });

  testWidgets('ScoreGaugeWidget renders score and arc progress', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ScoreGaugeWidget(
            score: 92,
            band: MotionScoreBand.excellent,
          ),
        ),
      ),
    );

    expect(find.text('92'), findsOneWidget);
    expect(find.text('/ 100'), findsOneWidget);
  });

  testWidgets('EcoDrivingDashboardCard renders metrics and feedback', (tester) async {
    const ecoScore = EcoScoreModel(
      score: 95,
      band: MotionScoreBand.excellent,
      smoothnessPercentage: 95.0,
      harshAccelCount: 0,
      harshBrakeCount: 0,
      sharpTurnCount: 1,
      totalEvents: 1,
      currentGForce: 1.05,
      maxLateralGForce: 0.20,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: EcoDrivingDashboardCard(ecoScore: ecoScore),
          ),
        ),
      ),
    );

    expect(find.text('95'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget); // sharp turn
    expect(find.text('95%'), findsOneWidget);
    expect(find.textContaining('1.05 G'), findsOneWidget);
  });
}
