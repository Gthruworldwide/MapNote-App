import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../data/models/trip_segment.dart';
import 'motion_format.dart';
import 'motion_segment_card.dart';

/// One drive in the day's timeline: how far, how long and how fast.
///
/// The map action is optional — the timeline passes it so a drive can be
/// inspected on the day's map, and a card used without it stays inert.
class DriveSegmentCard extends StatelessWidget {
  const DriveSegmentCard({super.key, required this.segment, this.onShowOnMap});

  /// The classified drive.
  final TripSegment segment;

  /// Switches the screen to the map view (null hides the action).
  final VoidCallback? onShowOnMap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String distance = segment.distanceKm.toStringAsFixed(1);
    final String duration = formatMotionDuration(segment.duration, l10n);

    return MotionSegmentCard(
      type: segment.type,
      title: l10n.motionTypeDrive,
      timeRange: formatSegmentTimeRange(
        context,
        start: segment.startTime,
        end: segment.endTime,
      ),
      subtitle: l10n.motionHistoryDriveStats(distance, duration),
      detail: l10n.motionHistoryAverageSpeed(
        segment.averageSpeedKmH.toStringAsFixed(0),
      ),
      onTap: onShowOnMap,
      trailing: onShowOnMap == null
          ? null
          : IconButton(
              tooltip: l10n.motionHistoryShowOnMap,
              icon: const Icon(Icons.map_outlined),
              onPressed: onShowOnMap,
            ),
    );
  }
}
