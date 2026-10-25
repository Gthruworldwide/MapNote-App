import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../data/models/trip_segment.dart';
import '../../../providers/app_providers.dart';
import 'drive_segment_card.dart';
import 'run_segment_card.dart';
import 'stopover_card.dart';
import 'walk_segment_card.dart';

/// The selected day as a chronological list of drive / stopover / walk / run
/// cards.
///
/// Reads [motionHistoryProvider] — the same classified segments the map draws —
/// so the two views can never disagree. Nothing is loaded here: the provider
/// chain already handled storage and classification, and an empty day renders
/// the shared empty state instead of an empty list.
class MotionTimelineWidget extends ConsumerWidget {
  const MotionTimelineWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<TripSegment> segments = ref.watch(motionHistoryProvider);
    if (segments.isEmpty) return const MotionTimelineEmptyState();

    // Stopover names are resolved lazily and may arrive after the first frame;
    // watching the map upgrades the card in place, and a miss just keeps the
    // localized label.
    final Map<DateTime, String?> stopoverNames = ref.watch(
      stopoverNamesProvider,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final TripSegment segment in segments)
          switch (segment.type) {
            MotionType.vehicle => DriveSegmentCard(
              segment: segment,
              onShowOnMap: () => ref
                  .read(motionHistoryViewModeProvider.notifier)
                  .select(MotionHistoryViewMode.map),
            ),
            MotionType.walking => WalkSegmentCard(segment: segment),
            MotionType.running => RunSegmentCard(segment: segment),
            MotionType.stationary => StopoverCard(
              segment: segment,
              name: stopoverNames[segment.startTime],
            ),
          },
      ],
    );
  }
}

/// Shown when the selected day has no classified motion at all.
///
/// Deliberately explains *why* it can be empty (tracking off, or a day before
/// any fixes were recorded) instead of leaving a blank pane.
class MotionTimelineEmptyState extends StatelessWidget {
  const MotionTimelineEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.route_outlined, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            l10n.motionHistoryEmptyTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.motionHistoryEmptyBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
