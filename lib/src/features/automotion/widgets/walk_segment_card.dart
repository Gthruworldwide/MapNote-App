import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../data/models/trip_segment.dart';
import 'motion_format.dart';
import 'motion_segment_card.dart';

/// One walk in the day's timeline: distance, steps and duration.
///
/// Everything shown here is a **measurement**: the hardware step counter counted
/// the steps and a walking stride of [TripSegment.walkingStrideMeters] turns
/// that count into the distance. A fix with no step count is never labelled a
/// walk (see `MotionClassifierService`), so this card has no estimate to
/// present and never needs a "≈".
class WalkSegmentCard extends StatelessWidget {
  const WalkSegmentCard({super.key, required this.segment});

  /// The classified walk.
  final TripSegment segment;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String metres = segment.distanceInMeters.toStringAsFixed(0);

    return MotionSegmentCard(
      type: segment.type,
      title: l10n.motionTypeWalk,
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
