import 'dart:async';

import 'package:flutter/services.dart';

/// Centralised tactile feedback for the MapNote design system.
///
/// Every primary touchpoint (saving, copying, opening a sheet, handing off to a
/// maps app) fires the same crisp [HapticFeedback.lightImpact]. Keeping it in
/// one place means the "feel" can be tuned — or silenced — without hunting down
/// call sites. Failures are ignored: haptics are a nicety, never a requirement.
class Haptics {
  const Haptics._();

  /// A subtle, crisp tap for confirmations and menu openings.
  static void light() {
    unawaited(HapticFeedback.lightImpact());
  }
}
