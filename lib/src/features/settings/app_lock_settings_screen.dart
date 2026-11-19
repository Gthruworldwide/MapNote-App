import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../providers/app_providers.dart';

/// App Lock settings screen — separate from Vault Lock.
/// App Lock controls how quickly the app locks after backgrounding;
/// Vault Lock protects encrypted places with biometrics/PIN.
class AppLockSettingsScreen extends ConsumerWidget {
  const AppLockSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final sessionGuard = ref.watch(sessionGuardProvider);

    // Read current inactivity timeout from settings, default to 15 minutes
    final settingsRepository = ref.watch(settingsRepositoryProvider);
    final currentMinutes =
        settingsRepository.sessionTimeoutMinutes.toString();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sessionTimeoutTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.sessionTimeoutSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),

            // App Lock toggle options
            _AppLockOption(
              value: 'never',
              label: 'Never',
              isSelected: currentMinutes == 'never',
              onSelect: () => _setTimeout(context, ref, 'never'),
            ),
            const Divider(height: 24),
            _AppLockOption(
              value: '15',
              label: '15 min',
              isSelected: currentMinutes == '15',
              onSelect: () => _setTimeout(context, ref, '15'),
            ),
            const Divider(height: 24),
            _AppLockOption(
              value: '5',
              label: '5 min',
              isSelected: currentMinutes == '5',
              onSelect: () => _setTimeout(context, ref, '5'),
            ),
            const Divider(height: 24),
            _AppLockOption(
              value: '1',
              label: '1 min',
              isSelected: currentMinutes == '1',
              onSelect: () => _setTimeout(context, ref, '1'),
            ),
            const Spacer(),

            // Vault Lock info section
            _SectionHeader(
              icon: Icons.vpn_key_outlined,
              title: l10n.sectionSecurityVault,
              subtitle: 'Vault Lock is managed separately',
            ),
            const SizedBox(height: 8),
            Text(
              'Vault Lock ends the encrypted vault session when the app backgrounds '
              'or the device locks. This is managed via the "Auto-lock after inactivity" '
              'setting below and the "Lock when device locks" toggle in Vault protection.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),

            // Lock on device lock toggle
            SwitchListTile(
              title: Text(l10n.lockOnDeviceLockTitle),
              subtitle: Text(l10n.lockOnDeviceLockSubtitle),
              value: sessionGuard.lockOnDeviceLock,
              onChanged: (value) {
                ref.read(sessionGuardProvider).setLockOnDeviceLock(value);
              },
              activeThumbColor: theme.colorScheme.primary,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  void _setTimeout(BuildContext context, WidgetRef ref, String minutes) async {
    // Save the inactivity timeout to settings via the repository
    ref.read(settingsRepositoryProvider).setSessionTimeoutMinutes(int.parse(minutes));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Auto-lock timeout updated')),
    );
  }
}

/// A combined section header with icon, title, and optional subtitle.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
      ],
    );
  }
}

/// A reusable option tile for App Lock timeout selection.
class _AppLockOption extends StatelessWidget {
  const _AppLockOption({
    required this.value,
    required this.label,
    required this.isSelected,
    required this.onSelect,
  });

  final String value;
  final String label;
  final bool isSelected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      title: Text(label),
      trailing: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: isSelected
            ? const Icon(Icons.check_circle, color: Color(0xFF38FFB0))
            : const Icon(Icons.radio_button_unchecked),
      ),
      onTap: onSelect,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isSelected
            ? BorderSide(color: theme.colorScheme.primary, style: BorderStyle.solid, width: 2)
            : BorderSide.none,
      ),
    );
  }
}