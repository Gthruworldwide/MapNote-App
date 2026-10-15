import 'package:geomag/geomag.dart';

/// Local magnetic declination — the angle between **magnetic north** (which the
/// device magnetometer reports) and **true north** (which
/// `QiblaCalculator.bearingFrom` measures the Qibla bearing from).
///
/// Backed by the bundled World Magnetic Model (WMM-2020) through the pure-Dart
/// `geomag` package, so it resolves entirely on-device: no network, no platform
/// channel, and deterministic enough to unit-test against published values.
///
/// Declination is signed, positive to the **east** of true north. For example a
/// value of `+4.8` means magnetic north lies 4.8° east of true north, so a
/// magnetic reading must be *increased* by 4.8° to become a true heading.
class MagneticDeclination {
  const MagneticDeclination._();

  /// Metres per foot; the WMM implementation takes altitude in feet.
  static const double _metresToFeet = 3.280839895013123;

  /// Declination in degrees for [latitude]/[longitude], or `null` when the
  /// coordinates are out of range or the model cannot produce a value.
  ///
  /// [altitudeMeters] defaults to sea level and [date] to "now"; both only
  /// fine-tune the result, so the common magnetic → true correction can omit
  /// them. Callers must treat `null` as "no correction available" and fall back
  /// to the raw magnetic heading.
  static double? degreesAt(
    double latitude,
    double longitude, {
    double altitudeMeters = 0,
    DateTime? date,
  }) {
    if (!latitude.isFinite || !longitude.isFinite) return null;
    if (latitude < -90 || latitude > 90) return null;
    if (longitude < -180 || longitude > 180) return null;

    try {
      final GeoMagResult result = GeoMag().calculate(
        latitude,
        longitude,
        altitudeMeters * _metresToFeet,
        date,
      );
      final double declination = result.dec;
      return declination.isFinite ? declination : null;
    } catch (_) {
      // A malformed model/input must never break the compass.
      return null;
    }
  }
}
