import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_providers.dart';
import '../../../services/motion_profiler.dart';

/// The current trip's harsh maneuvers — hard braking and harsh acceleration
/// — as detected by the motion behavior analyzer (GPS speed timeline
/// confirmed by accelerometer vibration, gated to vehicle trips).
///
/// Events are captured by [drivingEventsProvider] even while this card is
/// off-screen, and a new trip starts with a clean slate. Nothing here leaves
/// the device.
class DrivingEventsCard extends ConsumerWidget {
  const DrivingEventsCard({super.key});

  /// Most events shown inline; a busy trip overflows into a count line.
  static const int _visibleLimit = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final List<DrivingEvent> events = ref.watch(drivingEventsProvider);
    final List<DrivingEvent> newestFirst = events.reversed.toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.warning_amber_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.autoMotionEvents,
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (events.isEmpty)
              Text(
                l10n.autoMotionEventsEmpty,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...<Widget>[
              for (final DrivingEvent event
                  in newestFirst.take(_visibleLimit))
                _DrivingEventTile(event: event),
              if (newestFirst.length > _visibleLimit)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.autoMotionEventsMore(
                      newestFirst.length - _visibleLimit,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One maneuver: its kind, peak magnitude and the time it happened.
class _DrivingEventTile extends StatelessWidget {
  const _DrivingEventTile({required this.event});

  final DrivingEvent event;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final bool braking = event.type == DrivingEventType.harshBraking;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Icon(
            braking ? Icons.trending_down : Icons.trending_up,
            size: 20,
            color: braking
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              braking ? l10n.harshBraking : l10n.harshAcceleration,
              style: theme.textTheme.bodyLarge,
            ),
          ),
          Text(
            '${event.peakMps2.abs().toStringAsFixed(1)} ${l10n.mps2Unit}',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            MaterialLocalizations.of(
              context,
            ).formatTimeOfDay(TimeOfDay.fromDateTime(event.startedAt)),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
