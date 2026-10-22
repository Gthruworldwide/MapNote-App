import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../../services/daily_track_engine.dart';
import '../../services/location_service.dart';
import '../../widgets/track_failure_text.dart';
import 'settings_shared.dart';

/// Location & tracking settings: permission status, the merged AutoMotion +
/// daily GPS tracking card, and the today report.
class LocationSettingsScreen extends ConsumerWidget {
  const LocationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<LocationStatus> location = ref.watch(
      locationStatusProvider,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sectionLocationTracking)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SettingsSection(
            title: l10n.sectionLocationServices,
            child: _buildLocationCard(context, ref, l10n, location),
          ),
          SettingsSection(
            title: l10n.autoMotionSection,
            child: _buildTrackingCard(context, ref, l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    AsyncValue<LocationStatus> location,
  ) {
    final LocationStatus? status = location.value;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (status == null)
            Row(
              children: <Widget>[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(l10n.fetchingLocation),
              ],
            )
          else ...<Widget>[
            StatusRow(
              icon: status.serviceEnabled ? Icons.gps_fixed : Icons.gps_off,
              label: l10n.locationStatusGps,
              value: status.serviceEnabled
                  ? l10n.locationGpsOn
                  : l10n.locationGpsOff,
              ok: status.serviceEnabled,
            ),
            const SizedBox(height: 10),
            StatusRow(
              icon: status.permissionGranted
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              label: l10n.locationStatusPermission,
              value: _permissionLabel(l10n, status.permission),
              ok: status.permissionGranted,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () => ref
                .read(locationStatusProvider.notifier)
                .requestAccessFromUser(),
            icon: const Icon(Icons.tune),
            label: Text(l10n.manageLocation),
          ),
        ],
      ),
    );
  }

  String _permissionLabel(
    AppLocalizations l10n,
    LocationPermission permission,
  ) {
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => l10n.locationPermissionGranted,
      LocationPermission.deniedForever => l10n.locationPermissionDeniedForever,
      LocationPermission.denied => l10n.locationPermissionDenied,
      _ => l10n.locationPermissionUnknown,
    };
  }

  Widget _buildTrackingCard(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final ThemeData theme = Theme.of(context);
    final bool autoMotionEnabled = ref.watch(autoMotionEnabledProvider);
    final bool gpsEnabled = ref.watch(gpsTrackingEnabledProvider);
    final AutoMotionState motion = ref.watch(autoMotionControllerProvider);
    final GpsTrackingState tracking = ref.watch(gpsTrackingControllerProvider);
    final bool anyActive = tracking.active || motion.active;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              Icons.directions_walk,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.smartAutoMotionTitle),
            subtitle: Text(l10n.smartAutoMotionSubtitle),
            value: autoMotionEnabled || gpsEnabled,
            onChanged: (bool value) async {
              await ref.read(autoMotionEnabledProvider.notifier).setEnabled(value);
              await ref.read(gpsTrackingEnabledProvider.notifier).setEnabled(value);
            },
          ),
          if (autoMotionEnabled || gpsEnabled) ...<Widget>[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            if (autoMotionEnabled)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.battery_saver),
                title: Text(l10n.smartBatterySaver),
                subtitle: Text(l10n.smartBatterySaverDesc),
                value: ref.watch(settingsRepositoryProvider).isSmartBatterySaverEnabled,
                onChanged: (bool value) => ref
                    .read(settingsRepositoryProvider)
                    .setSmartBatterySaverEnabled(value),
              ),
            TrackingSummaryTile(
              totalKm: (tracking.totalKm > motion.totalKm
                  ? tracking.totalKm
                  : motion.totalKm),
              maxSpeedKmh: (tracking.maxSpeedKmh > motion.maxSpeedKmh
                  ? tracking.maxSpeedKmh
                  : motion.maxSpeedKmh),
              active: anyActive,
              unavailable:
                  !anyActive && (tracking.unavailable || motion.unavailable),
              failure: tracking.failure != TrackStartFailure.none
                  ? tracking.failure
                  : motion.failure,
              onManageLocation: () => _manageTrackingLocation(context, ref),
              l10n: l10n,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _manageTrackingLocation(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await ref.read(locationStatusProvider.notifier).requestAccessFromUser();
    if (!context.mounted) return;
    if (ref.read(gpsTrackingEnabledProvider)) {
      await ref.read(gpsTrackingControllerProvider.notifier).start();
    }
    if (ref.read(autoMotionEnabledProvider)) {
      await ref.read(autoMotionControllerProvider.notifier).start();
    }
  }
}

/// Today's distance / max-speed report.
class TrackingSummaryTile extends StatelessWidget {
  const TrackingSummaryTile({
    required this.totalKm,
    required this.maxSpeedKmh,
    required this.active,
    required this.unavailable,
    required this.failure,
    required this.onManageLocation,
    required this.l10n,
    super.key,
  });

  final double totalKm;
  final double maxSpeedKmh;
  final bool active;
  final bool unavailable;
  final TrackStartFailure failure;
  final VoidCallback onManageLocation;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (unavailable)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.gps_off,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        trackFailureText(
                          l10n,
                          failure,
                          fallback: l10n.dailyGpsUnavailable,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: onManageLocation,
                    icon: const Icon(Icons.location_on_outlined, size: 18),
                    label: Text(l10n.manageLocation),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: <Widget>[
            Expanded(
              child: _DailyGpsMetric(
                icon: Icons.straighten,
                label: l10n.dailyDistance,
                value: '${totalKm.toStringAsFixed(2)} ${l10n.kmUnit}',
              ),
            ),
            Expanded(
              child: _DailyGpsMetric(
                icon: Icons.speed,
                label: l10n.dailyMaxSpeed,
                value: '${maxSpeedKmh.toStringAsFixed(1)} ${l10n.kmhUnit}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Icon(
              active ? Icons.gps_fixed : Icons.pause_circle_outline,
              size: 16,
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              active ? l10n.dailyTrackingActive : l10n.dailyTrackingPaused,
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

class _DailyGpsMetric extends StatelessWidget {
  const _DailyGpsMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
