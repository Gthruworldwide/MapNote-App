import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../core/utils/date_formats.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/place.dart';
import '../../data/remote/auth_service.dart';
import '../../data/repositories/sync_repository.dart';
import '../../providers/app_providers.dart';
import '../../services/lock_gate.dart';
import '../saved_places/presentation/saved_places_vault_screen.dart';
import 'hidden_vault_screen.dart';
import 'settings_shared.dart';

/// Account & cloud backup settings: Google account, Drive sync/restore,
/// the hidden vault entry point and the encrypted saved-places vault.
class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<AuthUser?> auth = ref.watch(authProvider);
    final SyncState sync = ref.watch(syncControllerProvider);
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
      appBar: AppBar(title: Text(l10n.sectionAccount)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SettingsSection(
            title: l10n.accountAndBackup,
            child: grouped(<Widget>[
              _buildAccountCard(context, ref, l10n, auth),
              _buildSyncCard(context, ref, l10n, sync),
              _buildPrivacyCard(context, ref, l10n, hiddenCount),
              if (ref.watch(biometricVaultEnabledProvider))
                _buildEncryptedVaultCard(context, l10n),
            ]),
          ),
        ],
      ),
    );
  }

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

  Future<void> _openHiddenVault(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);

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
}
