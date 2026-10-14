import 'package:open_location_code/open_location_code.dart' as olc;

/// Offline Open Location Code (a.k.a. "Plus Code") support.
///
/// Plus Codes are computed entirely on-device by the pure-Dart
/// `open_location_code` package, so encoding a saved place or decoding a pasted
/// code never needs a network round-trip — MapNote stays offline-first.
///
/// Latitude/longitude remain the source of truth (they are what the map links
/// and the Drive backup are built from); the Plus Code is always derived from
/// them by [Place.plusCode], so the two can never drift apart.
class PlusCode {
  const PlusCode._();

  /// Number of significant digits produced by [encode].
  ///
  /// Ten is the shape Google Maps shows (`8FVC9G8F+6W`) and is accurate to
  /// roughly 13.5 m x 13.5 m — plenty for a saved parking bay or gate.
  static const int defaultCodeLength = 10;

  /// The Open Location Code alphabet, used to spot raw codes in text.
  static const String _alphabet = '23456789CFGHJMPQRVWX';

  /// A full (global) code: eight paired characters, the `+` separator, then two
  /// or more grid characters. People habitually group the first half
  /// (`8FVC 9G8F+6W`), so whitespace between the blocks is tolerated.
  static final RegExp _globalCode = RegExp(
    '^[$_alphabet]{4}\\s*[$_alphabet]{4}\\s*\\+\\s*[$_alphabet]{2,7}\$',
    caseSensitive: false,
  );

  /// A short (locality-relative) code such as `9G8F+6W`: fewer than eight
  /// characters before the `+`, so it only means something next to a reference
  /// location.
  static final RegExp _shortCode = RegExp(
    '^[$_alphabet]{2,7}\\s*\\+\\s*[$_alphabet]{2,3}\$',
    caseSensitive: false,
  );

  /// A Plus Code fragment anywhere inside a longer string (a shared link, a
  /// pasted address), full or short. Used by [extract] to carve a code out of
  /// the surrounding text.
  static final RegExp _codePattern = RegExp(
    '[$_alphabet]{2,8}\\s*\\+\\s*[$_alphabet]{2,7}',
    caseSensitive: false,
  );

  /// Encodes [latitude]/[longitude] into a global Plus Code.
  ///
  /// The encoder clips latitude to ±90 and normalises longitude to ±180, so an
  /// out-of-range fix still yields a decodable code.
  static String encode(
    double latitude,
    double longitude, {
    int codeLength = defaultCodeLength,
  }) {
    return olc.PlusCode.encode(
      olc.LatLng(latitude, longitude),
      codeLength: codeLength,
    ).toString();
  }

  /// Whether [value] is a *full* Plus Code.
  ///
  /// Short codes (e.g. `9G8F+6W`) are rejected here: they only mean something
  /// relative to a reference location. Use [isShortPlusCode] or the tolerant
  /// [decodeFlexible] for those.
  static bool isPlusCode(String value) => _isFullCode(_normalize(value));

  /// Whether [value] is a *short* (locality-relative) Plus Code.
  static bool isShortPlusCode(String value) => _isShortCode(_normalize(value));

  /// The first Plus Code (full or short) found anywhere in [value], normalised
  /// to upper case, or `null` when the text contains no valid code.
  ///
  /// This is what lets `9G8F+6W, Cairo` or a chunk of shared text be understood
  /// without asking the user to trim it first.
  static String? extract(String value) {
    for (final RegExpMatch match in _codePattern.allMatches(value)) {
      final String code = _normalize(match.group(0)!);
      if (_isFullCode(code) || _isShortCode(code)) return code;
    }
    return null;
  }

  /// Decodes a full Plus Code into its centre point, or `null` when [value] is
  /// not a valid, full code.
  ///
  /// The centre is returned rather than a corner so a round-trip
  /// [encode] → [decode] lands back in the same cell.
  static PlusCodePoint? decode(String value) {
    final String normalized = _normalize(value);
    if (!_isFullCode(normalized)) return null;
    final olc.CodeArea area = olc.PlusCode.unverified(normalized).decode();
    return PlusCodePoint(
      latitude: area.center.latitude,
      longitude: area.center.longitude,
    );
  }

  /// Decodes a full **or** short Plus Code.
  ///
  /// A full code is resolved on its own. A short code (`9G8F+6W`) needs a
  /// [reference] — the device's current fix, or the city the user typed next to
  /// it — which is used to recover the nearest full code; without a reference
  /// `null` is returned so the caller can ask for one.
  static PlusCodePoint? decodeFlexible(
    String value, {
    PlusCodePoint? reference,
  }) {
    final String? code = extract(value);
    if (code == null) return null;
    if (_isFullCode(code)) return decode(code);
    if (reference == null) return null;
    final olc.CodeArea area = olc.PlusCode.unverified(code)
        .recoverNearest(olc.LatLng(reference.latitude, reference.longitude))
        .decode();
    return PlusCodePoint(
      latitude: area.center.latitude,
      longitude: area.center.longitude,
    );
  }

  static bool _isFullCode(String normalized) {
    if (!_globalCode.hasMatch(normalized)) return false;
    final olc.PlusCode code = olc.PlusCode.unverified(normalized);
    return code.isValid && code.isFull();
  }

  static bool _isShortCode(String normalized) {
    if (!_shortCode.hasMatch(normalized)) return false;
    final olc.PlusCode code = olc.PlusCode.unverified(normalized);
    return code.isValid && code.isShort();
  }

  /// Uppercases the code and strips whitespace, so `8fvc 9g8f+6w` decodes the
  /// same as `8FVC9G8F+6W`.
  static String _normalize(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toUpperCase();
}

/// A decoded Plus Code centre, in signed decimal degrees.
class PlusCodePoint {
  const PlusCodePoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  String toString() => 'PlusCodePoint($latitude, $longitude)';
}
