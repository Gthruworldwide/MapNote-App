import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Delegates navigation to installed maps apps via intents / deep links
/// (`url_launcher`). RouteNote deliberately has no in-app turn-by-turn engine.
class NavigationService {
  const NavigationService();

  /// Starts turn-by-turn navigation to [lat],[lng] in Google Maps.
  Future<bool> navigate(double lat, double lng) async {
    final String destination = '$lat,$lng';
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final Uri apple = Uri.parse(
        'comgooglemaps://?daddr=$destination&directionsmode=driving',
      );
      if (await _tryLaunch(apple)) return true;
    } else {
      final Uri android = Uri.parse('google.navigation:q=$destination');
      if (await _tryLaunch(android)) return true;
    }
    // Fallback: open routing in the web maps page / browser.
    return openInGoogleMaps(lat, lng);
  }

  /// Delegates navigation to Waze using its universal link.
  Future<bool> navigateWithWaze(double lat, double lng) {
    final Uri uri = Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes');
    return _tryLaunch(uri, external: true);
  }

  /// Shows routing options for the destination in Google Maps.
  Future<bool> openInGoogleMaps(double lat, double lng) async {
    final Uri uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
    );
    return _tryLaunch(uri, external: true);
  }

  /// Opens the raw location (map view, no routing).
  Future<bool> openLocation(double lat, double lng) async {
    final String coords = '$lat,$lng';
    if (defaultTargetPlatform == TargetPlatform.android) {
      final Uri geo = Uri.parse('geo:$lat,$lng?q=$coords');
      if (await _tryLaunch(geo)) return true;
    } else {
      final Uri apple = Uri.parse('comgooglemaps://?q=$coords');
      if (await _tryLaunch(apple)) return true;
    }
    return _tryLaunch(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$coords'),
      external: true,
    );
  }

  Future<bool> _tryLaunch(Uri uri, {bool external = false}) async {
    try {
      if (!await canLaunchUrl(uri)) return false;
      return await launchUrl(
        uri,
        mode: external
            ? LaunchMode.externalApplication
            : LaunchMode.platformDefault,
      );
    } catch (_) {
      return false;
    }
  }
}
