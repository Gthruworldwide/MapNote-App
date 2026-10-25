import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';

/// Formats a segment's duration for the Motion history cards.
///
/// Sub-minute spans (the absorbed traffic-light case) never reach a card, but
/// the helper still answers honestly instead of printing "0 min".
String formatMotionDuration(Duration duration, AppLocalizations l10n) {
  if (duration <= Duration.zero) return l10n.durationZero;
  if (duration < const Duration(minutes: 1)) {
    return l10n.durationLessThanMinute;
  }
  if (duration < const Duration(hours: 1)) {
    return l10n.durationMinutes(duration.inMinutes);
  }
  return l10n.durationHoursMinutes(duration.inHours, duration.inMinutes % 60);
}

/// `09:15 – 10:02` for a segment, honouring the device's 12/24-hour setting.
///
/// The en dash is a separator, not translated text, and the whole string is
/// laid out with `Directionality`, so Arabic renders it end-to-start without a
/// second format.
String formatSegmentTimeRange(
  BuildContext context, {
  required DateTime start,
  required DateTime end,
}) {
  final MaterialLocalizations material = MaterialLocalizations.of(context);
  final bool alwaysUse24HourFormat = MediaQuery.alwaysUse24HourFormatOf(context);
  String format(DateTime at) => material.formatTimeOfDay(
    TimeOfDay.fromDateTime(at),
    alwaysUse24HourFormat: alwaysUse24HourFormat,
  );
  return '${format(start)} – ${format(end)}';
}
