/// A sustained stop on a recorded trip: a coordinate the device dwelled at for
/// at least [dwell].
///
/// Derived, never stored — recomputed from the AutoMotion path whenever the
/// suggestions are needed, so adding this type adds no Hive schema and no
/// migration risk.
class TripStop {
  const TripStop({
    required this.latitude,
    required this.longitude,
    required this.arrivedAt,
    required this.dwell,
  });

  /// WGS-84 latitude of the stop's representative (centroid) point.
  final double latitude;

  /// WGS-84 longitude of the stop's representative (centroid) point.
  final double longitude;

  /// When the device arrived (the first fix of the dwell cluster).
  final DateTime arrivedAt;

  /// How long the device stayed inside the stop radius.
  final Duration dwell;

  @override
  bool operator ==(Object other) =>
      other is TripStop &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.arrivedAt == arrivedAt &&
      other.dwell == dwell;

  @override
  int get hashCode => Object.hash(latitude, longitude, arrivedAt, dwell);

  @override
  String toString() =>
      'TripStop($latitude, $longitude, ${dwell.inMinutes}m)';
}
