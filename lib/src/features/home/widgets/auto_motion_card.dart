import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/motion_metric.dart';
import '../../../widgets/track_failure_text.dart';
import '../../automotion/automotion_screen.dart';
import 'auto_motion_badge.dart';

/// The AutoMotion dashboard card for the Home screen.
///
/// Surfaces today's recorded distance, today's max speed and whether tracking
/// is live. Home keeps it visible while AutoMotion is enabled, or while today
/// already has recorded motion — in that case the badge reads "Paused" so the
/// user can still see their day's totals.
///
/// Tapping the card opens the full [AutoMotionScreen] (driver mode + history).
class AutoMotionCard extends ConsumerWidget {
  const AutoMotionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final AutoMotionState state = ref.watch(autoMotionControllerProvider);

    return Card(
      margin: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const AutoMotionScreen(),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.directions_walk,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.autoMotionSection,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  AutoMotionBadge(
                    isActive: state.active,
                    isUnavailable: state.unavailable,
                    size: 28,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                    semanticLabel: l10n.autoMotionViewDetails,
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
              // A refused start is never silent: explain why tracking is down and
              // offer a one-tap fix that re-reads status and restarts the tracker.
              if (state.unavailable) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  trackFailureText(
                    l10n,
                    state.failure,
                    fallback: l10n.autoMotionPermissionHint,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
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
            ],
          ),
        ),
      ),
    );
  }
}
