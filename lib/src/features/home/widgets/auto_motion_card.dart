import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/track_failure_text.dart';
import 'auto_motion_badge.dart';

/// The AutoMotion dashboard card for the Home screen.
///
/// Surfaces today's recorded distance, today's max speed and whether tracking
/// is live. Home keeps it visible while AutoMotion is enabled, or while today
/// already has recorded motion — in that case the badge reads "Paused" so the
/// user can still see their day's totals.
class AutoMotionCard extends ConsumerWidget {
  const AutoMotionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final AutoMotionState state = ref.watch(autoMotionControllerProvider);

    return Card(
      margin: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 8),
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
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: _AutoMotionMetric(
                    icon: Icons.straighten,
                    label: l10n.autoMotionDistance,
                    value:
                        '${state.totalKm.toStringAsFixed(2)} ${l10n.kmUnit}',
                  ),
                ),
                Expanded(
                  child: _AutoMotionMetric(
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
    );
  }
}

/// A single labelled number in the AutoMotion card (distance / max speed).
class _AutoMotionMetric extends StatelessWidget {
  const _AutoMotionMetric({
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
