import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/preferred_nav_app.dart';

/// Delegates navigation to installed maps apps via intents / deep links
/// (`url_launcher`). RouteNote deliberately has no in-app turn-by-turn engine.
class NavigationService {
  const NavigationService({this.preferredApp = PreferredNavApp.system});

  /// The user's chosen navigation app, applied to every [navigate] call.
  final PreferredNavApp preferredApp;

  /// Starts turn-by-turn navigation to [lat],[lng] in the preferred app.
  ///
  /// [PreferredNavApp.googleMaps] opens Google Maps via `google.navigation:`
  /// (Android) / `comgooglemaps://` (iOS); [PreferredNavApp.waze] opens Waze
  /// via `waze://`. [PreferredNavApp.system] keeps the platform default.
  /// Every path falls back to the generic Google Maps web route when the
  /// chosen app is not installed.
  Future<bool> navigate(double lat, double lng) async {
    final String destination = '$lat,$lng';
    switch (preferredApp) {
      case PreferredNavApp.googleMaps:
        final Uri uri = _googleNavigationUri(destination);
        if (await _tryLaunch(uri)) return true;
        return openInGoogleMaps(lat, lng);
      case PreferredNavApp.waze:
        if (await navigateWithWaze(lat, lng)) return true;
        return _navigateDefault(destination, lat, lng);
      case PreferredNavApp.system:
        return _navigateDefault(destination, lat, lng);
    }
  }

  Future<bool> _navigateDefault(
    String destination,
    double lat,
    double lng,
  ) async {
    if (await _tryLaunch(_googleNavigationUri(destination))) return true;
    return openInGoogleMaps(lat, lng);
  }

  /// The Google Maps turn-by-turn URI for the current platform.
  Uri _googleNavigationUri(String destination) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return Uri.parse(
        'comgooglemaps://?daddr=$destination&directionsmode=driving',
      );
    }
    return Uri.parse('google.navigation:q=$destination');
  }

  /// Delegates navigation to Waze using its deep link (`waze://`), falling
  /// back to the universal link when the app is not installed.
  Future<bool> navigateWithWaze(double lat, double lng) async {
    final String location = '$lat,$lng';
    final Uri deepLink = Uri.parse('waze://?ll=$location&navigate=yes');
    if (await _tryLaunch(deepLink)) return true;
    final Uri universal = Uri.parse(
      'https://waze.com/ul?ll=$location&navigate=yes',
    );
    return _tryLaunch(universal, external: true);
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
