import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../data/models/trip_segment.dart';
import 'motion_format.dart';
import 'motion_segment_card.dart';

/// One stopover in the day's timeline: where and for how long.
///
/// Stopovers exist only when the classifier saw the device stay in one place
/// for at least three minutes (`MotionClassifierService.stopoverThreshold`), so
/// this card never appears for a red light. The place name is used when one has
/// been resolved and the generic kind label otherwise — the card never invents a
/// location.
class StopoverCard extends StatelessWidget {
  const StopoverCard({super.key, required this.segment, this.name});

  /// The classified stopover.
  final TripSegment segment;

  /// A reverse-geocoded place name for this stop, when one is known
  /// (`stopoverNamesProvider`). Best-effort by design: offline, no geocoder or
  /// not answered yet all mean `null`, and the card falls back to the generic
  /// label rather than inventing a location.
  final String? name;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return MotionSegmentCard(
      type: segment.type,
      title: name ?? segment.stopoverName ?? l10n.motionTypeStopover,
      timeRange: formatSegmentTimeRange(
        context,
        start: segment.startTime,
        end: segment.endTime,
      ),
      subtitle: l10n.motionHistoryStopoverStats(
        formatMotionDuration(segment.duration, l10n),
      ),
    );
  }
}
