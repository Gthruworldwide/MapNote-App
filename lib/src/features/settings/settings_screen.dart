import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../core/brand/brand_assets.dart';
import '../../core/brand/brand_logo.dart';
import '../../core/config/app_config.dart';
import '../../core/config/preferred_nav_app.dart';
import '../../core/utils/date_formats.dart';
import '../../data/models/place.dart';
import '../../data/remote/auth_service.dart';
import '../../data/repositories/sync_repository.dart';
import '../../providers/app_providers.dart';
import '../../services/location_service.dart';
import '../../services/lock_gate.dart';
import '../home/widgets/smart_insights_card.dart';
import 'hidden_vault_screen.dart';

/// Settings, grouped into cards: account, location services, sync & backup,
/// preferences and about.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<AuthUser?> auth = ref.watch(authProvider);
    final SyncState sync = ref.watch(syncControllerProvider);
    final Locale? locale = ref.watch(localeControllerProvider);
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    final AsyncValue<LocationStatus> location = ref.watch(
      locationStatusProvider,
    );
    final PreferredNavApp navApp = ref.watch(preferredNavAppProvider);
    final int hiddenCount =
        ref
            .watch(placesProvider)
            .value
            ?.where((Place place) => place.isHidden)
            .length ??
        0;

    ref.listen<SyncState>(syncControllerProvider, (prev, next) {
      if (prev?.status != SyncStatus.syncing) return;
      final SnackBar snackBar = switch (next.status) {
        SyncStatus.success => SnackBar(
          content: Text(
            next.outcome == SyncOutcome.restored
                ? l10n.restoreComplete
                : l10n.syncComplete,
          ),
        ),
        SyncStatus.error => SnackBar(
          content: Text(l10n.syncFailed(next.error ?? l10n.errorGeneric)),
        ),
        SyncStatus.skipped => SnackBar(content: Text(l10n.syncSignInRequired)),
        _ => const SnackBar(content: SizedBox.shrink()),
      };
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
        }
      });
    });

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _SettingsSection(
            title: l10n.sectionAccount,
            child: _buildAccountCard(context, ref, l10n, auth),
          ),
          _SettingsSection(
            title: l10n.sectionLocationServices,
            child: _buildLocationCard(context, ref, l10n, location),
          ),
          _SettingsSection(
            title: l10n.dailyGpsSection,
            child: _buildGpsCard(context, ref, l10n),
          ),
          _SettingsSection(
            title: l10n.autoMotionSection,
            child: _buildAutoMotionCard(context, ref, l10n),
          ),
          _SettingsSection(
            title: l10n.sectionSync,
            child: _buildSyncCard(context, ref, l10n, sync),
          ),
          _SettingsSection(
            title: l10n.sectionPrivacy,
            child: _buildPrivacyCard(context, ref, l10n, hiddenCount),
          ),
          _SettingsSection(
            title: l10n.sectionPreferences,
            child: _buildPreferencesCard(
              context,
              ref,
              l10n,
              locale,
              themeMode,
              navApp,
            ),
          ),
          _SettingsSection(
            title: l10n.sectionSmartInsights,
            child: _buildAgentCard(context, ref, l10n),
          ),
          _SettingsSection(
            title: l10n.about,
            child: _buildAboutCard(context, l10n),
          ),
        ],
      ),
    );
  }

  // --- Account ---------------------------------------------------------------

  Widget _buildAccountCard(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    AsyncValue<AuthUser?> auth,
  ) {
    final ThemeData theme = Theme.of(context);
    return auth.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace stackTrace) => ListTile(
        leading: const Icon(Icons.error_outline),
        title: Text(l10n.errorGeneric),
      ),
      data: (AuthUser? user) {
        if (user == null) {
          return Column(
            children: <Widget>[
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(l10n.notSignedIn),
                subtitle: Text(l10n.syncSignInRequired),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: FilledButton.tonalIcon(
                  onPressed: () => _signIn(context, ref, l10n),
                  icon: const Icon(Icons.login),
                  label: Text(l10n.signInWithGoogle),
                ),
              ),
            ],
          );
        }

        final String? photoUrl = user.photoUrl;
        final bool hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
        return Column(
          children: <Widget>[
            ListTile(
              leading: CircleAvatar(
                radius: 26,
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
                child: hasPhoto ? null : const Icon(Icons.person),
              ),
              title: Text(
                user.displayName ?? user.email,
                style: theme.textTheme.titleMedium,
              ),
              subtitle: Text(user.email),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: OutlinedButton.icon(
                onPressed: () => _signOut(context, ref, l10n),
                icon: const Icon(Icons.logout),
                label: Text(l10n.signOut),
              ),
            ),
          ],
        );
      },
    );
  }

  // --- Location services -----------------------------------------------------

  Widget _buildLocationCard(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    AsyncValue<LocationStatus> location,
  ) {
    final LocationStatus? status = location.value;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (status == null)
            Row(
              children: <Widget>[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(l10n.fetchingLocation),
              ],
            )
          else ...<Widget>[
            _StatusRow(
              icon: status.serviceEnabled ? Icons.gps_fixed : Icons.gps_off,
              label: l10n.locationStatusGps,
              value: status.serviceEnabled
                  ? l10n.locationGpsOn
                  : l10n.locationGpsOff,
              ok: status.serviceEnabled,
            ),
            const SizedBox(height: 10),
            _StatusRow(
              icon: status.permissionGranted
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              label: l10n.locationStatusPermission,
              value: _permissionLabel(l10n, status.permission),
              ok: status.permissionGranted,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () => ref
                .read(locationStatusProvider.notifier)
                .requestAccessFromUser(),
            icon: const Icon(Icons.tune),
            label: Text(l10n.manageLocation),
          ),
        ],
      ),
    );
  }

  String _permissionLabel(
    AppLocalizations l10n,
    LocationPermission permission,
  ) {
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => l10n.locationPermissionGranted,
      LocationPermission.deniedForever => l10n.locationPermissionDeniedForever,
      LocationPermission.denied => l10n.locationPermissionDenied,
      _ => l10n.locationPermissionUnknown,
    };
  }

  // --- Daily GPS tracking ---------------------------------------------------

  Widget _buildGpsCard(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final ThemeData theme = Theme.of(context);
    final bool enabled = ref.watch(gpsTrackingEnabledProvider);
    final GpsTrackingState tracking = ref.watch(gpsTrackingControllerProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(Icons.route, color: theme.colorScheme.primary),
            title: Text(l10n.dailyGpsToggle),
            subtitle: Text(l10n.dailyGpsToggleSubtitle),
            value: enabled,
            onChanged: (bool value) => _toggleGps(context, ref, l10n, value),
          ),
          if (enabled) ...<Widget>[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _DailyGpsSummaryTile(state: tracking, l10n: l10n),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleGps(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    bool value,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await ref.read(gpsTrackingEnabledProvider.notifier).setEnabled(value);
    if (value) {
      // After enabling, surface a hint when GPS or the permission is missing;
      // the tracker itself stays off until the user grants access.
      await ref.read(locationStatusProvider.notifier).refresh();
      final LocationStatus? status = ref.read(locationStatusProvider).value;
      if (status != null && status.needsAction) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.dailyGpsPermissionHint)),
        );
      }
    }
  }

  // --- AutoMotion ------------------------------------------------------------

  Widget _buildAutoMotionCard(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final ThemeData theme = Theme.of(context);
    final bool enabled = ref.watch(autoMotionEnabledProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: Icon(
          Icons.directions_walk,
          color: theme.colorScheme.primary,
        ),
        title: Text(l10n.autoMotionToggle),
        subtitle: Text(l10n.autoMotionToggleSubtitle),
        value: enabled,
        onChanged: (bool value) =>
            _toggleAutoMotion(context, ref, l10n, value),
      ),
    );
  }

  Future<void> _toggleAutoMotion(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    bool value,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await ref.read(autoMotionEnabledProvider.notifier).setEnabled(value);
    if (value) {
      // After enabling, surface a hint when GPS or the permission is missing;
      // the tracker itself stays off until the user grants access.
      await ref.read(locationStatusProvider.notifier).refresh();
      final LocationStatus? status = ref.read(locationStatusProvider).value;
      if (status != null && status.needsAction) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.autoMotionPermissionHint)),
        );
      }
    }
  }

  // --- Sync & backup ---------------------------------------------------------

  Widget _buildSyncCard(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    SyncState sync,
  ) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.cloud_done_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  sync.lastSynced == null
                      ? l10n.neverSynced
                      : l10n.lastSynced(
                          formatDateTime(
                            sync.lastSynced!,
                            Localizations.localeOf(context).toString(),
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.localOverridesCloud,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: sync.isSyncing
                ? null
                : () => ref.read(syncControllerProvider.notifier).syncNow(),
            icon: sync.isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(sync.isSyncing ? l10n.syncInProgress : l10n.syncNow),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: sync.isSyncing
                ? null
                : () => _confirmRestore(context, ref, l10n),
            icon: const Icon(Icons.settings_backup_restore_outlined),
            label: Text(l10n.restoreFromDrive),
          ),
        ],
      ),
    );
  }

  // --- Privacy & security ----------------------------------------------------

  Widget _buildPrivacyCard(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    int hiddenCount,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.lock_outline),
      title: Text(l10n.hiddenVault),
      subtitle: Text(l10n.hiddenVaultSubtitle(hiddenCount)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openHiddenVault(context, ref, l10n),
    );
  }

  Future<void> _openHiddenVault(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);

    // Unhiding must never trap the user's data, so an unverifiable device is
    // allowed through rather than locking the vault forever.
    final bool allowed = await ensureUnlocked(
      ref,
      l10n: l10n,
      reason: l10n.unlockToOpenVault,
      messenger: messenger,
      allowWhenUnavailable: true,
    );
    if (!allowed) return;

    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => const HiddenVaultScreen()),
    );
  }

  // --- Preferences -----------------------------------------------------------

  Widget _buildPreferencesCard(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Locale? locale,
    ThemeMode themeMode,
    PreferredNavApp navApp,
  ) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.language),
            title: Text(l10n.selectLanguage),
            trailing: DropdownButton<Locale?>(
              value: locale,
              underline: const SizedBox.shrink(),
              items: <DropdownMenuItem<Locale?>>[
                DropdownMenuItem<Locale?>(
                  value: null,
                  child: Text(l10n.languageSystem),
                ),
                DropdownMenuItem<Locale?>(
                  value: const Locale('en'),
                  child: Text(l10n.languageEnglish),
                ),
                DropdownMenuItem<Locale?>(
                  value: const Locale('ar'),
                  child: Text(l10n.languageArabic),
                ),
              ],
              onChanged: (Locale? value) =>
                  ref.read(localeControllerProvider.notifier).setLocale(value),
            ),
          ),
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.navigation_outlined),
            title: Text(l10n.preferredNavApp),
            subtitle: Text(l10n.preferredNavAppSubtitle),
            trailing: DropdownButton<PreferredNavApp>(
              value: navApp,
              underline: const SizedBox.shrink(),
              items: <DropdownMenuItem<PreferredNavApp>>[
                DropdownMenuItem<PreferredNavApp>(
                  value: PreferredNavApp.system,
                  child: Text(l10n.navAppSystem),
                ),
                DropdownMenuItem<PreferredNavApp>(
                  value: PreferredNavApp.googleMaps,
                  child: Text(l10n.navAppGoogleMaps),
                ),
                DropdownMenuItem<PreferredNavApp>(
                  value: PreferredNavApp.waze,
                  child: Text(l10n.navAppWaze),
                ),
              ],
              onChanged: (PreferredNavApp? value) {
                if (value != null) {
                  ref
                      .read(preferredNavAppProvider.notifier)
                      .setPreferredApp(value);
                }
              },
            ),
          ),
          const Divider(height: 24),
          Row(
            children: <Widget>[
              const Icon(Icons.dark_mode_outlined, size: 20),
              const SizedBox(width: 12),
              Text(l10n.appearance, style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _ThemeChoice(
                label: l10n.themeSystem,
                icon: Icons.brightness_auto,
                value: ThemeMode.system,
                selected: themeMode,
                onSelected: (ThemeMode value) =>
                    ref.read(themeModeProvider.notifier).setThemeMode(value),
              ),
              _ThemeChoice(
                label: l10n.themeLight,
                icon: Icons.light_mode,
                value: ThemeMode.light,
                selected: themeMode,
                onSelected: (ThemeMode value) =>
                    ref.read(themeModeProvider.notifier).setThemeMode(value),
              ),
              _ThemeChoice(
                label: l10n.themeDark,
                icon: Icons.dark_mode,
                value: ThemeMode.dark,
                selected: themeMode,
                onSelected: (ThemeMode value) =>
                    ref.read(themeModeProvider.notifier).setThemeMode(value),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Smart insights --------------------------------------------------------

  Widget _buildAgentCard(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final ThemeData theme = Theme.of(context);
    final bool cloudAvailable = AppConfig.isGeminiConfigured;
    final bool insightsEnabled = ref.watch(smartInsightsEnabledProvider);
    final bool cloudEnabled = ref.watch(cloudAiEnabledProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Master switch: hide or show the whole Smart Insights feature.
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              Icons.auto_awesome,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.smartInsightsEnable),
            subtitle: Text(l10n.smartInsightsEnableSubtitle),
            value: insightsEnabled,
            onChanged: (bool value) => ref
                .read(smartInsightsEnabledProvider.notifier)
                .setEnabled(value),
          ),
          if (insightsEnabled) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.smartInsightsTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: l10n.smartInsightsRefresh,
                  onPressed: () => ref.read(agentProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            const SmartInsightsList(showWhenEmpty: true),
            if (cloudAvailable) ...<Widget>[
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.cloud_outlined),
                title: Text(l10n.smartInsightsCloudAi),
                subtitle: Text(l10n.smartInsightsCloudAiSubtitle),
                value: cloudEnabled,
                onChanged: (bool value) =>
                    ref.read(cloudAiEnabledProvider.notifier).setEnabled(value),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // --- About -----------------------------------------------------------------

  Widget _buildAboutCard(BuildContext context, AppLocalizations l10n) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Brand lockup: the horizontal wordmark centred over the blurb, so
          // the About section doubles as the app's branding page.
          const Center(
            child: BrandLogo(BrandAssets.lockupHorizontal, width: 220),
          ),
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
              Text(
                'v${AppConfig.appVersion}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Actions ---------------------------------------------------------------

  Future<void> _signIn(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authProvider.notifier).signIn();
      await ref.read(syncControllerProvider.notifier).syncNow();
    } on AuthException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.signInFailed(e.message))),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
    }
  }

  Future<void> _signOut(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    await ref.read(authProvider.notifier).signOut();
  }

  Future<void> _confirmRestore(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.restoreConfirmTitle),
        content: Text(l10n.restoreConfirmMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.restoreFromDrive),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(syncControllerProvider.notifier).restoreFromDrive();
    }
  }
}

/// Section header + card container used to group related settings.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(child: child),
        ],
      ),
    );
  }
}

/// A label/value row with a status colour, e.g. "GPS — On".
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.ok,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = ok
        ? theme.colorScheme.primary
        : theme.colorScheme.error;
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// One option in the theme-mode selector.
class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.label,
    required this.icon,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final ThemeMode value;
  final ThemeMode selected;
  final ValueChanged<ThemeMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selected: value == selected,
      onSelected: (_) => onSelected(value),
    );
  }
}

/// Today's distance / max-speed report shown under the GPS tracking toggle.
class _DailyGpsSummaryTile extends StatelessWidget {
  const _DailyGpsSummaryTile({required this.state, required this.l10n});

  final GpsTrackingState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (state.unavailable)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.gps_off,
                  size: 16,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.dailyGpsUnavailable,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: <Widget>[
            Expanded(
              child: _DailyGpsMetric(
                icon: Icons.straighten,
                label: l10n.dailyDistance,
                value: '${state.totalKm.toStringAsFixed(2)} ${l10n.kmUnit}',
              ),
            ),
            Expanded(
              child: _DailyGpsMetric(
                icon: Icons.speed,
                label: l10n.dailyMaxSpeed,
                value: '${state.maxSpeedKmh.toStringAsFixed(1)} '
                    '${l10n.kmhUnit}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Icon(
              state.active ? Icons.gps_fixed : Icons.pause_circle_outline,
              size: 16,
              color: state.active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              state.active ? l10n.dailyTrackingActive : l10n.dailyTrackingPaused,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A single labelled number in the daily GPS summary (distance / max speed).
class _DailyGpsMetric extends StatelessWidget {
  const _DailyGpsMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
