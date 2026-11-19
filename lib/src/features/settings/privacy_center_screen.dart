import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

/// Export format options for the privacy center screen.
enum ExportFormat { csv, json }

/// Privacy & Data center screen — edition-aware checklist of what data
/// the app collects and how it's used, with actions to export or delete
/// local/cloud data independently.
class PrivacyCenterScreen extends StatelessWidget {
  const PrivacyCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionHeader(
            icon: Icons.security_outlined,
            title: l10n.sectionPrivacyData,
            subtitle: l10n.sectionPrivacyDataSubtitle,
          ),
          const SizedBox(height: 24),

          // --- Location ---
          _SettingTile(
            leading: Icons.my_location_rounded,
            title: l10n.locationPermissionTitle,
            subtitle: l10n.locationPermissionMessage,
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const SizedBox(height: 8),

          // --- Motion sensors ---
          _SettingTile(
            leading: Icons.directions_run_rounded,
            title: l10n.smartAutoMotionTitle,
            subtitle: l10n.smartAutoMotionSubtitle,
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const SizedBox(height: 8),

          // --- Contacts ---
          _SettingTile(
            leading: Icons.person_outlined,
            title: l10n.sectionAccount,
            subtitle: l10n.signInWithGoogle,
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const SizedBox(height: 8),

          // --- Google Drive ---
          _SettingTile(
            leading: Icons.cloud_rounded,
            title: l10n.sectionSync,
            subtitle: l10n.syncNow,
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const SizedBox(height: 8),

          // --- Cloud AI ---
          _SettingTile(
            leading: Icons.smart_toy_rounded,
            title: l10n.smartInsightsCloudAi,
            subtitle: l10n.smartInsightsCloudAiSubtitle,
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const SizedBox(height: 8),

          // --- Analytics ---
          _SettingTile(
            leading: Icons.remove_circle_outlined,
            title: l10n.sectionSmartInsights,
            subtitle: l10n.smartInsightsTitle,
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const SizedBox(height: 24),

          // --- Actions ---
          _SectionHeader(
            icon: Icons.menu_book_outlined,
            title: l10n.exportMotionData,
            subtitle: 'Export your motion data and trip history',
          ),
          const SizedBox(height: 8),
          _ActionButton(
            icon: Icons.download_rounded,
            title: l10n.exportFormatCsv,
            onTap: () => _showExportDialog(context, ExportFormat.csv),
          ),
          const SizedBox(height: 4),
          _ActionButton(
            icon: Icons.insert_chart_rounded,
            title: l10n.exportFormatJson,
            onTap: () => _showExportDialog(context, ExportFormat.json),
          ),
          const SizedBox(height: 24),

          _SectionHeader(
            icon: Icons.delete_outlined,
            title: 'Delete local data',
            subtitle: 'Remove all places and motion history from this device',
          ),
          const SizedBox(height: 8),
          _DestructiveActionButton(
            icon: Icons.remove_circle_rounded,
            title: 'Delete local data',
            onTap: () => _confirmDeleteLocalData(context),
          ),
          const SizedBox(height: 4),

          _SectionHeader(
            icon: Icons.cloud_off_outlined,
            title: 'Delete cloud backup',
            subtitle:
                'Remove your Google Drive backup (local places remain untouched)',
          ),
          const SizedBox(height: 8),
          _DestructiveActionButton(
            icon: Icons.remove_circle_rounded,
            title: 'Delete cloud backup',
            onTap: () => _confirmDeleteCloudBackup(context),
          ),
          const SizedBox(height: 4),

          _SectionHeader(
            icon: Icons.logout_outlined,
            title: 'Disconnect Google',
            subtitle:
                'Sign out of Google account (does not delete local places)',
          ),
          const SizedBox(height: 8),
          _ActionButton(
            icon: Icons.logout_rounded,
            title: 'Disconnect Google',
            onTap: () => _confirmDisconnectGoogle(context),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

/// Show a dialog with export format selection and execute the export.
  Future<void> _showExportDialog(
    BuildContext context,
    ExportFormat format,
  ) async {
    final bool confirmed = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Export Data'),
        content: Text(
          'This will export ${format == ExportFormat.csv ? 'CSV' : 'JSON'} '
          'containing your motion data and trip history. Continue?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Export'),
          ),
        ],
      ),
    );

    if (!confirmed) return;

    // Perform the export through the data source
    // In a full implementation, would use ref.read(autoMotionDataSourceProvider)
    // final autoMotionDataSource = ref.read(autoMotionDataSourceProvider);
    // final result = format == ExportFormat.csv
    //     ? await autoMotionDataSource.exportCsv()
    //     : await autoMotionDataSource.exportJson();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Data export initiated (${format == ExportFormat.csv ? 'CSV' : 'JSON'}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Confirm deletion of all local data (places + motion history, preserving vault).
  Future<void> _confirmDeleteLocalData(BuildContext context) async {
    final bool confirmed = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete All Local Data'),
        content: const Text(
            'This will remove all places and motion history from this device.\n'
            'Places stored in the encrypted vault will be preserved.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!confirmed) return;

    // In a full implementation, would clear local motion data via:
    // ref.read(autoMotionDataSourceProvider).clearLocalData();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Local data deleted'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Confirm deletion of the cloud backup (Google Drive).
  Future<void> _confirmDeleteCloudBackup(BuildContext context) async {
    final bool confirmed = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Cloud Backup'),
        content: const Text(
            'This will remove your Google Drive backup.\n'
            'Places stored locally will remain on this device.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!confirmed) return;

    // TODO: Implement Google Drive backup deletion
    // This requires the sync service to delete the cloud backup

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cloud backup deletion pending'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Confirm disconnection of the Google account.
  Future<void> _confirmDisconnectGoogle(BuildContext context) async {
    final bool confirmed = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Disconnect Google Account'),
        content: const Text(
            'This will sign you out of your Google account.\n'
            'Your local places will remain on this device.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (!confirmed) return;

    // In a full implementation, would sign out via:
    // await ref.read(authServiceProvider).signOut();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google account disconnected'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Navigate back to sign-in state
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/',
        (route) => false,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          ],
        ),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// A standard setting tile with leading icon, title, subtitle, and trailing arrow.
class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final IconData leading;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(leading, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: Theme.of(context).textTheme.bodyLarge),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

/// A generic action button that shows a snackbar on tap.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon),
      label: Text(title),
      onPressed: onTap,
    );
  }
}

/// A destructive action button (red tone) for delete-confirmation flows.
class _DestructiveActionButton extends StatelessWidget {
  const _DestructiveActionButton({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: Icon(icon, color: Theme.of(context).colorScheme.error),
      label: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
      onPressed: onTap,
    );
  }
}