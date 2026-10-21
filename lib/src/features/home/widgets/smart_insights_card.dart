import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../data/models/agent_insight.dart';
import '../../../providers/app_providers.dart';

/// A subtle "Smart Insights" card for the Home screen.
///
/// It renders the agent's recommendations and stays completely invisible while
/// there is nothing to suggest (unless [showWhenEmpty] is set).
class SmartInsightsCard extends ConsumerWidget {
  const SmartInsightsCard({super.key, this.showWhenEmpty = false});

  final bool showWhenEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<AgentInsight> insights =
        ref.watch(agentProvider).value ?? const <AgentInsight>[];
    if (insights.isEmpty && !showWhenEmpty) return const SizedBox.shrink();

    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 8),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
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
                IconButton(
                  tooltip: l10n.smartInsightsRefresh,
                  onPressed: () => ref.read(agentProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: SmartInsightsList(showWhenEmpty: showWhenEmpty),
            ),
          ],
        ),
      ),
    );
  }
}

/// The bare list of insight tiles, used inside the Home card and the Settings
/// section (which supplies its own header).
class SmartInsightsList extends ConsumerWidget {
  const SmartInsightsList({super.key, this.showWhenEmpty = false});

  final bool showWhenEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<AgentInsight> insights =
        ref.watch(agentProvider).value ?? const <AgentInsight>[];
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    if (insights.isEmpty) {
      if (!showWhenEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.smartInsightsEmpty,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            // A concrete hint tells the user how the feature becomes useful.
            Text(
              l10n.smartInsightsEmptyHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: insights
          .map((AgentInsight insight) => _InsightTile(insight: insight))
          .toList(growable: false),
    );
  }
}

class _InsightTile extends ConsumerWidget {
  const _InsightTile({required this.insight});

  final AgentInsight insight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ({String title, String body}) text = _resolveText(l10n, insight);
    final (IconData, Color) style = _severityStyle(theme, insight.severity);
    final IconData icon = style.$1;
    final Color color = style.$2;
    final String title = text.title;
    final String body = text.body;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (insight.action == AgentInsightAction.syncNow)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: TextButton.icon(
                      onPressed: () => ref
                          .read(syncControllerProvider.notifier)
                          .syncNow(userInitiated: true),
                      icon: const Icon(Icons.cloud_sync_outlined, size: 18),
                      label: Text(l10n.insightActionSyncNow),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.smartInsightsDismiss,
            onPressed: () =>
                ref.read(agentProvider.notifier).dismiss(insight.id),
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

({String title, String body}) _resolveText(
  AppLocalizations l10n,
  AgentInsight insight,
) {
  switch (insight.kind) {
    case AgentInsightKind.custom:
      return (title: insight.customTitle ?? '', body: insight.customBody ?? '');
    case AgentInsightKind.welcome:
      return (title: l10n.insightWelcomeTitle, body: l10n.insightWelcomeBody);
    case AgentInsightKind.nearbyDuplicates:
      return (
        title: l10n.insightNearbyDuplicatesTitle,
        body: l10n.insightNearbyDuplicatesBody(_int(insight, 'count', 2)),
      );
    case AgentInsightKind.unorganizedPlaces:
      return (
        title: l10n.insightUnorganizedTitle,
        body: l10n.insightUnorganizedBody(_int(insight, 'count', 0)),
      );
    case AgentInsightKind.syncIssues:
      return (
        title: l10n.insightSyncIssuesTitle,
        body: l10n.insightSyncIssuesBody(_int(insight, 'count', 1)),
      );
    case AgentInsightKind.networkWarning:
      return (
        title: l10n.insightNetworkWarningTitle,
        body: l10n.insightNetworkWarningBody,
      );
    case AgentInsightKind.parseIssues:
      return (
        title: l10n.insightParseIssuesTitle,
        body: l10n.insightParseIssuesBody(_int(insight, 'count', 2)),
      );
    case AgentInsightKind.staleBackup:
      final int days = _int(insight, 'days', 0);
      return (
        title: l10n.insightStaleBackupTitle,
        body: days <= 0
            ? l10n.insightStaleBackupNeverBody
            : l10n.insightStaleBackupBody(days),
      );
    case AgentInsightKind.pinFavorites:
      return (
        title: l10n.insightPinFavoritesTitle,
        body: l10n.insightPinFavoritesBody(_int(insight, 'count', 0)),
      );
    case AgentInsightKind.optimization:
      return (
        title: l10n.insightOptimizationTitle,
        body: l10n.insightOptimizationBody,
      );
  }
}

int _int(AgentInsight insight, String key, int fallback) {
  final Object? value = insight.params[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return fallback;
}

(IconData, Color) _severityStyle(
  ThemeData theme,
  AgentInsightSeverity severity,
) {
  return switch (severity) {
    AgentInsightSeverity.warning => (
      Icons.warning_amber_rounded,
      theme.colorScheme.error,
    ),
    AgentInsightSeverity.suggestion => (
      Icons.lightbulb_outline,
      theme.colorScheme.primary,
    ),
    AgentInsightSeverity.info => (
      Icons.info_outline,
      theme.colorScheme.tertiary,
    ),
  };
}
