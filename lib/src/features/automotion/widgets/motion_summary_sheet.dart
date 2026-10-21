import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_providers.dart';
import '../../../services/motion_profiler.dart';
import '../../../services/motion_score.dart';
import 'driving_event_presentation.dart';

/// A collapsible summary of the current trip's driving quality: the score, its
/// band, and a per-kind tally of every maneuver recorded.
///
/// Everything shown is derived from the location-free maneuver log and the
/// trip's distance — no coordinates, no identity (AGENT_SKILLS.md §5). The
/// sheet starts expanded, collapses to its header on tap, and empties
/// automatically when a new trip begins (the source list is cleared by
/// `AutoMotionController`).
class MotionSummarySheet extends ConsumerStatefulWidget {
  const MotionSummarySheet({super.key});

  @override
  ConsumerState<MotionSummarySheet> createState() => _MotionSummarySheetState();
}

class _MotionSummarySheetState extends ConsumerState<MotionSummarySheet> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final MotionScore score = ref.watch(motionScoreProvider);
    final Color bandColor = _bandColor(scheme, score.band);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The header is the collapse control and stays legible when closed,
          // so the score is always on screen.
          Semantics(
            button: true,
            label: _expanded ? l10n.motionSummaryCollapse : l10n.motionSummaryExpand,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.insights, size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.motionSummaryTitle,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    Text(
                      l10n.motionSummaryScore(score.score),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: bandColor,
                      ),
                    ),
                    // The chevron is directional, so it mirrors under RTL.
                    const SizedBox(width: 4),
                    Icon(
                      _expanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      _BandChip(label: _bandLabel(l10n, score.band), color: bandColor),
                      const SizedBox(width: 8),
                      if (!score.isClean)
                        Text(
                          l10n.motionSummaryEvents(score.total),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (score.isClean)
                    Text(
                      l10n.motionSummaryClean,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else
                    for (final DrivingEventType type
                        in DrivingEventType.values)
                      _TallyRow(
                        type: type,
                        count: score.tallies[type] ?? 0,
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _bandLabel(AppLocalizations l10n, MotionScoreBand band) =>
      switch (band) {
        MotionScoreBand.excellent => l10n.scoreExcellent,
        MotionScoreBand.good => l10n.scoreGood,
        MotionScoreBand.fair => l10n.scoreFair,
        MotionScoreBand.poor => l10n.scorePoor,
      };

  /// Bands ride the theme: good trips read as the positive accent, poor ones as
  /// the error colour, whatever the brightness.
  static Color _bandColor(ColorScheme scheme, MotionScoreBand band) =>
      switch (band) {
        MotionScoreBand.excellent || MotionScoreBand.good => scheme.primary,
        MotionScoreBand.fair => scheme.tertiary,
        MotionScoreBand.poor => scheme.error,
      };
}

/// The band name as a filled chip.
class _BandChip extends StatelessWidget {
  const _BandChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One maneuver kind's count. A zero count is dimmed rather than hidden, so the
/// tally reads as a complete checklist instead of a shifting list.
class _TallyRow extends StatelessWidget {
  const _TallyRow({required this.type, required this.count});

  final DrivingEventType type;
  final int count;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool present = count > 0;
    final Color color = present
        ? type.color(scheme)
        : scheme.onSurfaceVariant.withValues(alpha: 0.55);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Icon(type.icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              type.label(l10n),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: present ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            '$count',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
