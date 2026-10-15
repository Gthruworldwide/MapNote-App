import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../core/utils/date_formats.dart';
import '../../data/models/daily_gps_summary.dart';
import '../../providers/app_providers.dart';
import '../../widgets/motion_metric.dart';
import '../../widgets/track_failure_text.dart';
import '../home/widgets/auto_motion_badge.dart';

/// The full AutoMotion dashboard, opened by tapping the Home status card.
///
/// Shows a live **driver mode** header (current speed, active/paused status and
/// today's distance & max speed) followed by the **trip history** of every
/// recorded day, newest-first. Everything is read from the same offline Hive
/// data the Home card uses — no network calls, and the two daily trackers stay
/// independent.
class AutoMotionScreen extends ConsumerWidget {
  const AutoMotionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AutoMotionState state = ref.watch(autoMotionControllerProvider);
    final List<DailyGpsSummary> history = ref.watch(autoMotionHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.autoMotionDashboardTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _DriverModeCard(state: state),
          const SizedBox(height: 16),
          _HistoryCard(history: history),
        ],
      ),
    );
  }
}

/// Live driver-mode header: status badge, current speed and today's totals,
/// with the shared one-tap location recovery when tracking is unavailable.
class _DriverModeCard extends ConsumerWidget {
  const _DriverModeCard({required this.state});

  final AutoMotionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                AutoMotionBadge(
                  isActive: state.active,
                  isUnavailable: state.unavailable,
                  size: 48,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.autoMotionDriverMode,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _statusLabel(l10n),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: state.unavailable
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // The headline of driver mode: the speed of the latest fix.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  state.currentSpeedKmh.toStringAsFixed(1),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    l10n.kmhUnit,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l10n.autoMotionCurrentSpeed,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: MotionMetric(
                    icon: Icons.straighten,
                    label: l10n.autoMotionDistance,
                    value:
                        '${state.totalKm.toStringAsFixed(2)} ${l10n.kmUnit}',
                  ),
                ),
                Expanded(
                  child: MotionMetric(
                    icon: Icons.speed,
                    label: l10n.autoMotionMaxSpeed,
                    value:
                        '${state.maxSpeedKmh.toStringAsFixed(1)} ${l10n.kmhUnit}',
                  ),
                ),
              ],
            ),
            if (state.unavailable)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () async {
                    await ref
                        .read(locationStatusProvider.notifier)
                        .requestAccessFromUser();
                    if (!context.mounted) return;
                    if (ref.read(autoMotionEnabledProvider)) {
                      await ref
                          .read(autoMotionControllerProvider.notifier)
                          .start();
                    }
                  },
                  icon: const Icon(Icons.location_on_outlined, size: 18),
                  label: Text(l10n.manageLocation),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Active/Paused normally; the specific refusal reason when tracking is down.
  String _statusLabel(AppLocalizations l10n) {
    if (state.unavailable) {
      return trackFailureText(
        l10n,
        state.failure,
        fallback: l10n.autoMotionPermissionHint,
      );
    }
    return state.active ? l10n.autoMotionActive : l10n.autoMotionPaused;
  }
}

/// Today and every previous day recorded by AutoMotion, newest-first.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.history});

  final List<DailyGpsSummary> history;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.history,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(l10n.autoMotionHistory, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            if (history.isEmpty)
              const _EmptyHistory()
            else
              ...history.map(
                (DailyGpsSummary day) => _HistoryTile(day: day),
              ),
          ],
        ),
      ),
    );
  }
}

/// One recorded day: its date, distance and max speed.
class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.day});

  final DailyGpsSummary day;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String locale = Localizations.localeOf(context).toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              formatDate(day.date, locale),
              style: theme.textTheme.bodyLarge,
            ),
          ),
          Text(
            '${day.totalKm.toStringAsFixed(2)} ${l10n.kmUnit}',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${day.maxSpeedKmh.toStringAsFixed(1)} ${l10n.kmhUnit}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown until the first day has been recorded.
class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 4),
        Text(
          l10n.autoMotionHistoryEmpty,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.autoMotionHistoryEmptyHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
