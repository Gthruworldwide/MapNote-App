import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/geo_distance.dart';
import '../../../core/utils/haptics.dart';
import '../../../data/models/place.dart';
import '../../../providers/app_providers.dart';
import '../../../services/location_service.dart';

/// A compact, fully offline "route preview" for a saved place.
///
/// The map is painted with [CustomPaint] — there is no map SDK and no network
/// call — so the preview also works in airplane mode and in tests. The saved
/// place is always drawn; when the device can be located the current position,
/// a dashed great-circle route and an estimated distance are added on top.
///
/// Tapping the card opens a taller preview in a bottom sheet. Everything that
/// touches or moves the card fires the shared [Haptics] tap, and the entrance
/// animation is skipped when the platform asks for reduced motion.
class RoutePreviewCard extends ConsumerStatefulWidget {
  const RoutePreviewCard({
    super.key,
    required this.place,
    this.height,
    this.interactive = true,
  });

  final Place place;

  /// Height of the painted map. The bottom-sheet variant uses a taller map.
  final double? height;

  /// When false the card is informational only (used inside the sheet).
  final bool interactive;

  @override
  ConsumerState<RoutePreviewCard> createState() => _RoutePreviewCardState();
}

class _RoutePreviewCardState extends ConsumerState<RoutePreviewCard>
    with SingleTickerProviderStateMixin {
  static const double _mapHeight = 168;
  static const double _sheetMapHeight = 260;

  _DeviceFix? _current;
  bool _unavailable = false;
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (AppMotion.reduceMotion(context)) {
        _entrance.value = 1;
      } else {
        _entrance.forward();
      }
      _locate();
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  /// Best-effort device fix. Never throws: a denied permission or a missing
  /// platform channel simply means the preview shows the saved place alone.
  Future<void> _locate() async {
    try {
      final LocationResult result =
          await ref.read(locationServiceProvider).determinePosition();
      if (!mounted) return;
      setState(() {
        if (result is LocationSuccess) {
          _current = _DeviceFix(result.latitude, result.longitude);
        } else {
          _unavailable = true;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _unavailable = true;
      });
    }
  }

  double? get _distanceKm {
    final _DeviceFix? current = _current;
    if (current == null) return null;
    return haversineKm(
      current.latitude,
      current.longitude,
      widget.place.latitude,
      widget.place.longitude,
    );
  }

  static String _formatDistance(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
  }

  Future<void> _openFullPreview(BuildContext context) async {
    Haptics.light();
    final AppLocalizations l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // Design-system motion (250ms ease-out), instant under Reduce Motion.
      sheetAnimationStyle: AppMotion.sheetAnimationStyle(context),
      builder: (BuildContext sheetContext) => SheetEntrance(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  l10n.mapPreview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                RoutePreviewCard(
                  place: widget.place,
                  height: _sheetMapHeight,
                  interactive: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double? distanceKm = _distanceKm;

    final Widget map = Semantics(
      image: true,
      label: l10n.mapPreview,
      child: AnimatedBuilder(
        animation: _entrance,
        builder: (BuildContext context, Widget? child) => CustomPaint(
          painter: _RouteMapPainter(
            targetLat: widget.place.latitude,
            targetLon: widget.place.longitude,
            currentLat: _current?.latitude,
            currentLon: _current?.longitude,
            scheme: scheme,
            progress: _entrance.value,
            isDark: theme.brightness == Brightness.dark,
          ),
        ),
      ),
    );

    return Card(
      child: InkWell(
        onTap: widget.interactive ? () => _openFullPreview(context) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.route_outlined, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.routePreview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (distanceKm != null)
                    _DistancePill(
                      label: l10n.distanceAway(_formatDistance(distanceKm)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.input),
                child: SizedBox(
                  height: widget.height ?? _mapHeight,
                  width: double.infinity,
                  child: map,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  _LegendItem(
                    color: scheme.primary,
                    label: l10n.currentLocationMarker,
                  ),
                  const SizedBox(width: 18),
                  _LegendItem(
                    color: scheme.error,
                    label: l10n.savedLocationMarker,
                    pin: true,
                  ),
                ],
              ),
              if (_unavailable) ...<Widget>[
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.location_disabled_outlined,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.enableLocationForRoute,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A lightweight lat/lng pair for the current device fix.
class _DeviceFix {
  const _DeviceFix(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

/// The estimated-distance chip in the preview header.
class _DistancePill extends StatelessWidget {
  const _DistancePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.20)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A marker swatch + caption used under the map.
class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    this.pin = false,
  });

  final Color color;
  final String label;
  final bool pin;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (pin)
            Icon(Icons.place, size: 14, color: color)
          else
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the offline preview: a paper-like grid, the dashed route, the device
/// dot and the saved-place pin.
class _RouteMapPainter extends CustomPainter {
  _RouteMapPainter({
    required this.targetLat,
    required this.targetLon,
    required this.currentLat,
    required this.currentLon,
    required this.scheme,
    required this.progress,
    required this.isDark,
  });

  final double targetLat;
  final double targetLon;
  final double? currentLat;
  final double? currentLon;
  final ColorScheme scheme;
  final double progress;
  final bool isDark;

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

    // Equirectangular projection, longitude scaled by the mean latitude so
    // northern/southern places are not stretched.
    final double? cLat = currentLat;
    final double? cLon = currentLon;
    final double meanLat = cLat == null ? targetLat : (cLat + targetLat) / 2;
    final double lonScale = math
        .cos(meanLat * math.pi / 180)
        .abs()
        .clamp(0.05, 1.0);

    final double tx = targetLon * lonScale;
    final double ty = -targetLat;
    final double? cx = cLon == null ? null : cLon * lonScale;
    final double? cy = cLat == null ? null : -cLat;

    double minX = tx;
    double maxX = tx;
    double minY = ty;
    double maxY = ty;
    if (cx != null && cy != null) {
      minX = math.min(minX, cx);
      maxX = math.max(maxX, cx);
      minY = math.min(minY, cy);
      maxY = math.max(maxY, cy);
    }
    // Keep a sensible zoom when the two points coincide (or when only the
    // saved place is known).
    final double spanX = math.max(maxX - minX, 0.0009);
    final double spanY = math.max(maxY - minY, 0.0009);
    const double pad = 46;
    final double availW = math.max(size.width - pad * 2, 1);
    final double availH = math.max(size.height - pad * 2, 1);
    final double scale = math.min(availW / spanX, availH / spanY);
    final double centerX = (minX + maxX) / 2;
    final double centerY = (minY + maxY) / 2;

    Offset project(double wx, double wy) => Offset(
      size.width / 2 + (wx - centerX) * scale,
      size.height / 2 + (wy - centerY) * scale,
    );

    final Offset targetPoint = project(tx, ty);
    final Offset? currentPoint = (cx == null || cy == null)
        ? null
        : project(cx, cy);

    if (currentPoint != null) {
      _paintRoute(canvas, currentPoint, targetPoint);
      _paintDeviceDot(canvas, currentPoint);
    }
    _paintPin(canvas, targetPoint);
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

  void _paintRoute(Canvas canvas, Offset from, Offset to) {
    final Offset delta = to - from;
    final double length = delta.distance;
    final Offset mid = Offset.lerp(from, to, 0.5)!;
    final Offset normal = length == 0
        ? Offset.zero
        : Offset(-delta.dy / length, delta.dx / length);
    final Offset control = mid + normal * (length * 0.18);
    final Path path = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy);

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..color = scheme.primary.withValues(alpha: 0.16),
    );
    _drawDashed(
      canvas,
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = scheme.primary.withValues(alpha: 0.90),
    );
  }

  /// Draws [path] as dashes, trimmed to the current [progress] so the route
  /// appears to draw itself in.
  void _drawDashed(Canvas canvas, Path path, Paint paint) {
    const double dash = 9;
    const double gap = 7;
    for (final ui.PathMetric metric in path.computeMetrics()) {
      final double limit = metric.length * progress.clamp(0.0, 1.0);
      double distance = 0;
      while (distance < limit) {
        final double next = math.min(distance + dash, limit);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  /// The blue "you are here" dot, with a soft halo.
  void _paintDeviceDot(Canvas canvas, Offset center) {
    canvas.drawCircle(
      center,
      13,
      Paint()..color = scheme.primary.withValues(alpha: 0.16 * progress),
    );
    canvas.drawCircle(center, 6.5, Paint()..color = scheme.primary);
    canvas.drawCircle(center, 2.6, Paint()..color = Colors.white);
  }

  /// The saved-place pin, anchored so its tip sits exactly on the place.
  void _paintPin(Canvas canvas, Offset anchor) {
    final double s = 0.82 + 0.18 * progress.clamp(0.0, 1.0);
    final Offset head = Offset(anchor.dx, anchor.dy - 11 * s);
    canvas.drawCircle(
      head,
      15 * s,
      Paint()..color = scheme.error.withValues(alpha: 0.16 * progress),
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
  bool shouldRepaint(covariant _RouteMapPainter old) =>
      old.targetLat != targetLat ||
      old.targetLon != targetLon ||
      old.currentLat != currentLat ||
      old.currentLon != currentLon ||
      old.progress != progress ||
      old.isDark != isDark ||
      old.scheme != scheme;
}
