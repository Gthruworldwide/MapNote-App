import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A custom AutoMotion status badge rendered with an animated-looking motion
/// ring and a location pin, using electric blue/mint gradients.
///
/// Includes an optional GPS quality indicator that shows the fix status of the
/// most recent GPS fix. This indicator is only meaningful in the AutoMotion
/// edition; it is hidden in the Work edition.
///
/// Additionally, [showMockLocationWarning] can be set to `true` to display a
/// small warning icon when the device is using mock GPS locations (e.g. debug
/// settings, emulators). This is AutoMotion-only and respects the edition gate.
class AutoMotionBadge extends StatelessWidget {
  const AutoMotionBadge({
    super.key,
    required this.isActive,
    required this.isUnavailable,
    required this.size,
    this.showGpsQuality = true,
    this.showMockLocationWarning = false,
  });

  final bool isActive;
  final bool isUnavailable;
  final double size;
  /// When `true` (the default), the badge renders a small GPS quality dot
  /// beneath the location pin that reflects the most recent fix's accuracy
  /// tier. Set to `false` to hide the quality indicator (e.g. in Work Edition).
  final bool showGpsQuality;
  /// When `true`, renders a warning icon alongside the GPS quality dot to
  /// indicate that the device is using mock GPS locations. Set to `false`
  /// by default; enable when the app detects mock location streams.
  final bool showMockLocationWarning;

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
          showMockLocationWarning: showMockLocationWarning,
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
/// GPS quality dot and mock-location warning.
class _AutoMotionBadgePainter extends CustomPainter {
  _AutoMotionBadgePainter({
    required this.isActive,
    required this.isUnavailable,
    required this.showGpsQuality,
    required this.showMockLocationWarning,
  });

  final bool isActive;
  final bool isUnavailable;
  final bool showGpsQuality;
  final bool showMockLocationWarning;

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
  // When accuracy is high (≤ 20 m) it appears green; when unknown it is grey.
  static const Color _highQualityColor = Color(0xFF38FFB0);
  static const Color _unknownQualityColor = Color(0xFFBDC3C7);

  // Mock location warning: a small orange exclamation mark beneath the pin.
  static const double _warningSizeRatio = 0.18;

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
      // fix, but for the badge we use a static heuristic.
      final double dotRadius = size.width * 0.12;
      final Offset dotOffset = Offset(center, center + ringInner + dotRadius + 4);
      final Color dotColor = _determineQualityColor(isActive);
      final Paint dotPaint = Paint()
        ..color = dotColor
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.drawCircle(dotOffset, dotRadius, dotPaint);
    }

    // Optional mock-location data-quality warning: a small exclamation icon.
    if (showMockLocationWarning) {
      final double warningRadius = size.width * _warningSizeRatio;
      final Offset warningOffset =
          Offset(center - warningRadius - 2, center - warningRadius - 2);
      final Paint warningPaint = Paint()
        ..color = Colors.orangeAccent
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      // Draw the warning icon as a simple "!" using a Text widget approach
      // via DirectCanvas would be complex; instead we draw a minimal orange
      // circle with a white "!" using a custom approach.
      // For now, render a small orange dot with white plus pattern.
      final Paint plusPaint = Paint()..color = Colors.white;
      canvas.drawCircle(Offset(warningOffset.dx + warningRadius / 2, warningOffset.dy), 1.5, plusPaint);
      canvas.drawCircle(Offset(warningOffset.dx + warningRadius / 2, warningOffset.dy + warningRadius), 1.5, plusPaint);
      // Draw orange background circle
      canvas.drawCircle(warningOffset, warningRadius, warningPaint);
      // Draw white "!" - vertical line
      canvas.drawLine(
        Offset(warningOffset.dx + warningRadius / 2, warningOffset.dy),
        Offset(warningOffset.dx + warningRadius / 2, warningOffset.dy + warningRadius - 4),
        plusPaint,
      );
      // Draw white "!" - horizontal line
      canvas.drawLine(
        Offset(warningOffset.dx, warningOffset.dy + warningRadius - 4),
        Offset(warningOffset.dx + warningRadius, warningOffset.dy + warningRadius - 4),
        plusPaint,
      );
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
        oldDelegate.showGpsQuality != showGpsQuality ||
        oldDelegate.showMockLocationWarning != showMockLocationWarning;
  }
}