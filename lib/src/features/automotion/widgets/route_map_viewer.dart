import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../data/models/track_point.dart';
import '../../../data/models/trip_segment.dart';
import '../../../providers/app_providers.dart';
import '../../../services/polyline_smoother.dart';
import '../../../widgets/map_attribution_chip.dart';
import 'motion_format.dart';
import 'motion_presentation.dart';

/// The selected day drawn over OpenStreetMap tiles, colour-coded by motion.
///
/// Every classified segment contributes its own polyline — blue for a drive,
/// green for a walk, violet for a run — while stopovers become tappable pins
/// instead of lines, because a stop covers no ground. The map is **derived
/// state**: it reads [motionHistoryProvider], which is recomputed from the
/// day's stored fixes, so nothing here adds a Hive key.
///
/// Choices worth knowing:
///
/// * **Fit once, declaratively.** `initialCameraFit` frames the whole day on
///   first layout; the map is keyed by the selected day, so changing days
///   creates a fresh camera instead of leaving the old framing in place.
/// * **Smoothed geometry.** Segment points are raw fixes — the same jitter the
///   dashboard's route card strips — so each polyline is passed through
///   [PolylineSmoother] before it is drawn. Smoothing never moves a vertex more
///   than 30 m from where the receiver placed it.
/// * **Offline-first.** The map background is transparent and the parent paints
///   a surface behind it, so a day with no network still shows the full coloured
///   geometry; tiles simply fill in when they can.
class RouteMapViewer extends ConsumerWidget {
  const RouteMapViewer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DateTime day = ref.watch(selectedDateProvider);
    final List<TripSegment> segments = ref.watch(motionHistoryProvider);
    // The same lazily-resolved names the timeline cards use, so a pin's sheet
    // and its card can never disagree about what the place is called.
    final Map<DateTime, String?> stopoverNames = ref.watch(
      stopoverNamesProvider,
    );
    final List<LatLng> points = _pointsOf(segments);

    if (points.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.motionHistoryNoRoute,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return FlutterMap(
      // A new day means a new camera: rebuilding the map state is the simplest
      // way to re-run the one-shot initial fit.
      key: ValueKey<int>(day.millisecondsSinceEpoch),
      options: MapOptions(
        initialCenter: points.first,
        initialZoom: 13,
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(32),
          // Caps degenerate days (a single fix) so a zero-span bound cannot ask
          // for infinite zoom.
          maxZoom: 16,
        ),
        // Transparent so the parent's surface shows through until a tile lands.
        backgroundColor: Colors.transparent,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: <Widget>[
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.routenote.routenote',
          tileProvider: ref.watch(routeTileProviderProvider),
        ),
        PolylineLayer(polylines: _polylines(segments)),
        MarkerLayer(markers: _stopoverMarkers(context, segments, stopoverNames)),
        Align(
          alignment: AlignmentDirectional.topStart,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 8, top: 8),
            child: const _MotionLegend(),
          ),
        ),
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

  /// Every segment's fixes, flattened in chronological order (segment order is
  /// chronological, so this is too).
  List<LatLng> _pointsOf(List<TripSegment> segments) => <LatLng>[
    for (final TripSegment segment in segments)
      for (final TrackPoint point in segment.points)
        LatLng(point.latitude, point.longitude),
  ];

  /// One haloed polyline per *moving* segment, in its motion colour.
  ///
  /// Stopovers are skipped on purpose: a pin carries the information, a
  /// zero-length line would just be a dot in a misleading colour.
  List<Polyline> _polylines(List<TripSegment> segments) {
    const PolylineSmoother smoother = PolylineSmoother();
    final List<Polyline> polylines = <Polyline>[];
    for (final TripSegment segment in segments) {
      if (segment.type == MotionType.stationary) continue;
      if (segment.points.length < 2) continue;
      final List<RoutePoint> smoothed = smoother.smooth(<RoutePoint>[
        for (final TrackPoint point in segment.points) point.toRoutePoint(),
      ]);
      if (smoothed.length < 2) continue;
      final List<LatLng> line = <LatLng>[
        for (final RoutePoint point in smoothed)
          LatLng(point.latitude, point.longitude),
      ];
      polylines.add(
        Polyline(
          points: line,
          strokeWidth: 6,
          color: segment.type.color.withValues(alpha: 0.18),
        ),
      );
      polylines.add(
        Polyline(
          points: line,
          strokeWidth: 3,
          color: segment.type.color,
        ),
      );
    }
    return polylines;
  }

  /// One tappable pin per stopover, at the centroid of its fixes.
  List<Marker> _stopoverMarkers(
    BuildContext context,
    List<TripSegment> segments,
    Map<DateTime, String?> names,
  ) {
    final ThemeData theme = Theme.of(context);
    final List<Marker> markers = <Marker>[];
    for (final TripSegment segment in segments) {
      if (segment.type != MotionType.stationary) continue;
      if (segment.points.isEmpty) continue;
      double sumLat = 0;
      double sumLon = 0;
      for (final TrackPoint point in segment.points) {
        sumLat += point.latitude;
        sumLon += point.longitude;
      }
      final int count = segment.points.length;
      markers.add(
        Marker(
          point: LatLng(sumLat / count, sumLon / count),
          width: 34,
          height: 34,
          alignment: Alignment.center,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showStopover(
              context,
              segment,
              names[segment.startTime],
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: segment.type.color,
                border: Border.all(
                  color: theme.colorScheme.surface,
                  width: 2.5,
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                segment.type.icon,
                size: 16,
                color: theme.colorScheme.surface,
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  /// Explains one stopover: what it is, how long it lasted and when.
  void _showStopover(BuildContext context, TripSegment segment, String? name) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final AppLocalizations l10n = AppLocalizations.of(sheetContext);
        final ThemeData theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(segment.type.icon, color: segment.type.color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name ?? segment.stopoverName ?? l10n.motionTypeStopover,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.motionHistoryStopoverStats(
                    formatMotionDuration(segment.duration, l10n),
                  ),
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  formatSegmentTimeRange(
                    sheetContext,
                    start: segment.startTime,
                    end: segment.endTime,
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The map's colour key: which line means drive, walk, run and stop.
///
/// Colour is never the only channel — each entry carries the same icon and
/// localized label the cards use, so the map stays readable for colour-blind
/// users and in either brightness.
class _MotionLegend extends StatelessWidget {
  const _MotionLegend();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final MotionType type in const <MotionType>[
            MotionType.vehicle,
            MotionType.walking,
            MotionType.running,
            MotionType.stationary,
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: type.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(type.label(l10n), style: theme.textTheme.labelSmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
