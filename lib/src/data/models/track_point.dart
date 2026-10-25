import 'package:geolocator/geolocator.dart';

import '../../services/polyline_smoother.dart';

/// One raw GPS fix as recorded while tracking in the background.
///
/// The daily summary's `path` keeps only geometry (lat/lon/time) because that
/// is all the route map needs; classification needs more — how fast the device
/// was actually moving and how trustworthy the fix is — so the tracker stamps
/// those alongside each vertex. The extra fields live in the summary's
/// *additive* `track_points` key (see `DailyGpsSummary`), which means:
///
///  * records written before this model existed still parse (the key is
///    absent → `null`), and
///  * the classifier falls back to deriving speed from consecutive vertices,
///    so an old day's history is still browsable.
///
/// Privacy (AGENT_SKILLS.md §5): a track point carries the same coordinate the
/// route already stores plus motion scalars — no place names, notes or
/// identity, and nothing leaves the device.
class TrackPoint {
  const TrackPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.speed = 0,
    this.hasSpeed = false,
    this.accuracy = 0,
    this.detectedActivity = '',
    this.steps,
  });

  final double latitude;
  final double longitude;

  /// When the fix was taken.
  final DateTime timestamp;

  /// Doppler speed reported by the receiver, in metres per second.
  ///
  /// Only meaningful when [hasSpeed] is true: a receiver that reports nothing
  /// and a receiver that reports "exactly zero" both leave this at `0`, and the
  /// difference decides whether the classifier trusts a parked fix or derives
  /// the speed from the distance between fixes.
  final double speed;

  /// Whether [speed] is a real measurement rather than the `0` default.
  final bool hasSpeed;

  /// Horizontal accuracy in metres. Zero means "not reported".
  final double accuracy;

  /// The motion-state hint recorded with the fix: [inVehicle], [walking] or
  /// [still]. Empty when the tracker had no sensor verdict to attach.
  final String detectedActivity;

  /// Steps taken between the **previous** fix and this one, as counted by the
  /// hardware step counter (`StepMeter.drain`).
  ///
  /// `null` means "not measured" — a build without a pedometer, a denied
  /// `ACTIVITY_RECOGNITION` permission, or a record written before steps were
  /// stored. `0` is a real measurement ("no step was taken"), which is what
  /// lets the classifier separate riding from walking with no guesswork.
  final int? steps;

  /// Activity labels persisted with a point. Protocol values, not a localized
  /// vocabulary: they are never rendered directly.
  static const String inVehicle = 'In_Vehicle';
  static const String walking = 'Walking';
  static const String still = 'Still';

  /// Builds a point from a platform fix plus the current activity hint and the
  /// steps counted since the previous fix (`null` when unmeasured).
  factory TrackPoint.fromPosition(
    Position position,
    String activity, {
    int? steps,
  }) =>
      TrackPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: position.timestamp,
        speed: position.hasSpeed ? position.speed : 0,
        hasSpeed: position.hasSpeed,
        accuracy: position.hasAccuracy ? position.accuracy : 0,
        detectedActivity: activity,
        steps: steps,
      );

  /// A point synthesised from a stored route vertex (legacy summaries, which
  /// carry no speed or activity).
  factory TrackPoint.fromRoutePoint(RoutePoint point, {String activity = ''}) =>
      TrackPoint(
        latitude: point.latitude,
        longitude: point.longitude,
        timestamp: point.at ?? DateTime.fromMillisecondsSinceEpoch(0),
        accuracy: 0,
        detectedActivity: activity,
      );

  /// The geometry-only view `PolylineSmoother` and the map consume.
  RoutePoint toRoutePoint() =>
      RoutePoint(latitude: latitude, longitude: longitude, at: timestamp);

  /// Activity codes used by [toList]/[tryFromList]. A numeric code keeps the
  /// persisted form compact — a day holds thousands of points.
  static const int codeNone = 0;
  static const int codeInVehicle = 1;
  static const int codeWalking = 2;
  static const int codeStill = 3;

  /// Compact persisted form:
  /// `[latitude, longitude, epochMillis, speedMps?, accuracyM, activityCode,
  /// steps?]`.
  ///
  /// Coordinates are rounded to 5 decimals (~1.1 m) exactly like the stored
  /// `path`, so the two representations agree on where the device was. The
  /// speed slot is `null` when the receiver reported none — that is how a
  /// derived-speed fix is told apart from one measuring exactly `0` m/s. The
  /// trailing steps slot is additive: rows written before the pedometer existed
  /// simply end at the activity code and parse back with `steps == null`.
  List<Object?> toList() => <Object?>[
        (latitude * 1e5).roundToDouble() / 1e5,
        (longitude * 1e5).roundToDouble() / 1e5,
        timestamp.millisecondsSinceEpoch,
        hasSpeed ? speed : null,
        accuracy,
        codeOf(detectedActivity),
        steps,
      ];

  /// A copy carrying a measured step count.
  TrackPoint withSteps(int? steps) => TrackPoint(
        latitude: latitude,
        longitude: longitude,
        timestamp: timestamp,
        speed: speed,
        hasSpeed: hasSpeed,
        accuracy: accuracy,
        detectedActivity: detectedActivity,
        steps: steps,
      );

  /// Tolerant parser: a malformed entry yields `null` rather than failing the
  /// whole day's restore.
  static TrackPoint? tryFromList(Object? value) {
    if (value is! List || value.length < 3) return null;
    final Object? lat = value[0];
    final Object? lon = value[1];
    final Object? ts = value[2];
    if (lat is! num || lon is! num || ts is! num) return null;
    final Object? rawSpeed = value.length > 3 ? value[3] : null;
    final Object? rawSteps = value.length > 6 ? value[6] : null;
    return TrackPoint(
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts.toInt()),
      speed: rawSpeed is num ? rawSpeed.toDouble() : 0,
      hasSpeed: rawSpeed is num,
      accuracy: value.length > 4 && value[4] is num
          ? (value[4]! as num).toDouble()
          : 0,
      detectedActivity: activityOf(
        value.length > 5 && value[5] is num ? (value[5]! as num).toInt() : codeNone,
      ),
      // A negative count cannot have come from a step counter: treat it as
      // "not measured" rather than rewinding a day's totals.
      steps: rawSteps is num && rawSteps >= 0 ? rawSteps.toInt() : null,
    );
  }

  /// The persisted code for [activity].
  static int codeOf(String activity) {
    switch (activity) {
      case inVehicle:
        return codeInVehicle;
      case walking:
        return codeWalking;
      case still:
        return codeStill;
      default:
        return codeNone;
    }
  }

  /// The activity label for a persisted [code].
  static String activityOf(int code) {
    switch (code) {
      case codeInVehicle:
        return inVehicle;
      case codeWalking:
        return walking;
      case codeStill:
        return still;
      default:
        return '';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TrackPoint &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.timestamp == timestamp &&
      other.speed == speed &&
      other.hasSpeed == hasSpeed &&
      other.accuracy == accuracy &&
      other.detectedActivity == detectedActivity &&
      other.steps == steps;

  @override
  int get hashCode => Object.hash(
        latitude,
        longitude,
        timestamp,
        speed,
        hasSpeed,
        accuracy,
        detectedActivity,
        steps,
      );

  @override
  String toString() =>
      'TrackPoint(${latitude.toStringAsFixed(5)}, '
      '${longitude.toStringAsFixed(5)}, ${timestamp.toIso8601String()}, '
      '${(speed * 3.6).toStringAsFixed(1)} km/h, $detectedActivity, '
      '${steps ?? '—'} steps)';
}
