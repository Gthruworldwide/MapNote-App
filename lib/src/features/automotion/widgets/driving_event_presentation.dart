import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../services/motion_profiler.dart';

/// The single source of truth for how a [DrivingEventType] is presented:
/// its icon, whether it reads as a warning, and its localized label.
///
/// Every place that shows a maneuver — the events card, the map markers and the
/// motion summary sheet — reads from here, so a new [DrivingEventType] cannot
/// fall through to another kind's icon or label in one surface while being
/// correct in another (AGENT_SKILLS.md §5).
extension DrivingEventPresentation on DrivingEventType {
  /// Whether this maneuver means something went wrong. Braking and potholes
  /// take the error colour; a turn is a fact of driving, so it stays in the
  /// accent colour alongside acceleration and bumps.
  bool get isWarning => switch (this) {
    DrivingEventType.harshBraking || DrivingEventType.pothole => true,
    DrivingEventType.harshAcceleration ||
    DrivingEventType.sharpTurn ||
    DrivingEventType.speedBump => false,
  };

  /// The maneuver's icon, distinct per kind.
  IconData get icon => switch (this) {
    DrivingEventType.harshAcceleration => Icons.trending_up,
    DrivingEventType.harshBraking => Icons.trending_down,
    DrivingEventType.sharpTurn => Icons.u_turn_right,
    DrivingEventType.speedBump => Icons.speed,
    DrivingEventType.pothole => Icons.arrow_downward,
  };

  /// The localized name of the maneuver.
  String label(AppLocalizations l10n) => switch (this) {
    DrivingEventType.harshAcceleration => l10n.harshAcceleration,
    DrivingEventType.harshBraking => l10n.harshBraking,
    DrivingEventType.sharpTurn => l10n.sharpTurn,
    DrivingEventType.speedBump => l10n.speedBump,
    DrivingEventType.pothole => l10n.pothole,
  };

  /// The colour this maneuver is drawn in, derived from the theme so both
  /// brightnesses are covered.
  Color color(ColorScheme scheme) =>
      isWarning ? scheme.error : scheme.primary;
}
