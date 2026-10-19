import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection; // `intl` ships its own `TextDirection` — the widget needs `dart:ui`'s.

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/utils/date_formats.dart';
import '../../../providers/app_providers.dart';
import '../../../services/route_milestones.dart';

/// The milestone timeline rendered under the route map: every significant
/// stop of the day with its exact time, date and — when reverse geocoding
/// resolved one — its place name.
///
/// Pure derived state: rows come from [routeMilestoneNamesProvider], which
/// itself derives from the day's smoothed path, so the timeline adds no
/// storage and works fully offline (names then fall back to the milestone's
/// kind label — "Trip start", "Stop", "Trip end" — and upgrade in place if a
/// name is later resolved within the session).
class RouteTimeline extends ConsumerWidget {
  const RouteTimeline({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<RouteMilestone> milestones = ref.watch(
      routeMilestonesProvider,
    );
    final Map<String, String?> names = ref.watch(routeMilestoneNamesProvider);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    if (milestones.isEmpty) {
      // The route exists but carries no timestamps (a record from an older
      // build, for example): without times there is no timeline to draw.
      return Text(
        l10n.routeMilestonesEmpty,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    final bool ltr = Directionality.of(context) == TextDirection.ltr;
    final String locale = l10n.localeName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.timeline, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Text(l10n.routeMilestonesTitle, style: theme.textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 10),
        for (int i = 0; i < milestones.length; i++)
          _MilestoneRow(
            milestone: milestones[i],
            name: names[milestones[i].coordinateKey],
            kindLabel: _kindLabel(l10n, milestones[i].kind),
            locale: locale,
            isLast: i == milestones.length - 1,
            timeAlignedToOuterEdge: ltr,
            theme: theme,
          ),
      ],
    );
  }

  String _kindLabel(AppLocalizations l10n, RouteMilestoneKind kind) =>
      switch (kind) {
        RouteMilestoneKind.tripStart => l10n.milestoneTripStart,
        RouteMilestoneKind.stop => l10n.milestoneStop,
        RouteMilestoneKind.tripEnd => l10n.milestoneTripEnd,
      };
}

/// One timeline entry: rail dot and connector on the left, place name and
/// kind in the middle, exact time and date on the outer edge.
class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({
    required this.milestone,
    required this.name,
    required this.kindLabel,
    required this.locale,
    required this.isLast,
    required this.timeAlignedToOuterEdge,
    required this.theme,
  });

  final RouteMilestone milestone;
  final String? name;
  final String kindLabel;
  final String locale;
  final bool isLast;

  /// Times should hug the row's outer edge, which flips under RTL.
  final bool timeAlignedToOuterEdge;

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = theme.colorScheme;
    final Color railColor = switch (milestone.kind) {
      RouteMilestoneKind.tripEnd => scheme.error,
      _ => scheme.primary,
    };
    final bool filled = milestone.kind != RouteMilestoneKind.stop;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Rail: this entry's dot, and a connector down to the next one.
        Column(
          children: <Widget>[
            Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? railColor : scheme.surface,
                border: Border.all(
                  color: filled ? scheme.surface : railColor,
                  width: 3,
                ),
              ),
            ),
            if (!isLast) ...<Widget>[
              const SizedBox(height: 4),
              Container(
                width: 2,
                height: 24,
                color: scheme.outlineVariant,
              ),
            ],
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsetsDirectional.only(bottom: isLast ? 0 : 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        name ?? kindLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (name != null)
                        Text(
                          kindLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: timeAlignedToOuterEdge
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      DateFormat.jm(locale).format(milestone.at.toLocal()),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                    Text(
                      formatDate(milestone.at, locale),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
