import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:motion_smooth/motion_smooth.dart';
import '../../domain/anti_gravity_models.dart';
import '../../domain/vector3d.dart';

/// Interactive Canvas visualizer that displays raw GPS, motion_smooth path,
/// and Anti-Gravity transformed vectors.
class AntiGravityVisualizer extends StatelessWidget {
  final List<RoutePoint> rawPoints;
  final List<RoutePoint> smoothedPoints;
  final List<RoutePoint> antiGravityPoints;
  final AntiGravityState? currentTelemetry;

  const AntiGravityVisualizer({
    super.key,
    required this.rawPoints,
    required this.smoothedPoints,
    required this.antiGravityPoints,
    this.currentTelemetry,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: const Color(0xFF0F172A), // Tactical Slate 900
        child: Stack(
          children: [
            // Custom Painter for Trajectories
            Positioned.fill(
              child: CustomPaint(
                painter: _TrajectoryPainter(
                  rawPoints: rawPoints,
                  smoothedPoints: smoothedPoints,
                  antiGravityPoints: antiGravityPoints,
                  currentTelemetry: currentTelemetry,
                ),
              ),
            ),

            // Top HUD Overlay: Legend & Lift Altitude
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Trajectory Legend
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildLegendItem(const Color(0xFFEF4444), 'Raw GPS'),
                        const SizedBox(width: 10),
                        _buildLegendItem(const Color(0xFF38BDF8), 'motion_smooth'),
                        const SizedBox(width: 10),
                        _buildLegendItem(const Color(0xFF10B981), 'Anti-Gravity'),
                      ],
                    ),
                  ),

                  // Altitude Offset Badge
                  if (currentTelemetry != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.arrow_upward,
                              size: 14, color: Color(0xFF10B981)),
                          const SizedBox(width: 4),
                          Text(
                            'Lift: ${currentTelemetry!.displacementM.z.toStringAsFixed(1)}m',
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Force Vector Mini-Compass (Bottom Left)
            if (currentTelemetry != null)
              Positioned(
                bottom: 12,
                left: 12,
                child: _buildVectorCompass(currentTelemetry!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildVectorCompass(AntiGravityState state) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'FORCE VECTOR HUD',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 9,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 70,
            height: 70,
            child: CustomPaint(
              painter: _VectorCompassPainter(
                netForce: state.netForce,
                accel: state.accelerationVector,
                antiG: state.antiGravityVector,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrajectoryPainter extends CustomPainter {
  final List<RoutePoint> rawPoints;
  final List<RoutePoint> smoothedPoints;
  final List<RoutePoint> antiGravityPoints;
  final AntiGravityState? currentTelemetry;

  _TrajectoryPainter({
    required this.rawPoints,
    required this.smoothedPoints,
    required this.antiGravityPoints,
    this.currentTelemetry,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    if (rawPoints.isEmpty) return;

    // Compute bounding box
    double minLat = rawPoints.first.latitude;
    double maxLat = rawPoints.first.latitude;
    double minLng = rawPoints.first.longitude;
    double maxLng = rawPoints.first.longitude;

    for (final p in rawPoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final double latSpan = math.max(0.0008, maxLat - minLat);
    final double lngSpan = math.max(0.0008, maxLng - minLng);

    const double padding = 40.0;
    final double plotWidth = size.width - (padding * 2);
    final double plotHeight = size.height - (padding * 2);

    Offset toOffset(RoutePoint point) {
      final double normalizedX = (point.longitude - minLng) / lngSpan;
      final double normalizedY = (point.latitude - minLat) / latSpan;
      return Offset(
        padding + normalizedX * plotWidth,
        size.height - (padding + normalizedY * plotHeight),
      );
    }

    // 1. Draw Raw GPS Path (Red dashed/jittered line & dots)
    final rawPaint = Paint()
      ..color = const Color(0xFFEF4444).withValues(alpha: 0.4)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final rawDotPaint = Paint()
      ..color = const Color(0xFFEF4444).withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final rawPath = Path();
    for (int i = 0; i < rawPoints.length; i++) {
      final pt = toOffset(rawPoints[i]);
      if (i == 0) {
        rawPath.moveTo(pt.dx, pt.dy);
      } else {
        rawPath.lineTo(pt.dx, pt.dy);
      }
      canvas.drawCircle(pt, 1.5, rawDotPaint);
    }
    canvas.drawPath(rawPath, rawPaint);

    // 2. Draw motion_smooth Smoothed Path (Sky Blue smooth curve)
    if (smoothedPoints.isNotEmpty) {
      final smoothPaint = Paint()
        ..color = const Color(0xFF38BDF8)
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final smoothPath = Path();
      for (int i = 0; i < smoothedPoints.length; i++) {
        final pt = toOffset(smoothedPoints[i]);
        if (i == 0) {
          smoothPath.moveTo(pt.dx, pt.dy);
        } else {
          smoothPath.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(smoothPath, smoothPaint);
    }

    // 3. Draw Anti-Gravity Vector Path (Emerald Green Glowing Trajectory)
    if (antiGravityPoints.isNotEmpty) {
      final glowPaint = Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: 0.3)
        ..strokeWidth = 6.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final antiGPaint = Paint()
        ..color = const Color(0xFF10B981)
        ..strokeWidth = 2.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final antiGPath = Path();
      for (int i = 0; i < antiGravityPoints.length; i++) {
        final pt = toOffset(antiGravityPoints[i]);
        if (i == 0) {
          antiGPath.moveTo(pt.dx, pt.dy);
        } else {
          antiGPath.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(antiGPath, glowPaint);
      canvas.drawPath(antiGPath, antiGPaint);
    }

    // 4. Draw Current Vehicle Entity Marker
    if (smoothedPoints.isNotEmpty) {
      final currentPos = toOffset(smoothedPoints.last);
      final double headingRad =
          (currentTelemetry?.heading ?? 0.0) * math.pi / 180.0;

      // Outer Pulse Ring
      final pulsePaint = Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(currentPos, 14, pulsePaint);

      // Core Marker
      final corePaint = Paint()
        ..color = const Color(0xFF10B981)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(currentPos, 6, corePaint);

      // Heading Chevron Arrow
      final arrowPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final arrowTip = Offset(
        currentPos.dx + 16 * math.sin(headingRad),
        currentPos.dy - 16 * math.cos(headingRad),
      );
      canvas.drawLine(currentPos, arrowTip, arrowPaint);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1.0;

    const double step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrajectoryPainter oldDelegate) => true;
}

class _VectorCompassPainter extends CustomPainter {
  final Vector3D netForce;
  final Vector3D accel;
  final Vector3D antiG;

  _VectorCompassPainter({
    required this.netForce,
    required this.accel,
    required this.antiG,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Background dial
    final dialPaint = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius - 2, dialPaint);
    canvas.drawCircle(center, radius / 2, dialPaint);

    // Crosshairs
    canvas.drawLine(
        Offset(center.dx, 2), Offset(center.dx, size.height - 2), dialPaint);
    canvas.drawLine(
        Offset(2, center.dy), Offset(size.width - 2, center.dy), dialPaint);

    // Draw net force vector arrow
    final double netScale = math.min(radius - 4, (netForce.length / 1000.0) * 4);
    if (netScale > 1.0) {
      final netNorm = netForce.normalize();
      final arrowEnd = Offset(
        center.dx + netNorm.x * netScale,
        center.dy - netNorm.y * netScale,
      );

      final forcePaint = Paint()
        ..color = const Color(0xFF10B981)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(center, arrowEnd, forcePaint);
      canvas.drawCircle(arrowEnd, 3, forcePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _VectorCompassPainter oldDelegate) => true;
}
