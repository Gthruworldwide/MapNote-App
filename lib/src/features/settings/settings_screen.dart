import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../core/brand/brand_lockup.dart';
import '../../core/config/app_config.dart';
import '../../core/config/preferred_nav_app.dart';
import '../../core/security/session_guard.dart';
import '../../core/utils/date_formats.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/place.dart';
import '../../data/remote/auth_service.dart';
import '../../data/local/settings_repository.dart';
import '../../data/repositories/sync_repository.dart';
import '../../providers/app_providers.dart';
import '../../services/daily_track_engine.dart';
import '../../services/location_service.dart';
import '../../services/lock_gate.dart';
import '../../widgets/track_failure_text.dart';
import '../saved_places/presentation/saved_places_vault_screen.dart';
import 'hidden_vault_screen.dart';
import '../automotion/widgets/auto_motion_export_sheet.dart';

/// Settings, consolidated into four Apple-style grouped cards:
/// account & cloud backup, location & tracking, preferences, and about.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<AuthUser?> auth = ref.watch(authProvider);
    final SyncState sync = ref.watch(syncControllerProvider);
    final Locale? locale = ref.watch(localeControllerProvider);
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    final FontScalePreset fontScale = ref.watch(fontScaleProvider);
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
          // 1. Account & Cloud Backup: profile, sign out, Drive sync, vault.
          _SettingsSection(
            title: l10n.accountAndBackup,
            child: _grouped(<Widget>[
              _buildAccountCard(context, ref, l10n, auth),
              _buildSyncCard(context, ref, l10n, sync),
              _buildPrivacyCard(context, ref, l10n, hiddenCount),
              _buildEncryptedVaultCard(context, l10n),
              _subHeader(context, l10n.vaultProtectionTitle),
              _buildVaultProtectionCard(context, ref, l10n),
            ]),
          ),
          // 2. Location & Tracking: permissions, then the single merged
          //    AutoMotion + Daily GPS tracking card and its today report.
          _SettingsSection(
            title: l10n.sectionLocationTracking,
            child: _grouped(<Widget>[
              _buildLocationCard(context, ref, l10n, location),
              _subHeader(context, l10n.autoMotionSection),
              _buildTrackingCard(context, ref, l10n),
            ]),
          ),
          // 3. Preferences: navigation app, language, theme, Smart Insights.
          _SettingsSection(
            title: l10n.sectionPreferences,
            child: _grouped(<Widget>[
              _buildPreferencesCard(
                context,
                ref,
                l10n,
                locale,
                themeMode,
                navApp,
                fontScale,
              ),
              _buildAgentCard(context, ref, l10n),
            ]),
          ),
          // 4. About MapNote.
          _SettingsSection(
            title: l10n.aboutTitle,
            child: _buildAboutCard(context, l10n),
          ),
        ],
      ),
    );
  }

  /// Stacks the sub-cards of a consolidated settings card, separated by a
  /// hairline divider rather than another full section header.
  Widget _grouped(List<Widget> parts) {
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < parts.length; i++) {
      if (i > 0) {
        children.add(const Divider(height: 1, indent: 16, endIndent: 16));
      }
      children.add(parts[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// A sub-header inside a consolidated card, e.g. "AutoMotion".
  Widget _subHeader(BuildContext context, String title) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
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

  // --- Daily tracking (AutoMotion + Daily GPS tracking) ----------------------

  /// One merged tracking card: the AutoMotion and Daily-GPS switches, followed
  /// by a single "today" report. Keeping exactly one report block means no
  /// metric is ever rendered twice — the block covers whichever engines are on.
  Widget _buildTrackingCard(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final ThemeData theme = Theme.of(context);
    final bool autoMotionEnabled = ref.watch(autoMotionEnabledProvider);
    final bool gpsEnabled = ref.watch(gpsTrackingEnabledProvider);
    final AutoMotionState motion = ref.watch(autoMotionControllerProvider);
    final GpsTrackingState tracking = ref.watch(gpsTrackingControllerProvider);
    // The two engines sample the same trip: report the more complete one so
    // the card never reads 0.00 km while the other engine already recorded
    // today's motion.
    final bool anyActive = tracking.active || motion.active;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              Icons.directions_walk,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.smartAutoMotionTitle),
            subtitle: Text(l10n.smartAutoMotionSubtitle),
            value: autoMotionEnabled || gpsEnabled,
            onChanged: (bool value) async {
              await ref.read(autoMotionEnabledProvider.notifier).setEnabled(value);
              await ref.read(gpsTrackingEnabledProvider.notifier).setEnabled(value);
            },
          ),
          if (autoMotionEnabled || gpsEnabled) ...<Widget>[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _TrackingSummaryTile(
              totalKm: math.max(tracking.totalKm, motion.totalKm),
              maxSpeedKmh: math.max(tracking.maxSpeedKmh, motion.maxSpeedKmh),
              active: anyActive,
              // Warn only when nothing is actually recording: a stale failure
              // from one engine must not claim "unavailable" while the other
              // engine is producing today's numbers.
              unavailable:
                  !anyActive && (tracking.unavailable || motion.unavailable),
              // Prefer the GPS engine's specific reason, then AutoMotion's.
              failure: tracking.failure != TrackStartFailure.none
                  ? tracking.failure
                  : motion.failure,
              onManageLocation: () => _manageTrackingLocation(context, ref),
              l10n: l10n,
            ),
          ],
        ],
      ),
    );
  }

  /// Re-reads location access and restarts whichever engines are switched on,
  /// mirroring the AutoMotion card's one-tap recovery action.
  Future<void> _manageTrackingLocation(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await ref.read(locationStatusProvider.notifier).requestAccessFromUser();
    if (!context.mounted) return;
    if (ref.read(gpsTrackingEnabledProvider)) {
      await ref.read(gpsTrackingControllerProvider.notifier).start();
    }
    if (ref.read(autoMotionEnabledProvider)) {
      await ref.read(autoMotionControllerProvider.notifier).start();
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
                : () => ref
                      .read(syncControllerProvider.notifier)
                      .syncNow(userInitiated: true),
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

  /// Entry point for the AES-256 encrypted vault. The verification prompt is
  /// raised by the screen itself (it gates the decryption key, not the route),
  /// so this only navigates.
  Widget _buildEncryptedVaultCard(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.enhanced_encryption_outlined),
      title: Text(l10n.savedPlacesVault),
      subtitle: Text(l10n.savedPlacesVaultSubtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SavedPlacesVaultScreen(),
        ),
      ),
    );
  }

  // --- Vault protection ------------------------------------------------------

  /// The two vault-session controls: how long the vault may stay unlocked, and
  /// whether reaching the device lock screen ends the session at once.
  Widget _buildVaultProtectionCard(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final ThemeData theme = Theme.of(context);
    final int minutes = ref.watch(sessionTimeoutProvider);
    final bool lockOnDeviceLock = ref.watch(lockOnDeviceLockProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
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

  // --- Preferences -----------------------------------------------------------

  Widget _buildPreferencesCard(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Locale? locale,
    ThemeMode themeMode,
    PreferredNavApp navApp,
    FontScalePreset fontScale,
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
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.text_fields),
            title: Text(l10n.fontScale),
            trailing: DropdownButton<FontScalePreset>(
              value: fontScale,
              underline: const SizedBox.shrink(),
              items: <DropdownMenuItem<FontScalePreset>>[
                DropdownMenuItem<FontScalePreset>(
                  value: FontScalePreset.small,
                  child: Text(l10n.fontScaleSmall),
                ),
                DropdownMenuItem<FontScalePreset>(
                  value: FontScalePreset.standard,
                  child: Text(l10n.fontScaleStandard),
                ),
                DropdownMenuItem<FontScalePreset>(
                  value: FontScalePreset.large,
                  child: Text(l10n.fontScaleLarge),
                ),
                DropdownMenuItem<FontScalePreset>(
                  value: FontScalePreset.extraLarge,
                  child: Text(l10n.fontScaleExtraLarge),
                ),
              ],
              onChanged: (FontScalePreset? value) {
                if (value != null) {
                  ref.read(fontScaleProvider.notifier).setFontScale(value);
                }
              },
            ),
          ),
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.vibration),
            title: Text(l10n.hapticFeedback),
            value: ref.watch(settingsRepositoryProvider).isHapticFeedbackEnabled,
            onChanged: (bool value) =>
                ref.read(settingsRepositoryProvider).setHapticFeedbackEnabled(value),
          ),
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.density_medium),
            title: Text(l10n.uiDensityCompact),
            value: ref.watch(settingsRepositoryProvider).isUiDensityCompact,
            onChanged: (bool value) =>
                ref.read(settingsRepositoryProvider).setUiDensityCompact(value),
          ),
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.file_download_outlined),
            title: Text(l10n.exportMotionData),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const AutoMotionExportBottomSheet(),
            ),
          ),
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.storage_outlined),
            title: Text(l10n.tileCacheSize('0 MB')),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_sweep_outlined),
            title: Text(l10n.clearTileCache),
            onTap: () => showDialog<void>(
              context: context,
              builder: (BuildContext ctx) => AlertDialog(
                title: Text(l10n.clearTileCache),
                content: Text(l10n.clearTileCache),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(l10n.cancel),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.clearTileCache)),
                      );
                    },
                    child: Text(l10n.delete),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_outlined),
            title: Text(l10n.preloadOfflineMaps),
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.offlineMapDownloaded)),
            ),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Master switch: hide or show the whole Smart Insights feature. The
          // suggestions themselves live on the Home screen, so they are not
          // duplicated here — this card only carries the switches.
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
          // the About section doubles as the app's branding page. The splash
          // plays the animated entrance on cold start only; here it is static.
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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

  // --- Actions ---------------------------------------------------------------

  Future<void> _signIn(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authProvider.notifier).signIn();
      await ref
          .read(syncControllerProvider.notifier)
          .syncNow(userInitiated: true);
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
    Haptics.light();
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
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
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

/// Today's distance / max-speed report shown under the merged tracking card.
///
/// Takes plain values (not a single controller's state) because it summarises
/// both engines in one place.
class _TrackingSummaryTile extends StatelessWidget {
  const _TrackingSummaryTile({
    required this.totalKm,
    required this.maxSpeedKmh,
    required this.active,
    required this.unavailable,
    required this.failure,
    required this.onManageLocation,
    required this.l10n,
  });

  final double totalKm;
  final double maxSpeedKmh;
  final bool active;
  final bool unavailable;
  final TrackStartFailure failure;
  final VoidCallback onManageLocation;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (unavailable)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.gps_off,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        trackFailureText(
                          l10n,
                          failure,
                          fallback: l10n.dailyGpsUnavailable,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: onManageLocation,
                    icon: const Icon(Icons.location_on_outlined, size: 18),
                    label: Text(l10n.manageLocation),
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
                value: '${totalKm.toStringAsFixed(2)} ${l10n.kmUnit}',
              ),
            ),
            Expanded(
              child: _DailyGpsMetric(
                icon: Icons.speed,
                label: l10n.dailyMaxSpeed,
                value: '${maxSpeedKmh.toStringAsFixed(1)} ${l10n.kmhUnit}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Icon(
              active ? Icons.gps_fixed : Icons.pause_circle_outline,
              size: 16,
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              active ? l10n.dailyTrackingActive : l10n.dailyTrackingPaused,
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
