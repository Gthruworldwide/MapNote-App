import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../core/security/session_guard.dart';
import '../../../../providers/app_providers.dart';

/// Dims vaulted content when the device has been left resting unattended.
///
/// A shoulder-surfer's best opportunity is the phone lying on a table with the
/// vault still open. Rather than locking the screen outright (which would fight
/// the user if they are just reading), this dims the vault's contents and shows
/// a short, localized reason, so the information is no longer legible from a
/// metre away — while a touch restores it instantly.
///
/// The dimming is driven by [interactionContextProvider], which mirrors the
/// accelerometer micro-movement verdict: motion means the device is in a hand and
/// nothing dims; sustained stillness ([InteractionContext.surfaceIdle]) dims.
/// Tapping anywhere clears it until the next stillness period, so mis-detection
/// costs the user one tap, never a lost place.
///
/// Until the first sensor sample arrives the verdict is unknown, which is treated
/// as hand-held: the dimmer must never cover content on a guess.
///
/// Colors come entirely from [ColorScheme] (dark-mode safe) and the overlay is
/// direction-agnostic.
class VaultPrivacyDimmer extends ConsumerStatefulWidget {
  const VaultPrivacyDimmer({required this.child, super.key});

  /// The vault content to protect.
  final Widget child;

  @override
  ConsumerState<VaultPrivacyDimmer> createState() => _VaultPrivacyDimmerState();
}

class _VaultPrivacyDimmerState extends ConsumerState<VaultPrivacyDimmer> {
  /// Set when the user dismisses the dimming; cleared once the device is picked
  /// up again, so the next unattended stretch dims afresh.
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<InteractionContext> interaction =
        ref.watch(interactionContextProvider);
    final InteractionContext verdict =
        interaction.value ?? InteractionContext.unknown;

    // Any movement (or an explicit tap) clears the dismissal, so a picked-up
    // device is never left dimmed.
    if (verdict == InteractionContext.handHeld && _dismissed) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted) setState(() => _dismissed = false);
      });
    }

    final bool dimmed =
        verdict == InteractionContext.surfaceIdle && !_dismissed;

    return Stack(
      children: <Widget>[
        widget.child,
        if (dimmed)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _dismissed = true),
              child: Container(
                color: theme.colorScheme.scrim.withValues(alpha: 0.65),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.visibility_off_outlined,
                      size: 40,
                      color: theme.colorScheme.onInverseSurface,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.vaultDimmingNotice,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onInverseSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
