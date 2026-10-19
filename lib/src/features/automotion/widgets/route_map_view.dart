import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../../services/polyline_smoother.dart';
import '../../../services/route_milestones.dart';

/// The day's route drawn over real OpenStreetMap raster tiles.
///
/// The card layers this view on top of `TripPathPainter`'s tinted grid: the
/// map's background is transparent, so wherever tiles are missing — airplane
/// mode, first paint, an OSM outage — the grid shows straight through, while
/// the polyline and markers (pure widget layers, no network needed) keep
/// rendering. The card therefore degrades to today's offline mini-map with no
/// branching at all, and upgrades to a real map the moment the first tile
/// lands.
///
/// Deliberate choices:
///
///  * **Drag is off.** The map lives inside a scrolling dashboard;
///    `InteractiveFlag.drag` would fight the ListView for vertical swipes.
///    Pinch and double-tap zoom still work, and the camera is auto-fitted
///    anyway.
///  * **Fit, don't yank.** The camera fits the whole route when the map
///    becomes ready, then re-fits only once the growing route leaves the
///    visible bounds — never on every accepted fix.
///  * **OSM etiquette.** Requests carry the app package as user agent and an
///    attribution chip is always visible (OpenStreetMap ODbL).
class RouteMapView extends ConsumerStatefulWidget {
  const RouteMapView({
    super.key,
    required this.points,
    required this.milestones,
  });

  /// The smoothed route vertices in drive order (the card gates on non-empty).
  final List<RoutePoint> points;

  /// The route's milestones — pinned as start / stop / end markers.
  final List<RouteMilestone> milestones;

  @override
  ConsumerState<RouteMapView> createState() => _RouteMapViewState();
}

class _RouteMapViewState extends ConsumerState<RouteMapView> {
  /// Whether the underlying map has finished initializing (`onMapReady`).
  bool _ready = false;

  @override
  Widget build(BuildContext context) {
    // Rebuild (and re-check the camera fit) whenever an accepted fix lands.
    ref.watch(autoMotionFixesProvider);
    final MapController controller = ref.watch(routeMapControllerProvider);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    // Fit checks are imperative: run them once this frame has laid the map
    // out, never during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fitToRoute();
    });

    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: _centerOf(widget.points),
        initialZoom: 12,
        // Transparent so the offline grid (painted underneath) stays visible
        // when no tile has loaded — this is the offline fallback.
        backgroundColor: Colors.transparent,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom,
        ),
        onMapReady: () {
          _ready = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _fitToRoute(force: true);
          });
        },
      ),
      children: <Widget>[
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.routenote.routenote',
          tileProvider: ref.watch(routeTileProviderProvider),
        ),
        PolylineLayer(polylines: _polylines(theme.colorScheme)),
        MarkerLayer(markers: _markers(theme.colorScheme)),
        Align(
          alignment: AlignmentDirectional.bottomEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 6, bottom: 6),
            child: _AttributionChip(label: l10n.routeMapAttribution),
          ),
        ),
      ],
    );
  }

  /// Fits the camera around the whole route — immediately when [force] (map
  /// just became ready), otherwise only once the route no longer fits inside
  /// the visible bounds, so a trip being recorded never yanks the view.
  void _fitToRoute({bool force = false}) {
    if (!_ready || widget.points.isEmpty) return;
    final MapCamera camera = ref.read(routeMapControllerProvider).camera;
    if (!force && _routeInside(camera.visibleBounds)) return;
    ref
        .read(routeMapControllerProvider)
        .fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(_latLngPoints()),
            padding: const EdgeInsets.all(16),
            // Caps degenerate routes (a single fix, a parked day) so a
            // zero-span bound cannot ask for infinite zoom.
            maxZoom: 16,
          ),
        );
  }

  bool _routeInside(LatLngBounds visible) => widget.points.every(
    (RoutePoint point) =>
        visible.contains(LatLng(point.latitude, point.longitude)),
  );

  List<LatLng> _latLngPoints() => <LatLng>[
    for (final RoutePoint point in widget.points)
      LatLng(point.latitude, point.longitude),
  ];

  LatLng _centerOf(List<RoutePoint> points) {
    double sumLat = 0;
    double sumLon = 0;
    for (final RoutePoint point in points) {
      sumLat += point.latitude;
      sumLon += point.longitude;
    }
    final int count = points.isEmpty ? 1 : points.length;
    return LatLng(sumLat / count, sumLon / count);
  }

  /// The route drawn in the same two-stroke language as the offline painter:
  /// a soft halo under a crisp primary line.
  List<Polyline> _polylines(ColorScheme scheme) {
    if (widget.points.isEmpty) return const <Polyline>[];
    final List<LatLng> points = _latLngPoints();
    return <Polyline>[
      Polyline(
        points: points,
        strokeWidth: 6,
        color: scheme.primary.withValues(alpha: 0.16),
      ),
      Polyline(
        points: points,
        strokeWidth: 2.6,
        color: scheme.primary.withValues(alpha: 0.90),
      ),
    ];
  }

  List<Marker> _markers(ColorScheme scheme) {
    final List<Marker> markers = <Marker>[];
    final RoutePoint first = widget.points.first;
    markers.add(
      _pin(
        LatLng(first.latitude, first.longitude),
        _dot(scheme, scheme.primary, filled: true),
      ),
    );
    if (widget.points.length > 1) {
      final RoutePoint last = widget.points.last;
      markers.add(
        _pin(
          LatLng(last.latitude, last.longitude),
          _dot(scheme, scheme.error, filled: true),
        ),
      );
    }
    for (final RouteMilestone milestone in widget.milestones) {
      if (milestone.kind != RouteMilestoneKind.stop) continue;
      markers.add(
        _pin(
          LatLng(milestone.latitude, milestone.longitude),
          _dot(scheme, scheme.primary, filled: false),
        ),
      );
    }
    return markers;
  }

  Marker _pin(LatLng point, Widget child) => Marker(
    point: point,
    width: 26,
    height: 26,
    alignment: Alignment.center,
    child: Center(child: child),
  );

  /// A map pin in the offline painter's language: a coloured disc ringed by
  /// the map surface. Stops are hollow so they read differently from the
  /// solid start / end anchors.
  Widget _dot(ColorScheme scheme, Color color, {required bool filled}) {
    const double size = 15;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : scheme.surface,
        border: Border.all(color: filled ? scheme.surface : color, width: 3),
      ),
    );
  }
}

/// Small "© OpenStreetMap contributors" chip pinned over the map — required
/// by the OSM tile usage policy, themed from the app so it reads correctly in
/// both brightnesses.
class _AttributionChip extends StatelessWidget {
  const _AttributionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
