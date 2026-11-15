import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../data/models/place.dart';
import '../../../providers/app_providers.dart';
import '../../admin/admin_approval_card.dart';

/// Work Edition "Smart Insights": an offline, `placesProvider`-driven summary of
/// fleet/operations stats, plus the pending admin approval count (best-effort,
/// when Firestore is reachable). It never requires network for the core metrics,
/// never displays coordinates, and renders only from localized strings and theme
/// colors so it stays dark-mode / RTL compliant.
///
/// The personal app uses [SmartInsightsCard] (agent insights) instead; the home
/// screen chooses by [appEditionProvider], and [SmartInsightsCard] also delegates
/// to this view in Work Edition.
class SmartInsightsWidget extends ConsumerWidget {
  const SmartInsightsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final bool isEnabled = ref.watch(smartInsightsEnabledProvider);
    if (!isEnabled) return const SizedBox.shrink();

    final List<Place> places =
        ref.watch(placesProvider).value ?? const <Place>[];
    final _WorkStats stats = _WorkStats.fromPlaces(places);
    // Best-effort: Firestore may be unavailable/offline/uninitialized in tests;
    // core fleet stats above remain fully offline.
    final int pendingApprovals =
        ref.watch(pendingApprovalsCountProvider).asData?.value ?? 0;

    return Card(
      margin: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 8),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.smartInsightsTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StatRow(
              icon: Icons.store_mall_directory_outlined,
              text: l10n.workInsightsStations(stats.stationCount),
              theme: theme,
            ),
            const SizedBox(height: 6),
            _StatRow(
              icon: Icons.contacts_outlined,
              text: l10n.workInsightsManagers(stats.managerContactCount),
              theme: theme,
            ),
            const SizedBox(height: 6),
            _StatRow(
              icon: stats.missingManagerDetails == 0
                  ? Icons.verified_outlined
                  : Icons.contact_phone_outlined,
              text: stats.missingManagerDetails == 0
                  ? l10n.workInsightsNothingMissing
                  : l10n.workInsightsStationsMissingContactsLabel(
                      stats.missingManagerDetails,
                    ),
              theme: theme,
              color: stats.missingManagerDetails == 0
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 6),
            _StatRow(
              icon: Icons.pending_actions_outlined,
              text: l10n.workInsightsPendingApprovals(pendingApprovals),
              theme: theme,
              color: pendingApprovals > 0
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 6),
            _StatRow(
              icon: Icons.label_outline,
              text: l10n.workInsightsWorkTagged(stats.workTaggedCount),
              theme: theme,
            ),
            const SizedBox(height: 10),
            Text(
              l10n.workInsightsTip,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.text,
    required this.theme,
    this.color,
  });

  final IconData icon;
  final String text;
  final ThemeData theme;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color effective = color ?? theme.colorScheme.onSurface;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: effective),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(color: effective),
          ),
        ),
      ],
    );
  }
}

@immutable
class _WorkStats {
  const _WorkStats({
    required this.stationCount,
    required this.managerContactCount,
    required this.missingManagerDetails,
    required this.workTaggedCount,
  });

  final int stationCount;
  final int managerContactCount;
  final int missingManagerDetails;
  final int workTaggedCount;

  factory _WorkStats.fromPlaces(List<Place> places) {
    int managers = 0;
    int missingManagerDetails = 0;
    int workTagged = 0;
    int visibleCount = 0;
    for (final Place place in places) {
      if (place.isHidden) continue;
      visibleCount++;
      managers += place.managers.length;
      final bool hasManagerName =
          (place.displayName?.trim().isNotEmpty ?? false) ||
              place.managers.any((m) => m.name.trim().isNotEmpty);
      final bool hasPhone =
          (place.phoneNumber?.trim().isNotEmpty ?? false) ||
              place.managers.any((m) => m.hasPhone);
      if (!hasManagerName && !hasPhone) {
        missingManagerDetails++;
      }
      final String haystack = '${place.name} ${place.notes}'.toLowerCase();
      if (haystack.contains('#work')) workTagged++;
    }
    return _WorkStats(
      stationCount: visibleCount,
      managerContactCount: managers,
      missingManagerDetails: missingManagerDetails,
      workTaggedCount: workTagged,
    );
  }
}
