import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../services/motion_score.dart';

/// A circular gauge rendering the Eco-Driving score (0-100) with color bands.
class ScoreGaugeWidget extends StatelessWidget {
  const ScoreGaugeWidget({
    super.key,
    required this.score,
    required this.band,
    this.size = 140.0,
    this.strokeWidth = 12.0,
  });

  final int score;
  final MotionScoreBand band;
  final double size;
  final double strokeWidth;

  Color _bandColor(ThemeData theme) {
    switch (band) {
      case MotionScoreBand.excellent:
        return const Color(0xFF2E7D32); // Green
      case MotionScoreBand.good:
        return const Color(0xFF66BB6A); // Light Green
      case MotionScoreBand.fair:
        return const Color(0xFFFBC02D); // Amber
      case MotionScoreBand.poor:
        return const Color(0xFFC62828); // Red
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = _bandColor(theme);
    final trackColor = theme.colorScheme.surfaceContainerHighest;

    return Semantics(
      label: 'Eco-driving score: $score out of 100',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(size, size),
              painter: _GaugePainter(
                progress: (score / 100.0).clamp(0.0, 1.0),
                activeColor: activeColor,
                trackColor: trackColor,
                strokeWidth: strokeWidth,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$score',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: activeColor,
                  ),
                ),
                Text(
                  '/ 100',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.progress,
    required this.activeColor,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color activeColor;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    const startAngle = 0.75 * math.pi; // Start at bottom-left
    const sweepAngle = 1.5 * math.pi; // 270 degree arc

    // Draw track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // Draw active arc
    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * progress,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
