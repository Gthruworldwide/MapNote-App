import 'package:flutter/material.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../services/motion_score.dart';
import '../domain/eco_score_model.dart';
import 'score_gauge_widget.dart';

/// A dashboard card presenting the Eco-Driving & Safety Score, event tallies,
/// and live G-Force metrics.
class EcoDrivingDashboardCard extends StatelessWidget {
  const EcoDrivingDashboardCard({
    super.key,
    required this.ecoScore,
  });

  final EcoScoreModel ecoScore;

  String _feedbackText(AppLocalizations l10n) {
    switch (ecoScore.band) {
      case MotionScoreBand.excellent:
        return l10n.scoreExcellent;
      case MotionScoreBand.good:
        return l10n.scoreGood;
      case MotionScoreBand.fair:
        return l10n.scoreFair;
      case MotionScoreBand.poor:
        return l10n.scorePoor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      container: true,
      label: '${l10n.motionSummaryTitle}, score: ${ecoScore.score} out of 100, ${_feedbackText(l10n)}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.eco_rounded, color: scheme.primary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    l10n.motionSummaryTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _feedbackText(l10n),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: ScoreGaugeWidget(
                  score: ecoScore.score,
                  band: ecoScore.band,
                ),
              ),
              const SizedBox(height: 20),
              // Event metrics grid
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _MetricItem(
                    icon: Icons.speed,
                    label: l10n.harshAcceleration,
                    value: '${ecoScore.harshAccelCount}x',
                  ),
                  _MetricItem(
                    icon: Icons.aod,
                    label: l10n.harshBraking,
                    value: '${ecoScore.harshBrakeCount}x',
                  ),
                  _MetricItem(
                    icon: Icons.turn_right_rounded,
                    label: l10n.sharpTurn,
                    value: '${ecoScore.sharpTurnCount}x',
                  ),
                  _MetricItem(
                    icon: Icons.check_circle_outline,
                    label: 'Smoothness',
                    value: '${ecoScore.smoothnessPercentage.toInt()}%',
                  ),
                ],
              ),
              const Divider(height: 24),
              // Real-Time G-Force Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${l10n.telemetryGForce}: ${ecoScore.currentGForce.toStringAsFixed(2)} G',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    'Max Lat G: ${ecoScore.maxLateralGForce.toStringAsFixed(2)} G',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
