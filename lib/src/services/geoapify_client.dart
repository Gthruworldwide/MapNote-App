import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';

/// Raised when a cloud geocoding request fails.
class GeoapifyException implements Exception {
  const GeoapifyException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A place resolved from Geoapify geocoding.
class GeoapifyPlace {
  const GeoapifyPlace({
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
    this.city,
    this.country,
  });

  /// formatted human-readable address (e.g. "Cairo Tower, Cairo, Egypt")
  final String formattedAddress;

  /// Latitude coordinate
  final double latitude;

  /// Longitude coordinate
  final double longitude;

  /// City name, when available
  final String? city;

  /// Country name, when available
  final String? country;
}

/// Cloud geocoding client for Geoapify API.
///
/// This is intentionally optional: when no API key is configured or
/// `cloudGeocodingEnabledProvider` is false, it reports [isConfigured] = false
/// and the app stays fully offline-first. Consent is separate from Gemini's
/// `cloudAiEnabledProvider`.
///
/// The key comes from `--dart-define=GEOAPIFY_API_KEY` and is fetched via
/// `String.fromEnvironment`. The key travels only as the `apiKey` query parameter
/// in the request URL — never embedded in logs or error surfaces.
class GeoapifyClient {
  GeoapifyClient({
    http.Client? httpClient,
    String? apiKey,
  })  : _httpClient = httpClient ?? http.Client(),
        _apiKey = apiKey ??
            String.fromEnvironment(
              'GEOAPIFY_API_KEY',
              defaultValue: '',
            );

  final http.Client _httpClient;
  final String _apiKey;

  bool get isConfigured => _apiKey.trim().isNotEmpty;

  ///Reverse geocoding: resolves [latitude]/[longitude] to a [GeoapifyPlace].
  ///
  /// Returns `null` when:
  /// - [isConfigured] is false (no key configured), or
  /// - the network request fails (timeout, no connectivity), or
  /// - the API returns no results, or
  /// - the response is malformed.
  ///
  /// On failure, the error is **opaque**: no stack trace, no request URI, no
  /// API key value. The caller receives `null` and may fall back to the native
  /// `package:geocoding`.
  Future<GeoapifyPlace?> reverseGeocode({
    required double latitude,
    required double longitude,
    String lang = 'en',
  }) async {
    if (!isConfigured) return null;

    final uri = Uri.https(
      'api.geoapify.com',
      '/v1/geocode/reverse',
      {
        'lat': latitude.toStringAsFixed(6),
        'lon': longitude.toStringAsFixed(6),
        'lang': lang,
        'format': 'json',
        'apiKey': _apiKey,
      },
    );

    return _executeRequest(uri);
  }

  /// Forward geocoding: resolves [query] (text address) to a [GeoapifyPlace].
  ///
  /// Returns `null` when:
  /// - [isConfigured] is false (no key configured), or
  /// - the query is empty, or
  /// - the network request fails, or
  /// - the API returns no results.
  ///
  /// On failure, the error is **opaque**: no stack trace, no request URI, no
  /// API key value. The caller receives `null` and may fall back to the native
  /// `package:geocoding`.
  Future<GeoapifyPlace?> searchAddress({
    required String query,
    String lang = 'en',
  }) async {
    if (!isConfigured) return null;

    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.https(
      'api.geoapify.com',
      '/v1/geocode/search',
      {
        'text': trimmed,
        'lang': lang,
        'limit': '1',
        'format': 'json',
        'apiKey': _apiKey,
      },
    );

    return _executeRequest(uri);
  }

  Future<GeoapifyPlace?> _executeRequest(Uri uri) async {
    try {
      final response = await _httpClient
          .get(uri)
          .timeout(AppConfig.geocodeTimeout);

      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('Geoapify HTTP status: ${response.statusCode}');
        }
        return null;
      }

      final Map<String, dynamic>? data =
          _decode(response.body) as Map<String, dynamic>?;

      final List<dynamic>? results = data?['results'] as List<dynamic>?;

      if (results == null || results.isEmpty) return null;

      final Map<String, dynamic> first = results.first as Map<String, dynamic>;

      final double? lat = (_parseNumber(first, 'lat') ?? first['lat'] as num?)?.toDouble();
      final double? lon = (_parseNumber(first, 'lon') ?? first['lon'] as num?)?.toDouble();
      final String? formatted = first['formatted'] as String?;

      if (lat == null || lon == null || formatted == null) return null;

      return GeoapifyPlace(
        formattedAddress: formatted,
        latitude: lat,
        longitude: lon,
        city: first['city'] as String?,
        country: first['country'] as String?,
      );
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint('Geoapify request timed out');
      }
      return null;
    } catch (_) {
      // رسائل خطأ مبهمة تماماً بدون تسريب مسارات أو إحداثيات
      return null;
    }
  }

  dynamic _decode(String rawBody) {
    try {
      return jsonDecode(rawBody);
    } catch (_) {
      return null;
    }
  }

  double? _parseNumber(dynamic object, String key) {
    final dynamic value = object[key];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      try {
        return double.parse(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Releases the underlying HTTP client.
  void close() => _httpClient.close();
}