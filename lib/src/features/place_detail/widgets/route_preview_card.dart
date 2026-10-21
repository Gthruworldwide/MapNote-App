import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/geo_distance.dart';
import '../../../core/utils/haptics.dart';
import '../../../data/models/place.dart';
import '../../../providers/app_providers.dart';
import '../../../services/location_service.dart';
import '../../../services/offline_tile_cache_strategy.dart';
import '../../../widgets/map_attribution_chip.dart';

/// A compact route preview for a saved place, drawn over real OpenStreetMap
/// tiles — the same `flutter_map` stack the AutoMotion dashboard uses.
///
/// The saved place is always marked (red pin); when the device can be located
/// the current position (blue dot), the straight connection between the two
/// and an estimated distance are added on top. The camera auto-fits both
/// markers, so the pair is framed without any user interaction.
///
/// Tiles need a network, but the frame does not: the tinted grid the preview
/// has always painted stays underneath as the offline backdrop, so with no
/// connectivity (or before the first tile lands) both markers and the path
/// still render. The tile source is injected through
/// [routeTileProviderProvider], so tests never reach the network.
///
/// Tapping the card opens a taller copy in a bottom sheet. Everything that
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
        // The map subtree is passed as `child`, so the entrance fade repaints
        // the layer without rebuilding the tiles or the markers.
        builder: (BuildContext context, Widget? child) =>
            Opacity(opacity: _entrance.value.clamp(0.0, 1.0), child: child),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Offline backdrop (the preview's original grid): it shows through
            // wherever no tile has loaded, so the markers and path — pure
            // widget layers that need no network — never sit on a blank box.
            CustomPaint(
              painter: _PreviewGridPainter(
                scheme: scheme,
                isDark: theme.brightness == Brightness.dark,
              ),
            ),
            _RoutePreviewMap(
              place: widget.place,
              currentLat: _current?.latitude,
              currentLon: _current?.longitude,
            ),
          ],
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

/// The offline backdrop: the paper-like grid the preview has always painted,
/// now layered *under* the real tiles. It shows through wherever no tile has
/// loaded (airplane mode, first paint, an OSM outage) instead of leaving a
/// blank box.
class _PreviewGridPainter extends CustomPainter {
  _PreviewGridPainter({required this.scheme, required this.isDark});

  final ColorScheme scheme;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    // The card's ClipRRect already rounds the corners, so the backdrop fills
    // the whole box; the real tiles cover it the moment they arrive.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = isDark
            ? scheme.surfaceContainerHighest
            : scheme.primary.withValues(alpha: 0.04),
    );
    _paintGrid(canvas, size);
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

  @override
  bool shouldRepaint(covariant _PreviewGridPainter old) =>
      old.isDark != isDark || old.scheme != scheme;
}

/// The real-tile preview: OpenStreetMap raster tiles under a straight
/// connection line, a blue "you are here" dot and a red pin on the saved
/// place.
///
/// Mirrors `RouteMapView`'s language — a transparent background over the
/// offline grid, an injectable [TileProvider] (tests must never reach the
/// network) and the OSM attribution chip the tile usage policy requires. The
/// camera frames every known point on first paint and again whenever the
/// asynchronous device fix, or the place itself, changes.
class _RoutePreviewMap extends ConsumerStatefulWidget {
  const _RoutePreviewMap({
    required this.place,
    this.currentLat,
    this.currentLon,
  });

  final Place place;
  final double? currentLat;
  final double? currentLon;

  @override
  ConsumerState<_RoutePreviewMap> createState() => _RoutePreviewMapState();
}

class _RoutePreviewMapState extends ConsumerState<_RoutePreviewMap> {
  /// The zoom used while only the saved place is known — and the anchor for
  /// the very first frame, before the fit runs.
  static const double _singlePointZoom = 15;

  /// Padding around the fitted bounds: roomy enough that neither marker, nor
  /// the attribution chip, can be clipped by the card's rounded edge.
  static const EdgeInsets _fitPadding = EdgeInsets.fromLTRB(36, 44, 36, 52);

  /// Owned by this widget rather than the app-wide AutoMotion controller: the
  /// preview can be on screen while the dashboard's map is alive, and two live
  /// maps must never share a camera.
  final MapController _controller = MapController();

  /// Whether [FlutterMap.onMapReady] has fired — camera maths is only valid
  /// from then on.
  bool _ready = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _RoutePreviewMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The device fix arrives asynchronously (and the place can be edited), so
    // re-frame whenever either marker moves.
    final bool moved =
        oldWidget.place.latitude != widget.place.latitude ||
        oldWidget.place.longitude != widget.place.longitude ||
        oldWidget.currentLat != widget.currentLat ||
        oldWidget.currentLon != widget.currentLon;
    if (moved) _scheduleFit();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: _target(),
        initialZoom: _singlePointZoom,
        // Transparent so the offline grid painted underneath stays visible
        // wherever no tile has loaded — this is the offline fallback.
        backgroundColor: Colors.transparent,
        // Drag stays off: the card lives in the detail screen's ListView and
        // inside a bottom sheet, where a vertical drag belongs to the scroll
        // view. Pinch and double-tap zoom still work, and the camera
        // auto-fits both markers anyway.
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom,
        ),
        onMapReady: () {
          _ready = true;
          _scheduleFit();
        },
      ),
      children: <Widget>[
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.routenote.routenote',
          tileProvider: ref.watch(routeTileProviderProvider),
        ),
        PolylineLayer(polylines: _polylines(scheme)),
        MarkerLayer(markers: _markers(scheme)),
        Align(
          alignment: AlignmentDirectional.bottomEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 6, bottom: 6),
            child: MapAttributionChip(label: l10n.routeMapAttribution),
          ),
        ),
      ],
    );
  }

  /// The saved place — always known, so the map always has an anchor.
  LatLng _target() => LatLng(widget.place.latitude, widget.place.longitude);

  /// Every point the camera should frame: the place, plus the device whenever
  /// a fix is known.
  List<LatLng> _framePoints() {
    final List<LatLng> points = <LatLng>[_target()];
    final double? lat = widget.currentLat;
    final double? lon = widget.currentLon;
    if (lat != null && lon != null) points.add(LatLng(lat, lon));
    return points;
  }

  /// Reframes once this frame has laid the map out — never during build.
  void _scheduleFit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fit();
    });
  }

  /// "Fit bounds": frames every known point inside [_fitPadding], capped at a
  /// street-level zoom so a degenerate frame — only the place, or a fix
  /// sitting on top of it — cannot ask for an infinite zoom.
  void _fit() {
    if (!_ready) return;
    _controller.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(_framePoints()),
        padding: _fitPadding,
        maxZoom: 16,
      ),
    );
  }

  /// The straight connection between the device and the saved place, in the
  /// route map's two-stroke language (a soft halo under a crisp primary line).
  /// Empty until the device can be located.
  List<Polyline> _polylines(ColorScheme scheme) {
    final double? lat = widget.currentLat;
    final double? lon = widget.currentLon;
    if (lat == null || lon == null) return const <Polyline>[];
    final List<LatLng> leg = <LatLng>[LatLng(lat, lon), _target()];
    return <Polyline>[
      Polyline(
        points: leg,
        strokeWidth: 6,
        color: scheme.primary.withValues(alpha: 0.16),
      ),
      Polyline(
        points: leg,
        strokeWidth: 2.6,
        color: scheme.primary.withValues(alpha: 0.90),
      ),
    ];
  }

  /// The red saved-place pin, plus — once the device is located — the blue
  /// "you are here" dot. Both sit on the legend printed under the card, which
  /// uses [ColorScheme.primary] and [ColorScheme.error] the same way.
  List<Marker> _markers(ColorScheme scheme) {
    final List<Marker> markers = <Marker>[
      _pin(
        _target(),
        Icon(
          Icons.place,
          size: 32,
          color: scheme.error,
          // A surface-coloured halo keeps the pin legible over dark imagery.
          shadows: <Shadow>[Shadow(color: scheme.surface, blurRadius: 6)],
        ),
      ),
    ];
    final double? lat = widget.currentLat;
    final double? lon = widget.currentLon;
    if (lat != null && lon != null) {
      markers.add(
        _pin(LatLng(lat, lon), _youAreHereDot(scheme.primary, scheme.surface)),
      );
    }
    return markers;
  }

  Marker _pin(LatLng point, Widget child, {double zoom = 15}) {
    final OfflineTileCacheStrategy strategy = OfflineTileCacheStrategy();
    final Widget rendered = strategy.shouldRenderFullPin(zoom)
        ? RepaintBoundary(child: Center(child: child))
        : RepaintBoundary(
            child: Center(
              child: strategy.buildDotMarker(color: Colors.red, size: 10),
            ),
          );
    return Marker(
      point: point,
      width: 32,
      height: 32,
      alignment: Alignment.center,
      child: rendered,
    );
  }

  /// The blue dot ringed by the map surface — the same marker language the
  /// route map uses for its anchors.
  Widget _youAreHereDot(Color color, Color ring) => Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      border: Border.all(color: ring, width: 3),
      boxShadow: <BoxShadow>[
        BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 6),
      ],
    ),
  );
}
