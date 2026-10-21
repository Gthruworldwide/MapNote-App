import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../core/utils/date_formats.dart';
import '../../data/local/auto_motion_data_source.dart';
import '../../data/models/daily_gps_summary.dart';
import '../../providers/app_providers.dart';
import '../../widgets/motion_metric.dart';
import '../../widgets/track_failure_text.dart';
import '../home/widgets/auto_motion_badge.dart';
import '../saved_places/presentation/widgets/place_link_suggestions_card.dart';
import 'widgets/auto_motion_export_sheet.dart';
import 'widgets/driving_events_card.dart';
import 'widgets/motion_summary_sheet.dart';
import 'widgets/trip_route_card.dart';

/// The full AutoMotion dashboard, opened by tapping the Home status card.
///
/// Shows a live **driver mode** header (current speed, active/paused status and
/// today's distance & max speed), today's **recorded route** as an offline
/// mini-map, the trip's **driving events** (hard braking / harsh acceleration)
/// and the **trip history** of every recorded day, newest-first. Everything is
/// read from the same offline Hive data the Home card uses — no network calls,
/// and the two daily trackers stay independent.
class AutoMotionScreen extends ConsumerWidget {
  const AutoMotionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AutoMotionState state = ref.watch(autoMotionControllerProvider);
    final List<DailyGpsSummary> history = ref.watch(autoMotionHistoryProvider);
    final AutoMotionAggregates agg7 = ref.watch(autoMotionAggregates7dProvider);
    final AutoMotionAggregates agg30 = ref.watch(autoMotionAggregates30dProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.autoMotionDashboardTitle),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.autoMotionExport,
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const AutoMotionExportBottomSheet(),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _DriverModeCard(state: state),
          const SizedBox(height: 16),
          const MotionSummarySheet(),
          const SizedBox(height: 16),
          const TripRouteCard(),
          const SizedBox(height: 16),
          const PlaceLinkSuggestionsCard(),
          const DrivingEventsCard(),
          const SizedBox(height: 16),
          _ActivityBreakdownCard(state: state),
          const SizedBox(height: 16),
          _AggregatesCard(aggregates7: agg7, aggregates30: agg30),
          const SizedBox(height: 16),
          _HistoryCard(history: history),
        ],
      ),
    );
  }
}

/// Live driver-mode header: status badge, current speed and today's totals,
/// with the shared one-tap location recovery when tracking is unavailable.
class _DriverModeCard extends ConsumerWidget {
  const _DriverModeCard({required this.state});

  final AutoMotionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                AutoMotionBadge(
                  isActive: state.active,
                  isUnavailable: state.unavailable,
                  size: 48,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.autoMotionDriverMode,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _statusLabel(l10n),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: state.unavailable
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // The headline of driver mode: the speed of the latest fix.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  state.currentSpeedKmh.toStringAsFixed(1),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    l10n.kmhUnit,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l10n.autoMotionCurrentSpeed,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: MotionMetric(
                    icon: Icons.straighten,
                    label: l10n.autoMotionDistance,
                    value:
                        '${state.totalKm.toStringAsFixed(2)} ${l10n.kmUnit}',
                  ),
                ),
                Expanded(
                  child: MotionMetric(
                    icon: Icons.speed,
                    label: l10n.autoMotionMaxSpeed,
                    value:
                        '${state.maxSpeedKmh.toStringAsFixed(1)} ${l10n.kmhUnit}',
                  ),
                ),
              ],
            ),
            if (state.unavailable)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () async {
                    await ref
                        .read(locationStatusProvider.notifier)
                        .requestAccessFromUser();
                    if (!context.mounted) return;
                    if (ref.read(autoMotionEnabledProvider)) {
                      await ref
                          .read(autoMotionControllerProvider.notifier)
                          .start();
                    }
                  },
                  icon: const Icon(Icons.location_on_outlined, size: 18),
                  label: Text(l10n.manageLocation),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Active/Paused normally; the specific refusal reason when tracking is down.
  String _statusLabel(AppLocalizations l10n) {
    if (state.unavailable) {
      return trackFailureText(
        l10n,
        state.failure,
        fallback: l10n.autoMotionPermissionHint,
      );
    }
    return state.active ? l10n.autoMotionActive : l10n.autoMotionPaused;
  }
}

class _ActivityBreakdownCard extends StatelessWidget {
  const _ActivityBreakdownCard({required this.state});

  final AutoMotionState state;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final double walkKm = state.walkKm;
    final double runKm = state.runKm;
    final double vehicleKm = state.vehicleKm;
    final double total = walkKm + runKm + vehicleKm;
    final bool hasData = total > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.pie_chart_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.autoMotionActivityBreakdownToday,
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!hasData)
              Text(
                l10n.autoMotionActivityBreakdownEmpty,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              Column(
                children: <Widget>[
                  _ModeRow(
                    label: l10n.autoMotionModeWalk,
                    km: walkKm,
                    seconds: state.walkDurationSeconds,
                    totalKm: total,
                    color: theme.colorScheme.tertiary,
                  ),
                  _ModeRow(
                    label: l10n.autoMotionModeRun,
                    km: runKm,
                    seconds: state.runDurationSeconds,
                    totalKm: total,
                    color: theme.colorScheme.secondary,
                  ),
                  _ModeRow(
                    label: l10n.autoMotionModeVehicle,
                    km: vehicleKm,
                    seconds: state.vehicleDurationSeconds,
                    totalKm: total,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.label,
    required this.km,
    required this.seconds,
    required this.totalKm,
    required this.color,
  });

  final String label;
  final double km;
  final int seconds;
  final double totalKm;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final double pct = totalKm <= 0 ? 0 : (km / totalKm * 100);
    final int minutes = seconds ~/ 60;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text(
                '${km.toStringAsFixed(2)} ${l10n.kmUnit}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text(
                '$minutes min',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${pct.toStringAsFixed(0)}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AggregatesCard extends ConsumerStatefulWidget {
  const _AggregatesCard({
    required this.aggregates7,
    required this.aggregates30,
  });

  final AutoMotionAggregates aggregates7;
  final AutoMotionAggregates aggregates30;

  @override
  ConsumerState<_AggregatesCard> createState() => _AggregatesCardState();
}

class _AggregatesCardState extends ConsumerState<_AggregatesCard> {
  DateTimeRange? _customRange;
  AutoMotionAggregates? _customAgg;

  Future<void> _pickRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customRange,
    );
    if (picked == null) return;
    final AutoMotionDataSource store = ref.read(autoMotionDataSourceProvider);
    setState(() {
      _customRange = picked;
      _customAgg = store.aggregates(
        days: picked.end.difference(picked.start).inDays + 1,
        endDate: picked.end,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.calendar_view_week,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.autoMotionAggregates,
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _AggregateRow(
              title: l10n.autoMotionLast7Days,
              aggregates: widget.aggregates7,
            ),
            const Divider(height: 16),
            _AggregateRow(
              title: l10n.autoMotionLast30Days,
              aggregates: widget.aggregates30,
            ),
            const Divider(height: 16),
            OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range),
              label: Text(
                _customRange == null
                    ? l10n.autoMotionCustomRange
                    : l10n.autoMotionRangeLabel(
                        _fmt(_customRange!.start),
                        _fmt(_customRange!.end),
                      ),
              ),
            ),
            if (_customAgg != null) ...<Widget>[
              const SizedBox(height: 8),
              _AggregateRow(
                title: l10n.autoMotionCustomRange,
                aggregates: _customAgg!,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _AggregateRow extends StatelessWidget {
  const _AggregateRow({required this.title, required this.aggregates});

  final String title;
  final AutoMotionAggregates aggregates;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(title, style: theme.textTheme.bodyLarge),
            ),
            Text(
              l10n.autoMotionDaysRecorded(aggregates.days),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '${aggregates.totalKm.toStringAsFixed(2)} ${l10n.kmUnit}',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${aggregates.walkKm.toStringAsFixed(2)} ${l10n.kmUnit} ${l10n.autoMotionModeWalk.toLowerCase()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${aggregates.runKm.toStringAsFixed(2)} ${l10n.kmUnit} ${l10n.autoMotionModeRun.toLowerCase()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${aggregates.vehicleKm.toStringAsFixed(2)} ${l10n.kmUnit} ${l10n.autoMotionModeVehicle.toLowerCase()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Today and every previous day recorded by AutoMotion, newest-first.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.history});

  final List<DailyGpsSummary> history;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.history,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(l10n.autoMotionHistory, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            if (history.isEmpty)
              const _EmptyHistory()
            else
              ...history.map(
                (DailyGpsSummary day) => _HistoryTile(day: day),
              ),
          ],
        ),
      ),
    );
  }
}

/// One recorded day: its date, distance and max speed.
class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.day});

  final DailyGpsSummary day;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String locale = Localizations.localeOf(context).toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              formatDate(day.date, locale),
              style: theme.textTheme.bodyLarge,
            ),
          ),
          Text(
            '${day.totalKm.toStringAsFixed(2)} ${l10n.kmUnit}',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${day.maxSpeedKmh.toStringAsFixed(1)} ${l10n.kmhUnit}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown until the first day has been recorded.
class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 4),
        Text(
          l10n.autoMotionHistoryEmpty,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.autoMotionHistoryEmptyHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
