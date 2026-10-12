import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A custom AutoMotion status badge rendered with an animated-looking motion
/// ring and a location pin, using electric blue/mint gradients.
class AutoMotionBadge extends StatelessWidget {
  const AutoMotionBadge({
    super.key,
    required this.isActive,
    required this.isUnavailable,
    required this.size,
  });

  final bool isActive;
  final bool isUnavailable;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AutoMotionBadgePainter(
          isActive: isActive,
          isUnavailable: isUnavailable,
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

class _AutoMotionBadgePainter extends CustomPainter {
  _AutoMotionBadgePainter({
    required this.isActive,
    required this.isUnavailable,
  });

  final bool isActive;
  final bool isUnavailable;

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
  }

  @override
  bool shouldRepaint(covariant _AutoMotionBadgePainter oldDelegate) {
    return oldDelegate.isActive != isActive ||
        oldDelegate.isUnavailable != isUnavailable;
  }
}