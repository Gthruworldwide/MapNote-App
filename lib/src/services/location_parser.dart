import 'package:http/http.dart' as http;

import '../core/utils/plus_code.dart';

/// A latitude/longitude pair (plus an optional place name) extracted from
/// pasted text, a map URL or a share intent.
class ParsedLocation {
  const ParsedLocation({
    required this.latitude,
    required this.longitude,
    this.name,
  });

  final double latitude;
  final double longitude;

  /// A human readable name when one is embedded in the source (for example the
  /// `/maps/place/<name>/` segment of a Google Maps URL).
  final String? name;

  @override
  String toString() => 'ParsedLocation($latitude, $longitude, $name)';
}

/// Extracts coordinates (and, when available, a place name) from:
///
/// * raw coordinate strings such as `30.0444, 31.2357`,
/// * raw Plus Codes / Open Location Codes such as `8FVC9G8F+6W`,
/// * Google Maps links (full links with `@lat,lng`, `/maps/place/...`,
///   `?q=`, `?query=`, `?ll=`, `?daddr=`, `?destination=`, plus `geo:` URIs),
/// * Google Maps short links (`maps.app.goo.gl`, `goo.gl/maps`, `g.co/kgs`),
///   which are resolved over the network by [resolveShortLink].
///
/// Parsing is intentionally lenient: the first supported pattern found in the
/// text wins, and any result is range-checked before it is returned.
class LocationParser {
  const LocationParser();

  /// The whole string is exactly `lat, lng` (optionally signed).
  static final RegExp _rawCoordinates = RegExp(
    r'^\s*([-+]?\d{1,3}(?:\.\d+)?)\s*[,;]\s*([-+]?\d{1,3}(?:\.\d+)?)\s*$',
  );

  /// `@lat,lng` — the map-viewport anchor used by Google Maps links.
  static final RegExp _atCoordinates = RegExp(
    r'@(-?\d{1,3}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)',
  );

  /// `/maps/place/lat,lng`.
  static final RegExp _placePathCoordinates = RegExp(
    r'/maps/place/(-?\d{1,3}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)',
  );

  /// Query parameters that carry coordinates, e.g. `?q=`, `?query=`, `?ll=`.
  static final RegExp _queryCoordinates = RegExp(
    r'[?&](?:q|query|ll|sll|daddr|saddr|destination|center)=(?:loc:)?'
    r'(-?\d{1,3}(?:\.\d+)?)(?:%2C|,|;|\+|%20|\s)'
    r'(-?\d{1,3}(?:\.\d+)?)',
    caseSensitive: false,
  );

  /// `geo:lat,lng`.
  static final RegExp _geoCoordinates = RegExp(
    r'geo:(-?\d{1,3}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)',
    caseSensitive: false,
  );

  /// A full global Plus Code anywhere in the text, e.g. `8FVC9G8F+6W` or the
  /// grouped `8FVC 9G8F+6W`.
  static final RegExp _plusCode = RegExp(
    r'[23456789CFGHJMPQRVWX]{4}\s*[23456789CFGHJMPQRVWX]{4}\s*\+\s*'
    r'[23456789CFGHJMPQRVWX]{2,7}',
    caseSensitive: false,
  );

  /// A `lat.dddd, lng.dddd` pair anywhere in the text (decimal point required
  /// so arbitrary integers are not mistaken for coordinates).
  static final RegExp _looseCoordinates = RegExp(
    r'(-?\d{1,3}\.\d+)\s*[,;]\s*(-?\d{1,3}\.\d+)',
  );

  /// `/maps/place/<name>/` — the URL-encoded place name.
  static final RegExp _placeName = RegExp(r'/maps/place/([^/@]+)');

  static final RegExp _url = RegExp(r'https?://\S+', caseSensitive: false);

  static final RegExp _shortLink = RegExp(
    r'https?://(?:maps\.app\.goo\.gl|goo\.gl/maps|g\.co/kgs)/',
    caseSensitive: false,
  );

  static final RegExp _coordinateOnly = RegExp(
    r'^-?\d+(?:\.\d+)?\s*[,;]\s*-?\d+(?:\.\d+)?$',
  );

  /// Parses [raw] without performing any network access.
  ///
  /// Returns `null` when [raw] contains no recognisable location.
  ParsedLocation? parse(String raw) {
    final String text = raw.trim();
    if (text.isEmpty) return null;

    // Fast path: the whole string is just "lat, lng".
    final Match? rawMatch = _rawCoordinates.firstMatch(text);
    if (rawMatch != null) {
      return _validated(rawMatch.group(1), rawMatch.group(2));
    }

    final String decoded = _decode(text);

    final Match? geo = _geoCoordinates.firstMatch(decoded);
    if (geo != null) {
      return _validated(geo.group(1), geo.group(2));
    }

    final Match? at = _atCoordinates.firstMatch(decoded);
    if (at != null) {
      return _validated(at.group(1), at.group(2), name: _extractName(decoded));
    }

    final Match? placePath = _placePathCoordinates.firstMatch(decoded);
    if (placePath != null) {
      return _validated(
        placePath.group(1),
        placePath.group(2),
        name: _extractName(decoded),
      );
    }

    final Match? query = _queryCoordinates.firstMatch(decoded);
    if (query != null) {
      return _validated(
        query.group(1),
        query.group(2),
        name: _extractName(decoded),
      );
    }

    // A raw Plus Code (Open Location Code), e.g. `8FVC9G8F+6W`.
    final PlusCodePoint? plusCode = _parsePlusCode(decoded);
    if (plusCode != null) {
      return ParsedLocation(
        latitude: plusCode.latitude,
        longitude: plusCode.longitude,
        name: _extractName(decoded),
      );
    }

    // Last resort: a decimal coordinate pair embedded in free text.
    final Match? loose = _looseCoordinates.firstMatch(decoded);
    if (loose != null) {
      return _validated(loose.group(1), loose.group(2));
    }

    return null;
  }

  /// Whether [raw] contains a Google Maps short link that needs the network to
  /// be resolved into coordinates.
  bool looksLikeShortMapLink(String raw) => _shortLink.hasMatch(raw.trim());

  /// Finds the first full Plus Code in [text] and decodes it.
  ///
  /// A Plus Code can only ever be decoded when it is a *full* global code;
  /// short codes (fewer than eight characters before the `+`) need a nearby
  /// reference location, which a raw paste does not carry, so they are ignored.
  PlusCodePoint? _parsePlusCode(String text) {
    for (final RegExpMatch match in _plusCode.allMatches(text)) {
      final PlusCodePoint? decoded = PlusCode.decode(match.group(0)!);
      if (decoded != null) return decoded;
    }
    return null;
  }

  /// Follows the redirect chain of a Google Maps short link and parses the
  /// final destination URL.
  ///
  /// Returns `null` when the link cannot be resolved (for example while
  /// offline). The optional [client] makes the method testable.
  Future<ParsedLocation?> resolveShortLink(
    String raw, {
    http.Client? client,
  }) async {
    final Match? match = _url.firstMatch(raw.trim());
    if (match == null) return null;

    final Uri? parsed = Uri.tryParse(match.group(0)!);
    if (parsed == null) return null;
    Uri current = parsed;

    final http.Client httpClient = client ?? http.Client();
    try {
      for (int hop = 0; hop < 6; hop++) {
        final ParsedLocation? direct = parse(current.toString());
        if (direct != null) return direct;

        final http.Request request = http.Request('GET', current)
          ..followRedirects = false;
        final http.StreamedResponse response = await httpClient
            .send(request)
            .timeout(const Duration(seconds: 10));
        await response.stream.drain<void>();

        final String? location = response.headers['location'];
        if (location == null ||
            response.statusCode < 300 ||
            response.statusCode >= 400) {
          break;
        }
        current = current.resolve(location);
      }
      return parse(current.toString());
    } catch (_) {
      return null;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Best-effort place name for share text that pairs a title with a link,
  /// e.g. `Cairo Tower\nhttps://maps.app.goo.gl/...`.
  String? guessName(String raw) {
    for (final String line in raw.split(RegExp(r'[\r\n]+'))) {
      final String candidate = line.trim();
      if (candidate.isEmpty) continue;
      if (_url.hasMatch(candidate)) continue;
      if (_coordinateOnly.hasMatch(candidate)) continue;
      if (_plusCode.hasMatch(candidate)) continue;
      if (candidate.length > 120) continue;
      return candidate;
    }
    return null;
  }

  ParsedLocation? _validated(String? lat, String? lng, {String? name}) {
    final double? latitude = double.tryParse(lat ?? '');
    final double? longitude = double.tryParse(lng ?? '');
    if (latitude == null || longitude == null) return null;
    if (latitude.abs() > 90 || longitude.abs() > 180) return null;
    return ParsedLocation(
      latitude: latitude,
      longitude: longitude,
      name: (name == null || name.isEmpty) ? null : name,
    );
  }

  String? _extractName(String decoded) {
    final Match? match = _placeName.firstMatch(decoded);
    if (match == null) return null;
    final String name = _decode(match.group(1)!).replaceAll('+', ' ').trim();
    if (name.isEmpty) return null;
    if (_coordinateOnly.hasMatch(name)) return null;
    if (_plusCode.hasMatch(name)) return null;
    if (name.toLowerCase() == 'search') return null;
    return name;
  }

  static String _decode(String value) {
    try {
      return Uri.decodeFull(value);
    } catch (_) {
      return value;
    }
  }
}
