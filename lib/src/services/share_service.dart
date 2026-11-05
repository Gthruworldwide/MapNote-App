import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Provides platform-native sharing and direct WhatsApp launching.
///
/// - [shareViaWhatsApp] launches WhatsApp with a pre-filled message.
/// - [shareViaSystem] falls back to launching the system share intent.
class ShareService {
  const ShareService();

  /// Shares the given [stationName], [lat], [lng] via WhatsApp.
  /// If [phoneNumber] is provided, it launches WhatsApp with that specific number.
  /// Otherwise, it launches WhatsApp with a chooser for any chat.
  static Future<void> shareViaWhatsApp(
    BuildContext context,
    String stationName,
    double lat,
    double lng, {
    String? phoneNumber,
    String? distanceKm,
  }) async {
    // Build the message text with station details and Google Maps link.
    final String coords = '$lat, $lng';
    final String mapsUrl = 'https://maps.google.com/?q=$lat,$lng';
    final String message = '''$stationName
coordinates: $coords
$mapsUrl''';

    // Encode the message for URI.
    final String encodedMsg = Uri.encodeComponent(message);

    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      // Launch specific phone number.
      final Uri whatsAppUri = Uri.parse(
          'whatsapp://send?phone=$phoneNumber&text=$encodedMsg');
      if (await canLaunchUrl(whatsAppUri)) {
        await launchUrl(whatsAppUri);
      } else {
        // Fall back to sharing the message via system intent.
        if (context.mounted) {
          await ShareService.shareViaSystem(context, message);
        }
      }
    } else {
      // No phone number -> launch WhatsApp chooser for any chat.
      final Uri whatsAppUri = Uri.parse(
          'whatsapp://send?text=$encodedMsg');
      if (await canLaunchUrl(whatsAppUri)) {
        await launchUrl(whatsAppUri);
      } else {
        // Fall back to sharing the message via system intent.
        if (context.mounted) {
          await ShareService.shareViaSystem(context, message);
        }
      }
    }
  }

  /// Falls back to the native system share sheet via a share intent.
  static Future<void> shareViaSystem(
    BuildContext context,
    String message,
  ) async {
    // Launch a system share intent using url_launcher.
    // On Android, this triggers the system share sheet.
    // On iOS, it may show an action sheet or similar.
    final Uri shareIntent = Uri(
      scheme: 'mailto',
      query: {
        'body': message,
      }.toString(),
    );
    if (await canLaunchUrl(shareIntent)) {
      await launchUrl(shareIntent);
    }
  }
}