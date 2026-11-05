import 'package:flutter/material.dart';
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
    // Build the message text with station details.
    // We construct the message directly without relying on AppLocalizations
    // for the field names, since the change report uses its own labels.
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
      changes.add('Phone changed from "$oldPhone" to "$newPhone"');
    }
    if (oldDisplay != newDisplay) {
      changes.add('Display name changed from "$oldDisplay" to "$newDisplay"');
    }
    if (oldCategory != newCategory) {
      changes.add('Category changed from "$oldCategory" to "$newCategory"');
    }
    if (oldDriveThru != newDriveThru) {
      changes.add(
          'Has drive-thru changed from ${oldDriveThru ? 'yes' : 'no'} to ${newDriveThru ? 'yes' : 'no'}');
    }
    if (oldSpeed != newSpeed) {
      changes.add(
          'Speed limit zone changed from ${oldSpeed?.toString() ?? '—'} to ${newSpeed?.toString() ?? '—'}');
    }

    final String stationId = updatedPlace.id;
    final String reportHeader =
        '🏢 Station: ${updatedPlace.name} ($stationId)\n🔄 Changes:\n';
    final String changesBody =
        changes.isNotEmpty ? changes.join('\n') : 'No changes detected';
    final String submitterLine = '👤 Submitter: $employeeName';
    final String message = '$reportHeader$changesBody\n$submitterLine';

    // Encode the message for URI and launch WhatsApp.
    final String encodedMsg = Uri.encodeComponent(message);
    final Uri whatsAppUri = Uri.parse(
        'whatsapp://send?text=$encodedMsg');

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
      Uri(
        scheme: 'mailto',
        query: {'body': message}.toString(),
      ),
    )) {
      await launchUrl(
        Uri(
          scheme: 'mailto',
          query: {'body': message}.toString(),
        ),
      );
    }
  }
}
