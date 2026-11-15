import '../models/place.dart';

/// Decodes a raw value read from a Hive box into a [Place].
///
/// The `places` and `station_data` boxes store `Place.toMap()` payloads, so a
/// reader that assumes the box hands back a [Place] instance throws
/// `NoSuchMethodError` on the first real record. That is exactly what turned
/// every Admin Approval proposal into an "Incomplete proposal" card: the card
/// read `station?.displayName` from a `Map`.
///
/// Decoding defensively keeps one corrupt or legacy record from taking a whole
/// screen (or an approval) down: anything that is not a `Place` or a map-shaped
/// place returns `null` instead of throwing.
Place? placeFromHiveValue(Object? value) {
  if (value == null) return null;
  if (value is Place) return value.id.isEmpty ? null : value;
  if (value is! Map) return null;
  try {
    final Place place = Place.fromMap(Map<String, dynamic>.from(value));
    return place.id.isEmpty ? null : place;
  } catch (_) {
    return null;
  }
}
