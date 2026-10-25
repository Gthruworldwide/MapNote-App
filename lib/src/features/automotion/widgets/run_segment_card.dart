import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../data/models/trip_segment.dart';
import 'motion_format.dart';
import 'motion_segment_card.dart';

/// One run in the day's timeline: how far, how many steps and how long.
///
/// A run is the same physical measurement as a walk — the hardware step counter
/// — with two differences: the stride is longer ([TripSegment.runningStrideMeters])
/// and the cadence crosses `MotionClassifierService.runCadencePerMinute`. The
/// card therefore reuses the walking wording and only swaps the title, icon and
/// accent (all derived from [TripSegment.type]).
class RunSegmentCard extends StatelessWidget {
  const RunSegmentCard({super.key, required this.segment});

  /// The classified run.
  final TripSegment segment;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String metres = segment.distanceInMeters.toStringAsFixed(0);

    return MotionSegmentCard(
      type: segment.type,
      title: l10n.motionTypeRun,
      timeRange: formatSegmentTimeRange(
        context,
        start: segment.startTime,
        end: segment.endTime,
      ),
      subtitle: l10n.motionHistoryStepStats(metres, segment.steps ?? 0),
      detail: formatMotionDuration(segment.duration, l10n),
    );
  }
}
