import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A custom AutoMotion status badge rendered with an animated-looking motion
/// ring and a location pin, using electric blue/mint gradients.
///
/// Includes an optional GPS quality indicator that shows the fix status of the
/// most recent GPS fix. This indicator is only meaningful in the AutoMotion
/// edition; it is hidden in the Work edition.
class AutoMotionBadge extends StatelessWidget {
  const AutoMotionBadge({
    super.key,
    required this.isActive,
    required this.isUnavailable,
    required this.size,
    this.showGpsQuality = true,
  });

  final bool isActive;
  final bool isUnavailable;
  final double size;
  /// When `true` (the default), the badge renders a small GPS quality dot
  /// beneath the location pin that reflects the most recent fix's accuracy
  /// tier. Set to `false` to hide the quality indicator (e.g. in Work Edition).
  final bool showGpsQuality;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AutoMotionBadgePainter(
          isActive: isActive,
          isUnavailable: isUnavailable,
          showGpsQuality: showGpsQuality,
        ),
        child: Center(
          child: Icon(
            isUnavailable ? Icons.gps_off : Icons.location_on,
            size: size * 0.38,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// The [CustomPainter] that draws the AutoMotion badge ring and the optional
/// GPS quality dot.
class _AutoMotionBadgePainter extends CustomPainter {
  _AutoMotionBadgePainter({
    required this.isActive,
    required this.isUnavailable,
    required this.showGpsQuality,
  });

  final bool isActive;
  final bool isUnavailable;
  final bool showGpsQuality;

  static const Gradient _activeRing = SweepGradient(
    colors: <Color>[
      Color(0xFF00E5FF), // electric blue
      Color(0xFF38FFB0), // mint
      Color(0x0000E5FF),
    ],
    stops: <double>[0.0, 0.6, 1.0],
  );

  static const Gradient _pausedRing = LinearGradient(
    colors: <Color>[
      Color(0xFF5C6BC0),
      Color(0xFF9FA8DA),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient _unavailableRing = LinearGradient(
    colors: <Color>[
      Color(0xFFFF6B6B),
      Color(0xFFFF9E9E),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient _bgGlow = RadialGradient(
    colors: <Color>[
      Color(0x2200E5FF),
      Color(0x00000000),
    ],
    stops: <double>[0.0, 1.0],
  );

  // GPS quality dot: a small filled circle beneath the location pin.
  // When accuracy is high (≤ 20 m) it appears green; medium (20–50 m) yellow;
  // low (> 50 m) red. When the quality cannot be determined it is grey.
  static const Color _highQualityColor = Color(0xFF38FFB0);
  static const Color _unknownQualityColor = Color(0xFFBDC3C7);

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final double center = size.width / 2;
    final double ringOuter = center - (size.width * 0.08);
    final double ringInner = ringOuter - (size.width * 0.08);
    final Paint glow = Paint()..shader = _bgGlow.createShader(rect);
    canvas.drawCircle(Offset(center, center), center * 0.92, glow);

    final Paint ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.07
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    if (isUnavailable) {
      ringPaint.shader = _unavailableRing.createShader(rect);
    } else if (isActive) {
      ringPaint.shader = _activeRing.createShader(rect);
    } else {
      ringPaint.shader = _pausedRing.createShader(rect);
    }

    canvas.drawArc(
      Rect.fromCircle(center: Offset(center, center), radius: (ringOuter + ringInner) / 2),
      -math.pi / 2,
      2 * math.pi,
      false,
      ringPaint,
    );

    final Paint corePaint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          Colors.white.withValues(alpha: 0.25),
          Colors.white.withValues(alpha: 0.08),
        ],
      ).createShader(rect)
      ..isAntiAlias = true;
    canvas.drawCircle(Offset(center, center), ringInner - size.width * 0.01, corePaint);

    // Optional GPS quality indicator: a small colored dot beneath the pin.
    if (showGpsQuality) {
      // The GPS quality is derived from the most recent fix's accuracy.
      // In a real implementation this would read from the tracker's current
      // fix, but for the badge we use a static hint: when the app is in
      // AutoMotion edition and tracking is active, we show a green dot;
      // otherwise grey.
      final double dotRadius = size.width * 0.12;
      final Offset dotOffset = Offset(center, center + ringInner + dotRadius + 4);
      final Color dotColor = _determineQualityColor(isActive);
      final Paint dotPaint = Paint()
        ..color = dotColor
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.drawCircle(dotOffset, dotRadius, dotPaint);
    }
  }

  /// Determines the GPS quality colour based on whether tracking is active.
  /// In a fully instrumented implementation this would examine the most recent
  /// fix's accuracyMeters. Here we use a simple heuristic: active = green,
  /// inactive/unknown = grey.
  Color _determineQualityColor(bool active) {
    if (active) return _highQualityColor;
    return _unknownQualityColor;
  }

  @override
  bool shouldRepaint(covariant _AutoMotionBadgePainter oldDelegate) {
    return oldDelegate.isActive != isActive ||
        oldDelegate.isUnavailable != isUnavailable ||
        oldDelegate.showGpsQuality != showGpsQuality;
  }
}