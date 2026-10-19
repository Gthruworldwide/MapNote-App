import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../../services/polyline_smoother.dart';
import '../../../services/route_milestones.dart';
import 'route_map_view.dart';
import 'route_timeline.dart';
import 'trip_path_painter.dart';

/// Today's recorded route as a **dual preview**: the day's route on real
/// OpenStreetMap tiles (auto-fitted to the whole trip) plus the milestone
/// timeline narrating when and where the day stopped.
///
/// The vertices come from `AutoMotionService.smoothedPath` — every accepted
/// fix already jitter-filtered by `PolylineSmoother` on its way here (and on
/// its way to trip history) — so raw GPS noise is never drawn. The card
/// rebuilds on every accepted fix ([autoMotionFixesProvider]) as a repaint /
/// refit trigger.
///
/// Offline-first is preserved by construction: the tile map sits above the
/// grid-only `TripPathPainter` with a transparent background, so with no
/// tiles available the card renders the tinted grid, the polyline and the
/// markers — today's offline mini-map — without a single network-sourced
/// widget disappearing. Milestone names degrade the same way (kind labels).
class TripRouteCard extends ConsumerWidget {
  const TripRouteCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Repaint trigger: a broadcast of accepted fixes / midnight rollovers.
    ref.watch(autoMotionFixesProvider);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final List<RoutePoint> path = ref.watch(
      autoMotionServiceProvider,
    ).smoothedPath;
    final List<RouteMilestone> milestones = ref.watch(
      routeMilestonesProvider,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.route,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(l10n.autoMotionRoute, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            if (path.isEmpty)
              Text(
                l10n.autoMotionRouteEmpty,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...<Widget>[
              SizedBox(
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.input),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      // Offline layer: the tinted grid (routeVisible: false —
                      // the map draws the route itself, so nothing doubles).
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: TripPathPainter(
                            points: path,
                            scheme: theme.colorScheme,
                            isDark: theme.brightness == Brightness.dark,
                            routeVisible: false,
                          ),
                        ),
                      ),
                      // Online layer: real tiles, polyline, markers. Transparent
                      // where tiles never arrive (offline fallback above).
                      RouteMapView(points: path, milestones: milestones),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              const RouteTimeline(),
            ],
          ],
        ),
      ),
    );
  }
}
