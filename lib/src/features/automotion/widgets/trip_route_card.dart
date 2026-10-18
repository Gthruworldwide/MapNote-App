import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_providers.dart';
import '../../../services/polyline_smoother.dart';
import 'trip_path_painter.dart';

/// Today's recorded route as a fully offline mini-map.
///
/// The vertices come from `AutoMotionService.smoothedPath` — every accepted
/// fix already jitter-filtered by `PolylineSmoother` on its way here (and on
/// its way to trip history) — so raw GPS noise is never drawn. The card
/// rebuilds on every accepted fix ([autoMotionFixesProvider]) purely as a
/// repaint trigger; there is no map SDK and no network call anywhere.
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
            else
              SizedBox(
                height: 160,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: TripPathPainter(
                      points: path,
                      scheme: theme.colorScheme,
                      isDark: theme.brightness == Brightness.dark,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
