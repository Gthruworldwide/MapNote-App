import '../../l10n/generated/app_localizations.dart';
import '../services/daily_track_engine.dart';

/// Human-readable copy for a refused tracker start, shared by every surface
/// that reports today's tracking (the AutoMotion card and the daily-GPS tile).
///
/// [fallback] covers [TrackStartFailure.none] — an unavailable state with no
/// specific reason — so each surface keeps its own generic wording.
String trackFailureText(
  AppLocalizations l10n,
  TrackStartFailure failure, {
  required String fallback,
}) {
  return switch (failure) {
    TrackStartFailure.locationServiceDisabled => l10n.locationChipServiceOff,
    TrackStartFailure.permissionDenied => l10n.locationChipPermissionDenied,
    TrackStartFailure.permissionDeniedForever => l10n.locationChipDeniedForever,
    TrackStartFailure.platformError => l10n.locationUnavailable,
    TrackStartFailure.none => fallback,
  };
}
