import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../data/models/backup_data.dart';
import '../../data/models/backup_validator.dart';
import '../../data/models/place.dart';
import '../../data/repositories/place_repository.dart';
import '../../providers/app_providers.dart';
import 'sync_conflict_sheet.dart';

/// Manual `.mapnote` recovery: export the same versioned, checksummed envelope
/// that Drive uses, or paste one back in. No new file-picker dependency is
/// needed — the clipboard is already used elsewhere in the app — and importing
/// always merges, never silently replaces local places.
class RecoverySettingsScreen extends ConsumerStatefulWidget {
  const RecoverySettingsScreen({super.key});

  @override
  ConsumerState<RecoverySettingsScreen> createState() =>
      _RecoverySettingsScreenState();
}

class _RecoverySettingsScreenState
    extends ConsumerState<RecoverySettingsScreen> {
  final TextEditingController _pasteController = TextEditingController();

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final bool importing = ref.watch(syncControllerProvider).isSyncing;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.recoveryTitle)),
      body: ListView(
        padding: const EdgeInsetsDirectional.all(16),
        children: <Widget>[
          Text(
            l10n.recoverySubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.copy_all_outlined),
            label: Text(l10n.recoveryExport),
            onPressed: _export,
          ),
          const Divider(height: 32),
          Text(
            l10n.recoveryImportTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.recoveryImportMessage,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pasteController,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: l10n.recoveryPasteHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.restore),
            label: Text(importing ? l10n.syncInProgress : l10n.recoveryImport),
            onPressed: importing ? null : _import,
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final PlaceRepository repository = ref.read(placeRepositoryProvider);
    final List<Place> places = await repository.getAllIncludingDeleted();
    await Clipboard.setData(ClipboardData(text: BackupData(places: places).toRaw()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.recoveryExportDone)),
    );
  }

  Future<void> _import() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String raw = _pasteController.text.trim();
    // Parse here so a malformed payload never reaches the controller's generic
    // error path: the message is localized and the clipboard stays untouched.
    final BackupEnvelope envelope;
    try {
      envelope = parseBackupEnvelope(raw);
    } on BackupValidationException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.recoveryImportInvalid)),
      );
      return;
    }

    await ref
        .read(syncControllerProvider.notifier)
        .importRecoveryBackup(raw);
    if (!mounted) return;

    final SyncState sync = ref.read(syncControllerProvider);
    if (sync.status == SyncStatus.conflict) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const SyncConflictSheet(),
      );
      return;
    }
    if (sync.status == SyncStatus.error) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.recoveryImported(envelope.places.length),
        ),
      ),
    );
  }
}
