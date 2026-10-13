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
  /// Short codes (e.g. `9G8F+6W`) are rejected: they only mean something
  /// relative to a reference location, which a raw paste does not carry.
  static bool isPlusCode(String value) {
    final String normalized = _normalize(value);
    if (!_globalCode.hasMatch(normalized)) return false;
    final olc.PlusCode code = olc.PlusCode.unverified(normalized);
    return code.isValid && code.isFull();
  }

  /// Decodes a full Plus Code into its centre point, or `null` when [value] is
  /// not a valid, full code.
  ///
  /// The centre is returned rather than a corner so a round-trip
  /// [encode] → [decode] lands back in the same cell.
  static PlusCodePoint? decode(String value) {
    if (!isPlusCode(value)) return null;
    final olc.CodeArea area = olc.PlusCode.unverified(
      _normalize(value),
    ).decode();
    return PlusCodePoint(
      latitude: area.center.latitude,
      longitude: area.center.longitude,
    );
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
