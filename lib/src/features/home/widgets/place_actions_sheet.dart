import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/place.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/utils/haptics.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_providers.dart';
import '../../../services/lock_gate.dart';
import '../../saved_places/domain/usecases/unlock_vault.dart';
import '../../saved_places/presentation/providers/saved_places_providers.dart';

/// A result the sheet asks the caller to perform (needs a screen-level context).
enum PlaceActionResult { shareQr }

/// Opens the long-press context menu for [place] as a modal bottom sheet.
///
/// Returns [PlaceActionResult.shareQr] when the user asked for a QR code, which
/// the caller must display (the sheet closes before the dialog opens).
Future<PlaceActionResult?> showPlaceActionsSheet(
  BuildContext context,
  Place place,
) {
  return showModalBottomSheet<PlaceActionResult>(
    context: context,
    showDragHandle: true,
    // Lets the sheet grow taller than half the screen so the full action list
    // stays reachable on small screens / large text scales without overflow.
    isScrollControlled: true,
    // Design-system motion, or instant under the OS "Reduce Motion" setting.
    sheetAnimationStyle: AppMotion.sheetAnimationStyle(context),
    builder: (BuildContext context) =>
        SheetEntrance(child: _PlaceActionsSheet(place: place)),
  );
}

/// Bottom sheet listing privacy features and quick actions for a location.
class _PlaceActionsSheet extends ConsumerWidget {
  const _PlaceActionsSheet({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return SafeArea(
      // Scrollable so a long action list (or a large system text scale) never
      // overflows the bottom-sheet bounds — this was the 52px overflow error.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Text(
                place.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            _ActionTile(
              icon: Icons.directions,
              label: l10n.navigate,
              onTap: () => _navigate(context, ref, l10n),
            ),
            _ActionTile(
              icon: place.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
              label: place.isPinned ? l10n.unpinFromTop : l10n.pinToTop,
              onTap: () => _togglePin(context, ref, l10n),
            ),
            _ActionTile(
              icon: Icons.qr_code_2,
              label: l10n.shareQr,
              onTap: () => _showQr(context),
            ),
            _ActionTile(
              icon: Icons.add_to_home_screen,
              label: l10n.addToHomeScreen,
              onTap: () => _addShortcut(context, ref, l10n),
            ),
            const Divider(height: 8),
            _ActionTile(
              icon: place.isLocked ? Icons.lock_open : Icons.lock_outline,
              label: place.isLocked ? l10n.unlockLocation : l10n.lockLocation,
              onTap: () => _toggleLock(context, ref, l10n),
            ),
            if (!place.isHidden)
              _ActionTile(
                icon: Icons.visibility_off_outlined,
                label: l10n.hideLocation,
                onTap: () => _hide(context, ref, l10n),
              ),
            _ActionTile(
              icon: Icons.enhanced_encryption_outlined,
              label: l10n.moveToEncryptedVault,
              onTap: () => _moveToVault(context, ref, l10n),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // --- Actions -------------------------------------------------------------

  Future<void> _navigate(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    // Resolve services while the sheet is still mounted. After `pop()` the
    // widget is disposed, so touching `ref` again once the auth prompt has
    // run (seconds later) would be unsafe.
    final navigation = ref.read(navigationServiceProvider);
    final biometrics = ref.read(biometricServiceProvider);
    final bool locked = place.isLocked;

    Navigator.of(context).pop();

    if (locked) {
      final bool allowed = await ensureUnlockedWith(
        biometrics,
        l10n: l10n,
        reason: l10n.unlockToNavigate,
        messenger: messenger,
        allowWhenUnavailable: true,
      );
      if (!allowed) return;
    }

    // Verification only gates the action; when it passes, the navigation app
    // is always launched.
    Haptics.light();
    final bool launched = await navigation.navigate(
      place.latitude,
      place.longitude,
    );
    if (!launched) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.locationUnavailable)));
    }
  }

  Future<void> _togglePin(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(placesProvider.notifier);
    final bool pinned = !place.isPinned;
    Navigator.of(context).pop();
    await notifier.setPinned(place.id, pinned);
    messenger.showSnackBar(
      SnackBar(content: Text(pinned ? l10n.pinnedToTop : l10n.unpinnedFromTop)),
    );
  }

  void _showQr(BuildContext context) {
    Navigator.of(context).pop(PlaceActionResult.shareQr);
  }

  Future<void> _addShortcut(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final shortcut = ref.read(homeShortcutServiceProvider);
    Navigator.of(context).pop();

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.shortcutUnsupported)));
      return;
    }

    final bool requested = await shortcut.pinToHomeScreen(place);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          requested ? l10n.shortcutRequested : l10n.shortcutUnavailable,
        ),
      ),
    );
  }

  Future<void> _toggleLock(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    // Capture everything we need before the sheet closes: `ref` is unsafe
    // once this widget is disposed, and the auth prompt outlives the pop.
    final notifier = ref.read(placesProvider.notifier);
    final repository = ref.read(placeRepositoryProvider);
    final biometrics = ref.read(biometricServiceProvider);

    // Resolve the latest state through Riverpod (which mirrors Hive) instead
    // of trusting the snapshot the sheet was built with, so toggling always
    // reflects what is actually persisted.
    bool isLocked = place.isLocked;
    final List<Place>? current = ref.read(placesProvider).value;
    if (current != null) {
      for (final Place candidate in current) {
        if (candidate.id == place.id) {
          isLocked = candidate.isLocked;
          break;
        }
      }
    }

    final bool locked = !isLocked;
    Navigator.of(context).pop();

    // Turning the lock *on* is free; turning it *off* must be verified.
    if (!locked) {
      final bool allowed = await ensureUnlockedWith(
        biometrics,
        l10n: l10n,
        reason: l10n.unlockToUnlock,
        messenger: messenger,
        allowWhenUnavailable: true,
      );
      if (!allowed) return;
    }

    // Explicit model update + write straight to Hive + provider refresh, so
    // storage and every listener (home list, detail screen, mask) agree
    // immediately once the action completes.
    final Place? latest = await repository.getById(place.id);
    final Place updated = (latest ?? place).copyWith(isLocked: locked);
    await repository.save(updated);
    await notifier.reload();

    messenger.showSnackBar(
      SnackBar(
        content: Text(locked ? l10n.locationLocked : l10n.locationUnlocked),
      ),
    );
  }

  Future<void> _hide(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(placesProvider.notifier);
    Navigator.of(context).pop();
    await notifier.setHidden(place.id, true);
    messenger.showSnackBar(SnackBar(content: Text(l10n.locationHidden)));
  }

  /// Moves this place into the AES-256 encrypted vault.
  ///
  /// The vault's unlock prompt is what releases the decryption key, so the
  /// verification happens *before* anything is written. Resolved before the
  /// sheet closes because the auth prompt outlives the pop.
  Future<void> _moveToVault(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final VaultPlacesNotifier vault = ref.read(vaultPlacesProvider.notifier);
    Navigator.of(context).pop();

    final VaultUnlockResult result = await vault.unlock(
      reason: l10n.unlockToMoveToEncryptedVault,
    );
    if (result == VaultUnlockResult.denied) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.authenticationFailed)),
      );
      return;
    }
    if (result == VaultUnlockResult.unlockedUnverified) {
      // Same escape hatch the other locked-location gates use: the move goes
      // through, but the user is told no lock screen protects the device.
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.noDeviceSecurityWarning)),
      );
    }

    await vault.moveIn(place);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.moveToEncryptedVaultDone)),
    );
  }
}

/// A single row in the context menu.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () {
        Haptics.light();
        onTap();
      },
    );
  }
}
