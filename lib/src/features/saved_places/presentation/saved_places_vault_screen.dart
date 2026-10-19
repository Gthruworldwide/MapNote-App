import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../data/models/place.dart';
import '../../../providers/app_providers.dart';
import '../domain/usecases/unlock_vault.dart';
import 'providers/saved_places_providers.dart';

/// The biometric-gated, AES-256 encrypted "saved places" vault.
///
/// Opening the screen prompts for identity verification; the encrypted box is
/// only opened afterwards, so the places it holds are unreadable while locked.
/// Leaving the screen locks the vault again.
class SavedPlacesVaultScreen extends ConsumerStatefulWidget {
  const SavedPlacesVaultScreen({super.key});

  @override
  ConsumerState<SavedPlacesVaultScreen> createState() =>
      _SavedPlacesVaultScreenState();
}

class _SavedPlacesVaultScreenState
    extends ConsumerState<SavedPlacesVaultScreen> {
  /// Captured once so [dispose] can re-lock without touching `ref`.
  late final VaultPlacesNotifier _vault;

  @override
  void initState() {
    super.initState();
    _vault = ref.read(vaultPlacesProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) => _unlock());
  }

  @override
  void dispose() {
    // Re-lock on the way out: the key must not outlive this screen.
    unawaited(_vault.lock());
    super.dispose();
  }

  Future<void> _unlock() async {
    if (!mounted) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final VaultUnlockResult result = await _vault.unlock(
      reason: l10n.unlockToOpenSavedPlacesVault,
    );
    if (!mounted) return;

    // A failed check stays locked; a device that cannot verify at all opens and
    // gets the same warning every other locked-location gate shows.
    final String? message = switch (result) {
      VaultUnlockResult.unlocked => null,
      VaultUnlockResult.denied => l10n.authenticationFailed,
      VaultUnlockResult.unlockedUnverified => l10n.noDeviceSecurityWarning,
    };
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _lock() async {
    await _vault.lock();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).savedPlacesVaultLocked)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<Place>?> vault = ref.watch(vaultPlacesProvider);
    final bool unlocked = vault.value != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.savedPlacesVault),
        actions: <Widget>[
          if (unlocked)
            IconButton(
              tooltip: l10n.savedPlacesVaultLock,
              onPressed: _lock,
              icon: const Icon(Icons.lock_outline),
            ),
        ],
      ),
      body: vault.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) =>
            Center(child: Text(l10n.errorGeneric)),
        data: (List<Place>? places) {
          if (places == null) return _LockedVault(l10n: l10n, onUnlock: _unlock);
          if (places.isEmpty) return _EmptyVault(l10n: l10n);
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: places.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) => _VaultedPlaceCard(
              place: places[index],
              l10n: l10n,
            ),
          );
        },
      ),
    );
  }
}

class _LockedVault extends StatelessWidget {
  const _LockedVault({required this.l10n, required this.onUnlock});

  final AppLocalizations l10n;
  final Future<void> Function() onUnlock;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.enhanced_encryption_outlined,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.savedPlacesVaultLocked,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.savedPlacesVaultLockedMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onUnlock,
              icon: const Icon(Icons.lock_open),
              label: Text(l10n.savedPlacesVaultUnlock),
            ),
          ],
        ),
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
            Icon(
              Icons.enhanced_encryption_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.savedPlacesVaultEmpty,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.savedPlacesVaultEmptyMessage,
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

class _VaultedPlaceCard extends ConsumerWidget {
  const _VaultedPlaceCard({required this.place, required this.l10n});

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
                  Text(
                    place.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
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
              tooltip: l10n.restoreFromEncryptedVault,
              onPressed: () => _restore(context, ref),
              icon: const Icon(Icons.lock_open_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigate(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool launched = await ref
        .read(navigationServiceProvider)
        .navigate(place.latitude, place.longitude);
    if (!launched) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.locationUnavailable)));
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await ref.read(vaultPlacesProvider.notifier).moveOut(place);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.restoreFromEncryptedVaultDone)),
    );
  }
}
