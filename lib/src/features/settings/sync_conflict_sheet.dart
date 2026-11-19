import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../data/services/sync_merge.dart';
import '../../providers/app_providers.dart';

/// Lists every record whose local and cloud edits cannot be ordered safely.
///
/// The three choices map 1:1 onto [SyncResolution]. Nothing is written until
/// the user picks one; the unresolved local copy stays on the device.
class SyncConflictSheet extends ConsumerWidget {
  const SyncConflictSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final SyncState sync = ref.watch(syncControllerProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              l10n.syncConflictTitle,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.syncConflictMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: sync.conflicts.length,
                separatorBuilder: (_, _) => const Divider(height: 16),
                itemBuilder: (BuildContext context, int index) {
                  final SyncConflict conflict = sync.conflicts[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.syncConflictPlaceLabel(
                          conflict.local.name,
                          conflict.cloud.name,
                        ),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          OutlinedButton(
                            onPressed: () =>
                                _resolve(context, ref, conflict, SyncResolution.keepLocal, l10n),
                            child: Text(l10n.syncConflictKeepLocal),
                          ),
                          OutlinedButton(
                            onPressed: () =>
                                _resolve(context, ref, conflict, SyncResolution.useCloud, l10n),
                            child: Text(l10n.syncConflictUseCloud),
                          ),
                          FilledButton.tonal(
                            onPressed: () =>
                                _resolve(context, ref, conflict, SyncResolution.merge, l10n),
                            child: Text(l10n.syncConflictMerge),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    SyncConflict conflict,
    SyncResolution choice,
    AppLocalizations l10n,
  ) async {
    await ref
        .read(syncControllerProvider.notifier)
        .resolveConflict(conflict, choice);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.syncConflictResolved)),
    );
    if (ref.read(syncControllerProvider).hasConflicts) return;
    // ignore: use_build_context_synchronously
    Navigator.of(context).pop();
  }
}
