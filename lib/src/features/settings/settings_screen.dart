import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../core/brand/brand_lockup.dart';
import '../../core/config/app_config.dart';
import 'account_settings_screen.dart';
import 'location_settings_screen.dart';
import 'preferences_settings_screen.dart';
import 'security_vault_settings_screen.dart';

/// Modern Material 3 hub for all settings: four drill-down tiles plus a
/// standalone About MapNote card at the bottom.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _HubTile(
            icon: Icons.person_outline_rounded,
            title: l10n.sectionAccount,
            subtitle: l10n.accountAndBackup,
            onTap: () => _push(context, const AccountSettingsScreen()),
          ),
          const SizedBox(height: 12),
          _HubTile(
            icon: Icons.my_location_rounded,
            title: l10n.sectionLocationTracking,
            subtitle: l10n.sectionLocationServices,
            onTap: () => _push(context, const LocationSettingsScreen()),
          ),
          const SizedBox(height: 12),
          _HubTile(
            icon: Icons.verified_user_outlined,
            title: l10n.sectionSecurityVault,
            subtitle: l10n.vaultProtectionTitle,
            onTap: () => _push(context, const SecurityVaultSettingsScreen()),
          ),
          const SizedBox(height: 12),
          _HubTile(
            icon: Icons.tune_rounded,
            title: l10n.sectionPreferences,
            subtitle: l10n.sectionPreferences,
            onTap: () => _push(context, const PreferencesSettingsScreen()),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(l10n.aboutTitle),
              subtitle: Text(l10n.aboutDescription),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(
                context,
                _AboutScreen(l10n: l10n),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'v${AppConfig.appVersion}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      SharedAxisPageRoute<void>(builder: (_) => screen),
    );
  }
}

/// A page route that drives its enter/exit with a horizontal shared-axis
/// transition (Material motion), 300 ms in both directions with an
/// ease-in-out-cubic curve for fluid motion on high refresh-rate displays.
class SharedAxisPageRoute<T> extends PageRoute<T> {
  SharedAxisPageRoute({required this.builder});

  final WidgetBuilder builder;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Animation<double> curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    final Animation<double> curvedSecondary = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    return SharedAxisTransition(
      animation: curved,
      secondaryAnimation: curvedSecondary,
      transitionType: SharedAxisTransitionType.horizontal,
      child: child,
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title, style: theme.textTheme.titleMedium),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Minimal About screen carrying the brand lockup and version.
class _AboutScreen extends StatelessWidget {
  const _AboutScreen({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Center(child: BrandLockup(width: 190)),
          const SizedBox(height: 20),
          Text(
            l10n.aboutDescription,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Divider(height: 24),
          Row(
            children: <Widget>[
              Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(l10n.version, style: theme.textTheme.bodyMedium),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.20),
                  ),
                ),
                child: Text(
                  'v${AppConfig.appVersion}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
