import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/haversine.dart';
import '../../../data/models/place.dart';
import '../../../providers/app_providers.dart';
import '../../place_detail/place_detail_screen.dart';

/// A card widget that displays the top 3 nearest stations to a given place.
/// Uses Haversine distance calculation (100% offline, 0 APIs).
class NearbyStationsCard extends ConsumerWidget {
  const NearbyStationsCard({super.key, required this.currentPlace});

  final Place currentPlace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final placesAsync = ref.watch(placesProvider);

    return placesAsync.when(
      data: (places) {
        final nearest = Haversine.getNearestStations(currentPlace, places, limit: 3);
        if (nearest.isEmpty) return const SizedBox.shrink();

        return Card(
          margin: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Nearby Stations',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...nearest.map((place) {
                  final distance = Haversine.distanceKm(
                    currentPlace.latitude,
                    currentPlace.longitude,
                    place.latitude,
                    place.longitude,
                  );
                  return InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PlaceDetailScreen(placeId: place.id),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: place.name,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  TextSpan(
                                    text: ' - ${distance.toStringAsFixed(1)} km',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}