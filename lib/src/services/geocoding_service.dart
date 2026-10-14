import 'package:geocoding/geocoding.dart';

import '../core/utils/plus_code.dart';

/// A human-readable place description resolved from coordinates.
///
/// Each field is nullable because the platform geocoder fills in only what it
/// knows; [title] and [detail] collapse whatever is present into labels the
/// "Add / Edit Place" screen can drop straight into the name and notes.
class PlaceSuggestion {
  const PlaceSuggestion({
    this.name,
    this.street,
    this.subLocality,
    this.locality,
    this.administrativeArea,
    this.country,
  });

  /// The venue/point-of-interest name, e.g. `Cairo Tower`.
  final String? name;

  /// The street address, e.g. `26th of July Corridor`.
  final String? street;

  /// Neighbourhood-level information, e.g. `Zamalek`.
  final String? subLocality;

  /// The city, e.g. `Cairo`.
  final String? locality;

  /// The governorate/state, e.g. `Cairo Governorate`.
  final String? administrativeArea;

  /// The country, e.g. `Egypt`.
  final String? country;

  /// The most specific label available — used to prefill the place name.
  String? get title => _firstNonEmpty(<String?>[
    name,
    street,
    subLocality,
    locality,
    administrativeArea,
    country,
  ]);

  /// A comma-separated breakdown — used to prefill the notes.
  String? get detail {
    final List<String> parts = <String>[];
    for (final String? part in <String?>[
      street,
      subLocality,
      locality,
      administrativeArea,
      country,
    ]) {
      final String? value = _clean(part);
      if (value != null && !parts.contains(value)) parts.add(value);
    }
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// Whether there is nothing worth suggesting.
  bool get isEmpty => title == null;

  /// Maps a platform [Placemark] onto the fields used by the UI.
  static PlaceSuggestion fromPlacemark(Placemark mark) => PlaceSuggestion(
    name: _clean(mark.name),
    street: _clean(mark.street ?? mark.thoroughfare),
    subLocality: _clean(mark.subLocality),
    locality: _clean(mark.locality),
    administrativeArea: _clean(mark.administrativeArea),
    country: _clean(mark.country),
  );
}

/// Reverse geocoding built on `package:geocoding` (the native Android/iOS
/// geocoder), plus a forward lookup used to resolve the city name typed next to
/// a short Plus Code.
///
/// Every call is best-effort: a device with no geocoder, no network, or no match
/// yields `null` instead of throwing, so the offline-first flow is never blocked.
class GeocodingService {
  GeocodingService({this.placemarkLookup, this.locationLookup});

  /// Overridable platform lookups, injected by tests.
  final Future<List<Placemark>> Function(double latitude, double longitude)?
  placemarkLookup;
  final Future<List<Location>> Function(String address)? locationLookup;

  Geocoding? _geocoding;

  Geocoding get _impl => _geocoding ??= Geocoding();

  /// Resolves [latitude]/[longitude] to a place description, or `null`.
  Future<PlaceSuggestion?> reverse({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final List<Placemark> marks = placemarkLookup != null
          ? await placemarkLookup!(latitude, longitude)
          : await _impl.placemarkFromCoordinates(latitude, longitude);
      for (final Placemark mark in marks) {
        final PlaceSuggestion suggestion = PlaceSuggestion.fromPlacemark(mark);
        if (!suggestion.isEmpty) return suggestion;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Resolves free-text [address] (typically a city name) to coordinates, or
  /// `null` when offline or unresolvable.
  Future<PlusCodePoint?> forward(String address) async {
    final String query = address.trim();
    if (query.isEmpty) return null;
    try {
      final List<Location> matches = locationLookup != null
          ? await locationLookup!(query)
          : await _impl.locationFromAddress(query);
      if (matches.isEmpty) return null;
      final Location first = matches.first;
      return PlusCodePoint(
        latitude: first.latitude,
        longitude: first.longitude,
      );
    } catch (_) {
      return null;
    }
  }
}

String? _clean(String? value) {
  final String trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

String? _firstNonEmpty(List<String?> values) {
  for (final String? value in values) {
    final String? clean = _clean(value);
    if (clean != null) return clean;
  }
  return null;
}
