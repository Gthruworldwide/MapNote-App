import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/place.dart';
import '../../../data/models/station_manager.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_providers.dart';
import '../../../services/manager_contact_service.dart';

/// "Station manager" section on the place-detail screen.
///
/// Renders one row per manager shipped with the seeded catalogue, with a direct
/// call and WhatsApp action. The buttons appear only for a manager that actually
/// has a phone number: a dead button would be worse than an explicit
/// "no number on file yet" hint, because the first catalogue ships names only.
class StationManagersCard extends ConsumerWidget {
  const StationManagersCard({super.key, required this.place});

  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<StationManager> managers = place.managers;
    if (managers.isEmpty) return const SizedBox.shrink();

    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.support_agent, size: 20, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.stationManagersTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            for (final StationManager manager in managers) ...<Widget>[
              const SizedBox(height: 12),
              _ManagerRow(
                manager: manager,
                stationName: place.name,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ManagerRow extends ConsumerWidget {
  const _ManagerRow({required this.manager, required this.stationName});

  final StationManager manager;
  final String stationName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                manager.name,
                style: theme.textTheme.bodyLarge,
              ),
              if (manager.hasPhone)
                Text(
                  manager.phone!,
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                )
              else
                Text(
                  l10n.managerPhoneMissing,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        if (manager.hasPhone) ...<Widget>[
          IconButton(
            tooltip: l10n.callManager,
            onPressed: () => _call(context, ref, l10n),
            style: IconButton.styleFrom(
              backgroundColor: colors.primary.withValues(alpha: 0.10),
              foregroundColor: colors.primary,
            ),
            icon: const Icon(Icons.call_outlined, size: 20),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: l10n.messageManagerOnWhatsApp,
            onPressed: () => _message(context, ref, l10n),
            style: IconButton.styleFrom(
              backgroundColor: colors.primary.withValues(alpha: 0.10),
              foregroundColor: colors.primary,
            ),
            icon: const Icon(Icons.chat_outlined, size: 20),
          ),
        ],
      ],
    );
  }

  Future<void> _call(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ManagerContactService contact = ref.read(managerContactServiceProvider);
    final bool launched = await contact.call(manager.phone!);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.managerContactUnavailable)),
      );
    }
  }

  Future<void> _message(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ManagerContactService contact = ref.read(managerContactServiceProvider);
    final bool launched = await contact.whatsApp(
      manager.phone!,
      message: l10n.managerWhatsAppMessage(manager.name, stationName),
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.managerContactUnavailable)),
      );
    }
  }
}
