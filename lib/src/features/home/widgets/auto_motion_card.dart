import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_providers.dart';

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
                _StatusBadge(state: state, l10n: l10n),
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
          ],
        ),
      ),
    );
  }
}

/// Small "Active / Paused / GPS unavailable" indicator for the card header.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state, required this.l10n});

  final AutoMotionState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (IconData icon, Color color, String label, String tooltip) =
        state.unavailable
            ? (
                Icons.gps_off,
                theme.colorScheme.error,
                l10n.dailyGpsUnavailable,
                l10n.dailyGpsUnavailable,
              )
            : state.active
            ? (
                Icons.gps_fixed,
                theme.colorScheme.primary,
                l10n.autoMotionActive,
                l10n.autoMotionActive,
              )
            : (
                Icons.pause_circle_outline,
                theme.colorScheme.onSurfaceVariant,
                l10n.autoMotionPaused,
                l10n.autoMotionPaused,
              );

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ),
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