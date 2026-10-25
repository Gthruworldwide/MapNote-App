import 'package:flutter/material.dart';

import '../../../data/models/trip_segment.dart';
import 'motion_presentation.dart';

/// The shared shell of the Motion history cards: a coloured rail on the leading
/// edge, the kind's icon, a title, an optional time range and up to two lines of
/// detail.
///
/// The three cards ([DriveSegmentCard], [WalkSegmentCard], [StopoverCard]) own
/// their own wording and numbers; this shell owns the layout so the timeline
/// stays visually consistent and the rail always matches the map's polyline
/// colour (both read [MotionTypePresentation]).
class MotionSegmentCard extends StatelessWidget {
  const MotionSegmentCard({
    super.key,
    required this.type,
    required this.title,
    required this.subtitle,
    this.detail,
    this.timeRange,
    this.trailing,
    this.onTap,
  });

  /// Which motion this card describes — drives the rail, the icon and the tint.
  final MotionType type;

  /// The card's headline (the kind's name, or a stopover's resolved place).
  final String title;

  /// The primary number line (distance/duration, or a stop's length).
  final String subtitle;

  /// An optional secondary line (average speed, estimated steps…).
  final String? detail;

  /// The segment's wall-clock span, shown at the trailing end of the title row.
  final String? timeRange;

  /// An optional action rendered after the text column (e.g. "show on map").
  final Widget? trailing;

  /// Tapping the card body.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsetsDirectional.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // The colour rail: leading edge, so it mirrors with the locale.
              Container(width: 4, color: type.color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 12, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: type.color.withValues(alpha: 0.14),
                        ),
                        alignment: Alignment.center,
                        child: Icon(type.icon, size: 20, color: type.color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    title,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (timeRange != null) ...<Widget>[
                                  const SizedBox(width: 8),
                                  Text(
                                    timeRange!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(subtitle, style: theme.textTheme.bodyMedium),
                            if (detail != null) ...<Widget>[
                              const SizedBox(height: 2),
                              Text(
                                detail!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (trailing != null) ...<Widget>[
                        const SizedBox(width: 4),
                        trailing!,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
