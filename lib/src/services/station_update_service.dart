import 'package:flutter/material.dart';
import 'package:routenote/l10n/generated/app_localizations.dart';
import '../data/models/place.dart';
import 'package:url_launcher/url_launcher.dart';

/// Handles proposing station updates for Work Edition.
///
/// Compares original and updated [Place] objects, extracts changed fields,
/// and launches a WhatsApp share intent targeted to the Central Admin.
class StationUpdateService {
  const StationUpdateService();

  /// Compares [originalPlace] and [updatedPlace] to extract changed fields,
  /// formats a change report, and launches WhatsApp with the proposal.
  ///
  /// - [originalPlace] the pre-edit place (typically a default station)
  /// - [updatedPlace] the user-edited place with proposed changes
  /// - [employeeName] the name/ID of the staff member submitting the update
  /// - [context] build context for launching WhatsApp
  static Future<void> submitStationUpdate(
    BuildContext context,
    Place originalPlace,
    Place updatedPlace,
    String employeeName,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // Build the message text with station details.
    final String oldPhone = originalPlace.phoneNumber ?? '—';
    final String newPhone = updatedPlace.phoneNumber ?? '—';
    final String oldDisplay = originalPlace.displayName ?? '—';
    final String newDisplay = updatedPlace.displayName ?? '—';
    final String oldCategory = originalPlace.category ?? '—';
    final String newCategory = updatedPlace.category ?? '—';
    final bool oldDriveThru = originalPlace.hasDriveThru ?? false;
    final bool newDriveThru = updatedPlace.hasDriveThru ?? false;
    final int? oldSpeed = originalPlace.speedLimitZone;
    final int? newSpeed = updatedPlace.speedLimitZone;

    // Build the change report message.
    final List<String> changes = <String>[];

    if (oldPhone != newPhone) {
      changes.add(l10n.stationPhoneChanged(oldPhone, newPhone));
    }
    if (oldDisplay != newDisplay) {
      changes.add(l10n.stationDisplayNameChanged(oldDisplay, newDisplay));
    }
    if (oldCategory != newCategory) {
      changes.add(l10n.stationCategoryChanged(oldCategory, newCategory));
    }
    if (oldDriveThru != newDriveThru) {
      changes.add(
        l10n.stationDriveThruChanged(
          oldDriveThru ? l10n.yes : l10n.no,
          newDriveThru ? l10n.yes : l10n.no,
        ),
      );
    }
    if (oldSpeed != newSpeed) {
      changes.add(
        l10n.stationSpeedLimitChanged(
          oldSpeed?.toString() ?? '—',
          newSpeed?.toString() ?? '—',
        ),
      );
    }

    final String stationId = updatedPlace.id;
    final String reportHeader =
        '🏢 ${l10n.stationShareNameLine(updatedPlace.name, stationId)}\n';
    final String changesBody = changes.isNotEmpty
        ? changes.join('\n')
        : l10n.stationChangeNoChanges;
    final String submitterLine =
        '👤 ${l10n.stationChangeSubmittedBy(employeeName)}';
    final String message =
        '$reportHeader${l10n.stationChangeReportHeader}\n$changesBody\n$submitterLine';

    // Encode the message for URI and launch WhatsApp.
    final String encodedMsg = Uri.encodeComponent(message);
    final Uri whatsAppUri = Uri.parse('whatsapp://send?text=$encodedMsg');

    if (await canLaunchUrl(whatsAppUri)) {
      await launchUrl(whatsAppUri);
    } else {
      // Fall back to system share if WhatsApp is not installed.
      if (context.mounted) {
        await _shareViaSystem(context, message);
      }
    }
  }

  /// Falls back to the native system share sheet.
  static Future<void> _shareViaSystem(
    BuildContext context,
    String message,
  ) async {
    if (await canLaunchUrl(
      Uri(scheme: 'mailto', query: {'body': message}.toString()),
    )) {
      await launchUrl(
        Uri(scheme: 'mailto', query: {'body': message}.toString()),
      );
    }
  }
}
