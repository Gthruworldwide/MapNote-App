import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/polyline_smoother.dart';

/// Paints the recorded trip route with [CustomPaint] — no map SDK and no
/// network call, so the mini-map also works in airplane mode and in tests.
///
/// The drawing language matches the place-detail route preview: a
/// paper-like tinted background, a faint grid, and the route drawn as a
/// solid primary line with a soft halo, anchored by a "start" dot and an
/// "end" pin. The vertices are expected to already be jitter-smoothed (the
/// card reads `AutoMotionService.smoothedPath`).
class TripPathPainter extends CustomPainter {
  const TripPathPainter({
    required this.points,
    required this.scheme,
    required this.isDark,
    this.routeVisible = true,
  });

  /// The smoothed route vertices, in drive order.
  final List<RoutePoint> points;

  final ColorScheme scheme;

  /// Whether the surrounding theme is dark (selects the background tint).
  final bool isDark;

  /// Whether to draw the route itself (line, start dot, end pin).
  ///
  /// `false` turns the painter into the pure tinted-grid backdrop the tile
  /// map sits on: the real map draws its own polyline and markers, and only
  /// the grid needs to survive underneath for the offline fallback. With
  /// [routeVisible] `true` (the default) the painter renders the complete
  /// offline mini-map, exactly as it always has.
  final bool routeVisible;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final RRect rounded = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(AppRadii.input),
    );
    canvas.drawRRect(
      rounded,
      Paint()
        ..color = isDark
            ? scheme.surfaceContainerHighest
            : scheme.primary.withValues(alpha: 0.04),
    );

    canvas.save();
    canvas.clipRRect(rounded);
    _paintGrid(canvas, size);

    if (!routeVisible || points.isEmpty) {
      canvas.restore();
      return;
    }

    // Equirectangular projection with the longitude scaled by the mean
    // latitude (same projection as the route preview), fitted to the whole
    // path with a uniform scale so the shape never stretches.
    double sumLat = 0;
    for (final RoutePoint point in points) {
      sumLat += point.latitude;
    }
    final double meanLat = sumLat / points.length;
    final double lonScale = math
        .cos(meanLat * math.pi / 180)
        .abs()
        .clamp(0.05, 1.0);

    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double minY = double.infinity;
    double maxY = double.negativeInfinity;
    for (final RoutePoint point in points) {
      final double x = point.longitude * lonScale;
      final double y = -point.latitude;
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }
    // Keep a sensible zoom when the route is a single dot (or sub-metre).
    final double spanX = math.max(maxX - minX, 0.0009);
    final double spanY = math.max(maxY - minY, 0.0009);
    const double pad = 28;
    final double availW = math.max(size.width - pad * 2, 1);
    final double availH = math.max(size.height - pad * 2, 1);
    final double scale = math.min(availW / spanX, availH / spanY);
    final double centerX = (minX + maxX) / 2;
    final double centerY = (minY + maxY) / 2;

    Offset project(RoutePoint point) => Offset(
      size.width / 2 + (point.longitude * lonScale - centerX) * scale,
      size.height / 2 + (-point.latitude - centerY) * scale,
    );

    if (points.length > 1) {
      final Offset first = project(points.first);
      final Path path = Path()..moveTo(first.dx, first.dy);
      for (final RoutePoint point in points.skip(1)) {
        final Offset offset = project(point);
        path.lineTo(offset.dx, offset.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = scheme.primary.withValues(alpha: 0.16),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = scheme.primary.withValues(alpha: 0.90),
      );
    }

    final Offset start = project(points.first);
    final Offset end = project(points.last);
    _paintDeviceDot(canvas, start);
    if (points.length > 1) _paintPin(canvas, end);
    canvas.restore();
  }

  void _paintGrid(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: isDark ? 0.9 : 0.7)
      ..strokeWidth = 1;
    const double step = 34;
    for (double x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  /// The blue "where the trip started" dot, with a soft halo.
  void _paintDeviceDot(Canvas canvas, Offset center) {
    canvas.drawCircle(
      center,
      13,
      Paint()..color = scheme.primary.withValues(alpha: 0.16),
    );
    canvas.drawCircle(center, 6.5, Paint()..color = scheme.primary);
    canvas.drawCircle(center, 2.6, Paint()..color = Colors.white);
  }

  /// The "where the trip ended" pin, anchored so its tip sits on the vertex.
  void _paintPin(Canvas canvas, Offset anchor) {
    const double s = 0.82;
    final Offset head = Offset(anchor.dx, anchor.dy - 11 * s);
    canvas.drawCircle(
      head,
      15 * s,
      Paint()..color = scheme.error.withValues(alpha: 0.16),
    );
    final Path tail = Path()
      ..moveTo(anchor.dx - 5.6 * s, head.dy + 4.5 * s)
      ..lineTo(anchor.dx + 5.6 * s, head.dy + 4.5 * s)
      ..lineTo(anchor.dx, anchor.dy + 1.5 * s)
      ..close();
    canvas.drawPath(tail, Paint()..color = scheme.error);
    canvas.drawCircle(head, 7.6 * s, Paint()..color = scheme.error);
    canvas.drawCircle(head, 3 * s, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant TripPathPainter old) =>
      old.isDark != isDark ||
      old.scheme != scheme ||
      old.routeVisible != routeVisible ||
      !listEquals(old.points, points);
}
