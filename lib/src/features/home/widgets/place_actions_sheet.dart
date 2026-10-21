import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/place.dart';
import '../../../core/utils/haptics.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_providers.dart';
import '../../../services/lock_gate.dart';
import '../../add_place/add_place_screen.dart';


/// A result the compact action bar asks the caller to perform (needs a
/// screen-level context, e.g. showing a QR dialog).
enum PlaceActionResult { shareQr }

/// Opens the long-press context menu for [place] as a compact horizontal
/// action strip.
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
    builder: (BuildContext context) =>
        _CompactActionBar(place: place),
  );
}

/// A compact horizontal strip of icon actions for a saved place.
///
/// Replaces the former text-heavy list. Each action is an icon button with a
/// localized tooltip; the strip is direction-aware (RTL/LTR) and minimal in
/// height.
class _CompactActionBar extends ConsumerWidget {
  const _CompactActionBar({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            _ActionIcon(
              icon: Icons.directions_outlined,
              tooltip: l10n.navigate,
              color: theme.colorScheme.primary,
              onTap: () => _navigate(context, ref, l10n),
            ),
            _ActionIcon(
              icon: Icons.edit_outlined,
              tooltip: l10n.editPlaceTitle,
              onTap: () => _edit(context, ref, l10n),
            ),
            _ActionIcon(
              icon: place.isLocked
                  ? Icons.lock_open_rounded
                  : Icons.lock_outline_rounded,
              tooltip: place.isLocked ? l10n.unlockLocation : l10n.lockLocation,
              onTap: () => _toggleLock(context, ref, l10n),
            ),
            _ActionIcon(
              icon: place.isHidden
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              tooltip: place.isHidden ? l10n.unhideLocation : l10n.hideLocation,
              onTap: () => _toggleHidden(context, ref, l10n),
            ),
            _ActionIcon(
              icon: Icons.share_outlined,
              tooltip: l10n.shareQr,
              onTap: () => _shareQr(context),
            ),
            _ActionIcon(
              icon: Icons.delete_outline_rounded,
              tooltip: l10n.delete,
              color: theme.colorScheme.error,
              onTap: () => _delete(context, ref, l10n),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigate(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
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
      if (!allowed || !context.mounted) return;
    }

    Haptics.light();
    final bool launched = await navigation.navigate(
      place.latitude,
      place.longitude,
    );
    if (!launched && context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.locationUnavailable)));
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (place.isLocked) {
      final bool allowed = await ensureUnlockedWith(
        ref.read(biometricServiceProvider),
        l10n: l10n,
        reason: l10n.unlockToEdit,
        messenger: messenger,
        allowWhenUnavailable: true,
      );
      if (!allowed) return;
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AddPlaceScreen(place: place)),
    );
  }

  void _shareQr(BuildContext context) {
    Navigator.of(context).pop(PlaceActionResult.shareQr);
  }

  Future<void> _toggleLock(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(placesProvider.notifier);
    final repository = ref.read(placeRepositoryProvider);
    final biometrics = ref.read(biometricServiceProvider);

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

    // Turning the lock on is free; turning it off must be verified.
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
    if (!context.mounted) return;

    Navigator.of(context).pop();

    final Place? latest = await repository.getById(place.id);
    final Place updated = (latest ?? place).copyWith(isLocked: locked);
    await repository.save(updated);
    await notifier.reload();

    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(locked ? l10n.locationLocked : l10n.locationUnlocked)),
      );
    }
  }

  Future<void> _toggleHidden(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(placesProvider.notifier);
    Navigator.of(context).pop();
    if (place.isHidden) {
      await notifier.setHidden(place.id, false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.locationUnhidden)));
    } else {
      await notifier.setHidden(place.id, true);
      messenger.showSnackBar(SnackBar(content: Text(l10n.locationHidden)));
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
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

    Navigator.of(context).pop();
    await ref.read(placesProvider.notifier).delete(place.id);
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.placeDeleted)));
    }
  }
}

/// A single icon action in the compact strip.
class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, color: color),
        onPressed: () {
          Haptics.light();
          onTap();
        },
      ),
    );
  }
}
