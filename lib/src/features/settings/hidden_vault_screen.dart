import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../data/models/place.dart';
import '../../providers/app_providers.dart';
import '../../services/lock_gate.dart';


/// Lists the locations the user has hidden from the home screen.
///
/// Reachable only from Settings, behind a biometric/device-credential prompt.
class HiddenVaultScreen extends ConsumerWidget {
  const HiddenVaultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.hiddenVault)),
      body: ref
          .watch(placesProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object error, StackTrace stackTrace) => Center(
              child: Text(l10n.errorGeneric),
            ),
            data: (List<Place> places) {
              final List<Place> hidden = places
                  .where((Place place) => place.isHidden)
                  .toList();
              if (hidden.isEmpty) return _EmptyVault(l10n: l10n);

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: hidden.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int index) =>
                    _VaultCard(place: hidden[index], l10n: l10n),
              );
            },
          ),
    );
  }
}

class _EmptyVault extends StatelessWidget {
  const _EmptyVault({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.visibility_off_outlined, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              l10n.hiddenVaultEmpty,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.hiddenVaultEmptyMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VaultCard extends ConsumerWidget {
  const _VaultCard({required this.place, required this.l10n});

  final Place place;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      if (place.isLocked) ...<Widget>[
                        Icon(
                          Icons.lock,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          place.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    place.formattedCoordinates,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.navigate,
              onPressed: () => _navigate(context, ref),
              icon: const Icon(Icons.directions),
            ),
            IconButton(
              tooltip: l10n.unhideLocation,
              onPressed: () => _unhide(context, ref),
              icon: const Icon(Icons.visibility_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigate(BuildContext context, WidgetRef ref) async {
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

  Future<void> _unhide(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await ref.read(placesProvider.notifier).setHidden(place.id, false);
    messenger.showSnackBar(SnackBar(content: Text(l10n.locationUnhidden)));
  }
}
