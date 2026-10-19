import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../core/utils/plus_code.dart';
import '../../../../data/models/place.dart';
import '../../../../providers/app_providers.dart';
import '../../domain/entities/place_link_suggestion.dart';
import '../providers/saved_places_providers.dart';

/// Advisory card listing the day's trip stops and the saved places they match.
///
/// Everything is derived from the recorded route: nothing is stored, nothing
/// leaves the device, and the user always confirms the action. Renders nothing
/// when there is no route or no qualifying stop.
class PlaceLinkSuggestionsCard extends ConsumerWidget {
  const PlaceLinkSuggestionsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<PlaceLinkSuggestion> suggestions = ref.watch(
      placeLinkSuggestionsProvider,
    );
    if (suggestions.isEmpty) return const SizedBox.shrink();

    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.link, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.suggestedPlaceLinks,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 28, top: 2),
              child: Text(
                l10n.suggestedPlaceLinksSubtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 4),
            for (final PlaceLinkSuggestion suggestion in suggestions)
              _SuggestionTile(suggestion: suggestion),
          ],
        ),
      ),
    );
  }
}

class _SuggestionTile extends ConsumerWidget {
  const _SuggestionTile({required this.suggestion});

  static const Uuid _uuid = Uuid();

  final PlaceLinkSuggestion suggestion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final Place? place = suggestion.place;
    final bool matches = place != null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(
        matches ? Icons.place_outlined : Icons.add_location_alt_outlined,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        matches
            ? l10n.suggestedPlaceNearSaved(
                place.name,
                suggestion.distanceMeters.round(),
              )
            : l10n.suggestedPlaceNoMatch,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        l10n.suggestedPlaceStopDetails(suggestion.stop.dwell.inMinutes),
        style: theme.textTheme.bodySmall,
      ),
      trailing: TextButton(
        onPressed: () => matches
            ? _open(context, ref)
            : _saveAsNewPlace(context, ref),
        child: Text(
          matches ? l10n.suggestedPlaceOpenAction : l10n.suggestedPlaceSaveAction,
        ),
      ),
    );
  }

  /// Opens the matched saved place in the user's maps app.
  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final Place? place = suggestion.place;
    if (place == null) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool launched = await ref
        .read(navigationServiceProvider)
        .navigate(place.latitude, place.longitude);
    if (!launched) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.locationUnavailable)));
    }
  }

  /// Saves the stop as a new place, named by its Plus Code (a real, human
  /// usable name that needs no network geocoder).
  Future<void> _saveAsNewPlace(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final Place place = Place(
      id: _uuid.v4(),
      name: PlusCode.encode(
        suggestion.stop.latitude,
        suggestion.stop.longitude,
      ),
      notes: l10n.suggestedPlaceStopDetails(suggestion.stop.dwell.inMinutes),
      latitude: suggestion.stop.latitude,
      longitude: suggestion.stop.longitude,
      timestamp: DateTime.now().toUtc(),
    );
    await ref.read(placesProvider.notifier).save(place);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.suggestedPlaceSaved)),
    );
  }
}
