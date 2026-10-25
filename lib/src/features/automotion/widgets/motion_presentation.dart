import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/trip_segment.dart';

/// The single source of truth for how a [MotionType] is presented: icon,
/// colour and localized label.
///
/// The timeline cards, the quick-stats bar and the route map's polylines all
/// read from here, so a segment can never be a blue "Drive" in the list and a
/// green "Walk" on the map. Colours come from [AppColors] tokens rather than raw
/// `Colors.*` values, which keeps the light and dark palettes in lock-step
/// (AGENT_SKILLS.md §4.1).
extension MotionTypePresentation on MotionType {
  /// The kind's icon — a car, a walking figure, a runner or a stop pin.
  IconData get icon => switch (this) {
    MotionType.vehicle => Icons.directions_car_filled_outlined,
    MotionType.walking => Icons.directions_walk,
    MotionType.running => Icons.directions_run,
    MotionType.stationary => Icons.location_on_outlined,
  };

  /// The kind's accent colour (card rail, icon, map polyline).
  Color get color => switch (this) {
    MotionType.vehicle => AppColors.motionDrive,
    MotionType.walking => AppColors.motionWalk,
    MotionType.running => AppColors.motionRun,
    MotionType.stationary => AppColors.motionStop,
  };

  /// The localized name of the kind.
  String label(AppLocalizations l10n) => switch (this) {
    MotionType.vehicle => l10n.motionTypeDrive,
    MotionType.walking => l10n.motionTypeWalk,
    MotionType.running => l10n.motionTypeRun,
    MotionType.stationary => l10n.motionTypeStopover,
  };

  /// Whether the kind is measured in steps (walking or running).
  ///
  /// The timeline cards use this to decide between a measured step count and
  /// the "≈" estimate, so running inherits the walking presentation rules
  /// instead of duplicating them.
  bool get isOnFoot =>
      this == MotionType.walking || this == MotionType.running;
}
