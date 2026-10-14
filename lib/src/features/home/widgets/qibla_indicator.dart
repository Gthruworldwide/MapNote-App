import 'package:flutter/material.dart';

import 'package:geolocator/geolocator.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/utils/qibla_calculator.dart';

/// Stateful widget that displays the Qibla direction (bearing to Ka'bah).
///
/// Shows the bearing as "X° DDD" (e.g., "136° SE").
/// - Fetches current GPS location and calculates Qibla bearing.
/// - Falls back gracefully if location is disabled/denied.
/// - Displays the 16-point compass direction abbreviation.
class QiblaIndicator extends StatefulWidget {
  const QiblaIndicator({super.key});

  @override
  State<QiblaIndicator> createState() => _QiblaIndicatorState();
}

/// Internal state for QiblaIndicator.
class _QiblaIndicatorState extends State<QiblaIndicator> {
  /// Calculated Qibla bearing to Mecca (0° to 360°), null if no GPS fix.
  double? _qiblaBearing;

  /// GPS position status string.
  String _positionStatus = '---';

  /// Qibla direction abbreviation (e.g., 'SE', 'NE').
  String _directionAbbrev = '';

  /// Whether we have a valid position and bearing.
  bool _hasValidFix = false;

  @override
  void initState() {
    super.initState();
    _fetchInitial();
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// --- Initial fetch ---

  Future<void> _fetchInitial() {
    return Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high, distanceFilter: 10))
        .then((Position position) => _updateQiblaFromPosition(position))
        .onError((Object error, StackTrace stackTrace) {
      setState(() {
        _positionStatus = 'Could not get location';
      });
    });
  }

  /// --- Qibla Calculation from GPS Position ---

  void _updateQiblaFromPosition(Position position) {
    // Calculate Qibla bearing from current GPS position to Mecca.
    final bearing = QiblaCalculator.bearingFrom(position.latitude, position.longitude);
    setState(() {
      _qiblaBearing = bearing;
      _positionStatus =
          'GPS fix: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
      // Derive 16-point compass direction abbreviation.
      if (bearing != null) {
        _directionAbbrev = _formatDirection(bearing);
        _hasValidFix = true;
      } else {
        _directionAbbrev = '---';
        _hasValidFix = false;
      }
    });
  }

  /// Formats a bearing into a 16‑point compass abbreviation.
  static String _formatDirection(double bearing) {
    final labels = [
      'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
    ];
    final index = ((bearing + 11.25) / 22.5).round() % 16;
    return labels[index];
  }

  // -------------------------------------------------------------------------
  // Widget build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    // --- Determine displayed bearing ---
    final hasValidFix = _hasValidFix && _qiblaBearing != null;
    final safeBearing = _qiblaBearing!;

    // --- Qibla badge ---
    final qiblaBadge = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: hasValidFix
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.surface,
        border: Border.all(
          color: hasValidFix
              ? theme.colorScheme.secondary
              : theme.colorScheme.outline,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        hasValidFix ? '${safeBearing.toInt()}° $_directionAbbrev' : l10n.qiblaUnavailable,
        style: theme.textTheme.bodySmall?.copyWith(
          color: hasValidFix
              ? theme.colorScheme.onSecondaryContainer
              : theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    // --- Direction abbreviation label ---
    final dirLabel = Text(
      hasValidFix ? l10n.qiblaDirectionAbbrev : l10n.qiblaUnavailable,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    // --- Position status ---
    final positionChip = Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _positionStatus,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // --- Qibla Status Badge ---
        qiblaBadge,

        const SizedBox(height: 4),

        // --- Direction Abbebrivation Label ---
        dirLabel,

        // --- Position Status ---
        const SizedBox(height: 8),
        positionChip,
      ],
    );
  }
}