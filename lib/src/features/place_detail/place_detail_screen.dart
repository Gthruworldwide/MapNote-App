import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_formats.dart';
import '../../data/models/place.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../../services/lock_gate.dart';
import '../add_place/add_place_screen.dart';

/// Shows a saved location with navigation, copy, edit and delete actions.
class PlaceDetailScreen extends ConsumerWidget {
  const PlaceDetailScreen({super.key, required this.placeId});

  final String placeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<Place>? places = ref.watch(placesProvider).value;

    Place? place;
    if (places != null) {
      for (final Place candidate in places) {
        if (candidate.id == placeId) {
          place = candidate;
          break;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.placeDetailsTitle),
        actions: <Widget>[
          if (place != null)
            IconButton(
              tooltip: l10n.edit,
              onPressed: () => _openEdit(context, ref, place!),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: place == null
          ? _MissingPlace(l10n: l10n)
          : _buildBody(context, ref, l10n, place),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Place place,
  ) {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(place.name, style: theme.textTheme.headlineSmall),
                if (place.notes.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    place.notes,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  l10n.createdAt(
                    formatDateTime(
                      place.timestamp,
                      Localizations.localeOf(context).toString(),
                    ),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.pin_drop_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${l10n.latitude}: ${place.latitude.toStringAsFixed(6)}\n'
                        '${l10n.longitude}: ${place.longitude.toStringAsFixed(6)}\n'
                        '${l10n.plusCode}: ${place.plusCode}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.copyCoordinates,
                      onPressed: () => _copyCoordinates(context, l10n, place),
                      icon: const Icon(Icons.copy),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => _navigate(context, ref, l10n, place),
          icon: const Icon(Icons.directions),
          label: Text(l10n.navigate),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    _openInGoogleMaps(context, ref, l10n, place),
                icon: const Icon(Icons.map_outlined),
                label: Text(l10n.openInGoogleMaps),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openInWaze(context, ref, l10n, place),
                icon: const Icon(Icons.near_me_outlined),
                label: Text(l10n.openInWaze),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Center(
          child: TextButton.icon(
            onPressed: () => _confirmDelete(context, ref, l10n, place),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            icon: const Icon(Icons.delete_outline),
            label: Text(l10n.delete),
          ),
        ),
      ],
    );
  }

  Future<void> _openEdit(
    BuildContext context,
    WidgetRef ref,
    Place place,
  ) async {
    if (place.isLocked) {
      final bool allowed = await ensureUnlocked(
        ref,
        l10n: AppLocalizations.of(context),
        reason: AppLocalizations.of(context).unlockToEdit,
        messenger: ScaffoldMessenger.of(context),
        allowWhenUnavailable: true,
      );
      if (!allowed || !context.mounted) return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AddPlaceScreen(place: place)),
    );
  }

  Future<void> _copyCoordinates(
    BuildContext context,
    AppLocalizations l10n,
    Place place,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    // Include the Plus Code so the pasted text works everywhere, even in apps
    // that only understand Open Location Codes.
    final String text =
        '${place.formattedCoordinates}\n${l10n.plusCode}: ${place.plusCode}';
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(content: Text(l10n.coordinatesCopied)));
  }

  Future<void> _navigate(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Place place,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (place.isLocked) {
      final bool allowed = await ensureUnlocked(
        ref,
        l10n: l10n,
        reason: l10n.unlockToNavigate,
        messenger: messenger,
        allowWhenUnavailable: true,
      );
      if (!allowed) return;
    }
    final bool launched = await ref
        .read(navigationServiceProvider)
        .navigate(place.latitude, place.longitude);
    if (!launched) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.locationUnavailable)));
    }
  }

  Future<void> _openInGoogleMaps(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Place place,
  ) async {
    if (place.isLocked) {
      final bool allowed = await ensureUnlocked(
        ref,
        l10n: l10n,
        reason: l10n.unlockToNavigate,
        messenger: ScaffoldMessenger.of(context),
        allowWhenUnavailable: true,
      );
      if (!allowed) return;
    }
    await ref
        .read(navigationServiceProvider)
        .openInGoogleMaps(place.latitude, place.longitude);
  }

  Future<void> _openInWaze(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Place place,
  ) async {
    if (place.isLocked) {
      final bool allowed = await ensureUnlocked(
        ref,
        l10n: l10n,
        reason: l10n.unlockToNavigate,
        messenger: ScaffoldMessenger.of(context),
        allowWhenUnavailable: true,
      );
      if (!allowed) return;
    }
    await ref
        .read(navigationServiceProvider)
        .navigateWithWaze(place.latitude, place.longitude);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Place place,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.deletePlaceTitle),
        content: Text(l10n.deletePlaceMessage(place.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    await ref.read(placesProvider.notifier).delete(place.id);
    messenger.showSnackBar(SnackBar(content: Text(l10n.placeDeleted)));
    if (context.mounted) navigator.pop();
  }
}

class _MissingPlace extends StatelessWidget {
  const _MissingPlace({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(l10n.errorGeneric));
  }
}
