import '../../../../data/models/place.dart';
import 'trip_stop.dart';

/// What the user should do with a detected trip stop.
enum PlaceLinkSuggestionKind {
  /// A saved place already sits at the stop — offer to link them.
  linkToExisting,

  /// Nothing is saved nearby — offer to save the stop as a new place.
  saveAsNew,
}

/// An advisory link between a detected [TripStop] and the user's saved places.
///
/// The suggestion is never applied automatically: the user confirms it. It
/// carries no analytics payload and is never persisted — it is a pure function
/// of today's route and the saved places.
class PlaceLinkSuggestion {
  const PlaceLinkSuggestion({
    required this.kind,
    required this.stop,
    required this.distanceMeters,
    this.place,
  });

  /// Whether the stop matches a saved place or should become a new one.
  final PlaceLinkSuggestionKind kind;

  /// The stop this suggestion is about.
  final TripStop stop;

  /// The saved place the stop matches, or `null` for
  /// [PlaceLinkSuggestionKind.saveAsNew].
  final Place? place;

  /// Distance from the stop to [place], in metres (`0` for a new place).
  final double distanceMeters;

  @override
  bool operator ==(Object other) =>
      other is PlaceLinkSuggestion &&
      other.kind == kind &&
      other.stop == stop &&
      other.place == place &&
      other.distanceMeters == distanceMeters;

  @override
  int get hashCode => Object.hash(kind, stop, place, distanceMeters);

  @override
  String toString() => 'PlaceLinkSuggestion($kind, $stop, place: ${place?.id})';
}
