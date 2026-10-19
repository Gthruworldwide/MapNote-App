import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// The small "© OpenStreetMap contributors" chip pinned over a tile map.
///
/// Required by the OSM tile usage policy, and themed from the app so it stays
/// legible in both brightnesses. Shared by every OSM-backed map — the
/// AutoMotion route map and the saved-place preview — so attribution reads
/// identically wherever a map appears.
class MapAttributionChip extends StatelessWidget {
  const MapAttributionChip({super.key, required this.label});

  /// Already-localized attribution text (see `routeMapAttribution`).
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
