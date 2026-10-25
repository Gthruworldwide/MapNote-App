import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_formats.dart';
import '../../data/models/daily_motion_summary.dart';
import '../../data/models/trip_segment.dart';
import '../../providers/app_providers.dart';
import '../../widgets/motion_metric.dart';
import 'widgets/motion_format.dart';
import 'widgets/motion_presentation.dart';
import 'widgets/motion_timeline_widget.dart';
import 'widgets/route_map_viewer.dart';

/// The Motion history screen: one day of AutoMotion tracking, read as a
/// timeline of drives, stopovers and walks, or as a colour-coded route map.
///
/// Layout, top to bottom:
///
/// ```
/// ┌───────────────────────────────────────────┐
/// │ ‹   Today — 2026-10-23   ›        [calendar]│  date header
/// │ Distance   Drive time   Idle time          │  quick stats
/// │ [ Timeline | Map ]                         │  view toggle
/// ├───────────────────────────────────────────┤
/// │ timeline cards  /  full-height route map    │
/// └───────────────────────────────────────────┘
/// ```
///
/// Everything is derived from the day's stored fixes through
/// [dailyMotionSummaryProvider]; the screen itself owns no state beyond the
/// provider-backed selected date and view mode, so leaving and reopening it can
/// never show stale numbers.
class RouteHistoryScreen extends ConsumerWidget {
  const RouteHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DateTime day = ref.watch(selectedDateProvider);
    final DailyMotionSummary summary = ref.watch(dailyMotionSummaryProvider);
    final MotionHistoryViewMode mode = ref.watch(motionHistoryViewModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.motionHistoryTitle),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.motionHistoryPickDate,
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => _pickDate(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _DateHeader(day: day),
                  const SizedBox(height: 12),
                  _QuickStats(summary: summary),
                  const SizedBox(height: 12),
                  _ViewToggle(mode: mode),
                ],
              ),
            ),
            Expanded(
              child: switch (mode) {
                MotionHistoryViewMode.timeline => ListView(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
                  children: const <Widget>[MotionTimelineWidget()],
                ),
                MotionHistoryViewMode.map => Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const RouteMapViewer(),
                    ),
                  ),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the calendar for a specific day. The picker itself forbids the
  /// future, so `selectedDateProvider` only has to clamp defensively.
  Future<void> _pickDate(BuildContext context, WidgetRef ref) async {
    final DateTime selected = ref.read(selectedDateProvider);
    final DateTime today = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selected,
      firstDate: DateTime(2020),
      lastDate: DateTime(today.year, today.month, today.day),
    );
    if (picked == null) return;
    ref.read(selectedDateProvider.notifier).select(picked);
  }
}

/// The day being shown: its friendly name (Today / Yesterday), its date, and the
/// arrows that step one day at a time.
class _DateHeader extends ConsumerWidget {
  const _DateHeader({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final DateTime today = DateTime.now();
    final DateTime todayDay = DateTime(today.year, today.month, today.day);
    final DateTime yesterdayDay = DateTime(
      today.year,
      today.month,
      today.day - 1,
    );
    final bool isToday = day == todayDay;
    final String label = isToday
        ? l10n.motionHistoryToday
        : day == yesterdayDay
        ? l10n.motionHistoryYesterday
        : formatDate(day, Localizations.localeOf(context).toString());

    return Row(
      children: <Widget>[
        IconButton(
          tooltip: l10n.motionHistoryPreviousDay,
          icon: const Icon(Icons.chevron_left),
          onPressed: () => ref.read(selectedDateProvider.notifier).shiftDays(-1),
        ),
        Expanded(
          child: Column(
            children: <Widget>[
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formatDate(day, Localizations.localeOf(context).toString()),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: l10n.motionHistoryNextDay,
          icon: const Icon(Icons.chevron_right),
          // The future holds no history: the arrow disables on today rather
          // than stepping into an always-empty day.
          onPressed: isToday
              ? null
              : () => ref.read(selectedDateProvider.notifier).shiftDays(1),
        ),
      ],
    );
  }
}

/// Distance / drive time / idle time for the selected day, plus the day's
/// measured modes (vehicle / walk / run) and its step total.
///
/// The counters come straight from [DailyMotionSummary] — which the tracker
/// produces from the same fixes the timeline renders — so the header, the
/// timeline cards, the dashboard breakdown and Smart Insights can never
/// disagree about what the day contained. Only categories that actually
/// recorded something are rendered, so a driving-only day does not grow empty
/// rows of zeros.
class _QuickStats extends StatelessWidget {
  const _QuickStats({required this.summary});

  final DailyMotionSummary summary;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    final List<({IconData icon, String label, String value})> breakdown =
        <({IconData icon, String label, String value})>[
          if (summary.vehicleDistanceKm > 0)
            (
              icon: MotionType.vehicle.icon,
              // The category names are the ones the dashboard and the legend
              // use, so "Walk" means exactly one thing app-wide.
              label: l10n.autoMotionModeVehicle,
              value:
                  '${summary.vehicleDistanceKm.toStringAsFixed(2)} ${l10n.kmUnit}',
            ),
          if (summary.walkingDistanceKm > 0)
            (
              icon: MotionType.walking.icon,
              label: l10n.autoMotionModeWalk,
              value:
                  '${summary.walkingDistanceKm.toStringAsFixed(2)} ${l10n.kmUnit}',
            ),
          if (summary.runningDistanceKm > 0)
            (
              icon: MotionType.running.icon,
              label: l10n.autoMotionModeRun,
              value:
                  '${summary.runningDistanceKm.toStringAsFixed(2)} ${l10n.kmUnit}',
            ),
          if (summary.stepCount > 0)
            (
              icon: Icons.directions_walk_outlined,
              label: l10n.motionHistorySteps,
              value: '${summary.stepCount}',
            ),
        ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: MotionMetric(
                icon: Icons.straighten,
                label: l10n.motionHistoryTotalDistance,
                value:
                    '${summary.totalDistanceKm.toStringAsFixed(2)} ${l10n.kmUnit}',
              ),
            ),
            Expanded(
              child: MotionMetric(
                icon: Icons.directions_car_outlined,
                label: l10n.motionHistoryDriveTime,
                value: formatMotionDuration(summary.vehicleDuration, l10n),
              ),
            ),
            Expanded(
              child: MotionMetric(
                icon: Icons.pause_circle_outline,
                label: l10n.motionHistoryStopoverTime,
                value: formatMotionDuration(summary.stopoverDuration, l10n),
              ),
            ),
          ],
        ),
        if (breakdown.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final ({IconData icon, String label, String value}) entry
                  in breakdown)
                Expanded(
                  child: MotionMetric(
                    icon: entry.icon,
                    label: entry.label,
                    value: entry.value,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.motionHistoryModeBreakdownHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Timeline ⇄ map. Both sides render the same provider, so switching is purely
/// presentational.
class _ViewToggle extends ConsumerWidget {
  const _ViewToggle({required this.mode});

  final MotionHistoryViewMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return SegmentedButton<MotionHistoryViewMode>(
      showSelectedIcon: false,
      segments: <ButtonSegment<MotionHistoryViewMode>>[
        ButtonSegment<MotionHistoryViewMode>(
          value: MotionHistoryViewMode.timeline,
          icon: const Icon(Icons.view_timeline_outlined),
          label: Text(l10n.motionHistoryViewTimeline),
        ),
        ButtonSegment<MotionHistoryViewMode>(
          value: MotionHistoryViewMode.map,
          icon: const Icon(Icons.map_outlined),
          label: Text(l10n.motionHistoryViewMap),
        ),
      ],
      selected: <MotionHistoryViewMode>{mode},
      onSelectionChanged: (Set<MotionHistoryViewMode> selection) => ref
          .read(motionHistoryViewModeProvider.notifier)
          .select(selection.first),
    );
  }
}
