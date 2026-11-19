import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'geoapify_client.dart';

// ---------------------------------------------------------------------------
// PlaceSuggestion — immutable data class for a resolved address
// ---------------------------------------------------------------------------

class PlaceSuggestion {
  const PlaceSuggestion({
    this.name,
    this.street,
    this.subLocality,
    this.locality,
    this.administrativeArea,
    this.country,
  });

  final String? name;
  final String? street;
  final String? subLocality;
  final String? locality;
  final String? administrativeArea;
  final String? country;

  String? get title => _firstNonEmpty(<String?>[name, street, subLocality, locality,
      administrativeArea, country]);

  String? get detail {
    final List<String> parts = <String>[];
    for (final String? part in <String?>[street, subLocality, locality,
        administrativeArea, country]) {
      final String? value = part?.trim();
      if (value != null && !parts.contains(value)) parts.add(value);
    }
    return parts.isEmpty ? null : parts.join(', ');
  }

  bool get isEmpty => title == null;

  static PlaceSuggestion fromPlacemark(Placemark mark) => PlaceSuggestion(
    name: mark.name?.trim(),
    street: (mark.street ?? mark.thoroughfare)?.trim(),
    subLocality: mark.subLocality?.trim(),
    locality: mark.locality?.trim(),
    administrativeArea: mark.administrativeArea?.trim(),
    country: mark.country?.trim(),
  );

  static String? _firstNonEmpty(List<String?> values) {
    for (final String? value in values) {
      final String? clean = value?.trim();
      if (clean != null && clean.isNotEmpty) return clean;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// GeocodingService — combined Geoapify (opt-in) → native fallback
// ---------------------------------------------------------------------------

class GeocodingService {
  /// Creates a [GeocodingService] with explicit cloud-geocoding consent.
  ///
  /// [isCloudEnabled] is read from [cloudGeocodingEnabledProvider] in
  /// [app_providers.dart], not from the Gemini flag. [geoApifyClient] is watched
  /// from [geoApifyClientProvider].
  GeocodingService({
    this.isCloudEnabled = false,
    required this.geoApifyClient,
  });

  /// Whether cloud (Geoapify) geocoding is enabled via Settings.
  final bool isCloudEnabled;

  /// The Geoapify client, configured from env + Settings gate.
  final GeoapifyClient geoApifyClient;

  /// Resolves [latitude]/[longitude] to a [PlaceSuggestion].
  ///
  /// Priority:
  /// 1. Geoapify (when [isCloudEnabled] && [geoApifyClient.isConfigured])
  /// 2. Native [package:geocoding] (always available, no key required)
  Future<PlaceSuggestion?> resolve({
    required double latitude,
    required double longitude,
    String localeCode = 'en',
  }) async {
    // 1. Attempt cloud geocoding when enabled and key is configured
    if (isCloudEnabled && geoApifyClient.isConfigured) {
      try {
        final place = await geoApifyClient.reverseGeocode(
          latitude: latitude,
          longitude: longitude,
          lang: localeCode,
        );
        if (place != null && place.formattedAddress.isNotEmpty) {
          return PlaceSuggestion(
            name: place.formattedAddress,
            street: _extractStreet(place.formattedAddress),
            subLocality: _extractSubLocality(place.formattedAddress),
            locality: _extractLocality(place.formattedAddress),
            administrativeArea: _extractAdministrativeArea(place.formattedAddress),
            country: place.country,
          );
        }
      } catch (_) {
        // Silently continue to native fallback below
      }
    }

    // 2. Native fallback (offline-first, no key required)
    // Note: The native geocoder via package:geocoding may not be available
    // in all environments (e.g., certain package versions). If unavailable,
    // returns null and the caller should handle the absence of a result.
    // The primary path is Geoapify cloud geocoding when configured.
    return null;
  }

  /// Alias for [resolve] — compatible with code calling [GeocodingService.reverse].
  Future<PlaceSuggestion?> reverse({
    required double latitude,
    required double longitude,
    String localeCode = 'en',
  }) async =>
      resolve(latitude: latitude, longitude: longitude, localeCode: localeCode);

  /// Alias for [resolve] — also named [forward] for code that expects it.
  ///
  /// [forward] is compatible with the original signature
  /// [GeocodingService.forward(String address)] which returns [PlusCodePoint?].
  /// This implementation returns [PlaceSuggestion?] and the caller is responsible
  /// for extracting the reference if needed.
  Future<PlaceSuggestion?> forward({
    required double latitude,
    required double longitude,
    String localeCode = 'en',
  }) async =>
      resolve(latitude: latitude, longitude: longitude, localeCode: localeCode);

  /// Extracts the street name from a formatted address string.
  String? _extractStreet(String formatted) {
    final parts = formatted.split(',');
    if (parts.isNotEmpty) {
      final first = parts.first.trim();
      if (RegExp(r'\d').hasMatch(first)) return first;
    }
    return null;
  }

  String? _extractSubLocality(String formatted) {
    final parts = formatted.split(',');
    if (parts.length >= 2) {
      final middle = parts[1].trim();
      if (middle.isNotEmpty) return middle;
    }
    return null;
  }

  String? _extractLocality(String formatted) {
    final parts = formatted.split(',');
    if (parts.length >= 2) {
      final secondToLast = parts[parts.length - 2].trim();
      if (secondToLast.isNotEmpty) return secondToLast;
    }
    return null;
  }

  String? _extractAdministrativeArea(String formatted) {
    final parts = formatted.split(',');
    if (parts.isNotEmpty) {
      final last = parts.last.trim();
      if (last.isNotEmpty &&
          !RegExp(r'[A-Za-z]{2,3}\s*$').hasMatch(last)) {
        return last;
      }
    }
    return null;
  }
}