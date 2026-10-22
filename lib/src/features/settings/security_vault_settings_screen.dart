import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../core/security/session_guard.dart';
import '../../providers/app_providers.dart';
import '../saved_places/domain/services/vault_pin_verifier.dart';
import '../saved_places/presentation/providers/saved_places_providers.dart';
import '../saved_places/presentation/widgets/vault_pin_dialog.dart';
import 'settings_shared.dart';

/// Security vault settings: biometric vault switch, PIN management, session
/// timeout and device-lock behaviour.
class SecurityVaultSettingsScreen extends ConsumerWidget {
  const SecurityVaultSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sectionSecurityVault)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SettingsSection(
            title: l10n.vaultProtectionTitle,
            child: _buildVaultProtectionCard(context, ref, l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildVaultProtectionCard(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final ThemeData theme = Theme.of(context);
    final int minutes = ref.watch(sessionTimeoutProvider);
    final bool lockOnDeviceLock = ref.watch(lockOnDeviceLockProvider);
    final bool vaultEnabled = ref.watch(biometricVaultEnabledProvider);
    final bool hasPin = ref.watch(vaultPinSetProvider).value ?? false;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              Icons.enhanced_encryption_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.biometricVaultEnabled),
            subtitle: Text(l10n.biometricVaultEnabledSubtitle),
            value: vaultEnabled,
            onChanged: (bool value) =>
                _setBiometricVaultEnabled(context, ref, value),
          ),
          if (vaultEnabled) ...<Widget>[
            const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.pin_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(l10n.changeVaultPin),
              subtitle: Text(
                hasPin ? l10n.vaultPinSet : l10n.changeVaultPinSubtitle,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editVaultPin(context, ref, l10n),
            ),
          ],
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.timer_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.sessionTimeoutTitle),
            subtitle: Text(l10n.sessionTimeoutSubtitle),
            trailing: DropdownButton<int>(
              value: minutes,
              underline: const SizedBox.shrink(),
              onChanged: (int? value) {
                if (value == null) return;
                ref.read(sessionTimeoutProvider.notifier).setMinutes(value);
              },
              items: <DropdownMenuItem<int>>[
                for (final int option in SessionGuard.selectableInactivityMinutes)
                  DropdownMenuItem<int>(
                    value: option,
                    child: Text(l10n.sessionTimeoutMinutes(option)),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              Icons.phonelink_lock_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.lockOnDeviceLockTitle),
            subtitle: Text(l10n.lockOnDeviceLockSubtitle),
            value: lockOnDeviceLock,
            onChanged: (bool value) =>
                ref.read(lockOnDeviceLockProvider.notifier).setEnabled(value),
          ),
        ],
      ),
    );
  }

  Future<void> _setBiometricVaultEnabled(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    await ref
        .read(biometricVaultEnabledProvider.notifier)
        .setEnabled(value);
    if (value) return;
    await ref.read(vaultPlacesProvider.notifier).lock();
  }

  Future<void> _editVaultPin(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final VaultPinVerifier verifier = ref.read(vaultPinVerifierProvider);
    final bool hasPin = await verifier.hasPin();
    if (!context.mounted) return;

    if (!hasPin) {
      await _setVaultPin(context, ref, l10n, verifier);
      return;
    }

    final String? action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: Text(l10n.changeVaultPin),
              onTap: () => Navigator.of(sheetContext).pop('change'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.removeVaultPin),
              onTap: () => Navigator.of(sheetContext).pop('remove'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    if (action == 'remove') {
      await verifier.clearPin();
      ref.invalidate(vaultPinSetProvider);
      messenger.showSnackBar(SnackBar(content: Text(l10n.vaultPinRemoved)));
      return;
    }
    await _setVaultPin(context, ref, l10n, verifier);
  }

  Future<void> _setVaultPin(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    VaultPinVerifier verifier,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String? pin = await showVaultPinDialog(
      context,
      l10n: l10n,
      requireConfirmation: true,
      title: l10n.changeVaultPin,
    );
    if (pin == null || !context.mounted) return;
    await verifier.setPin(pin);
    ref.invalidate(vaultPinSetProvider);
    messenger.showSnackBar(SnackBar(content: Text(l10n.vaultPinSet)));
  }
}
