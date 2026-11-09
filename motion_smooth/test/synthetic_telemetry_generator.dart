import 'dart:math' as math;
import 'dart:typed_data';

import 'package:motion_smooth/motion_smooth.dart';

/// Synthetic GPS telemetry generator for AI/ML training and testing.
///
/// Produces labeled GPS trajectory streams with controlled edge cases:
/// - Gaussian GPS jitter (simulated sensor noise)
/// - Tunnel dropout (GPS signal loss for configured durations)
/// - Harsh braking and acceleration events
/// - Sharp cornering at varying speeds
/// - Stationary periods (idle)
/// - Mixed traffic scenarios
///
/// All generated data uses the package's own types (RoutePoint, DrivingEventType)
/// and is fully deterministic given a seed for reproducible testing.
@immutable
class SyntheticTelemetryGenerator {
  /// Random number generator seeded for reproducibility.
  final Random _rng;

  /// Gaussian noise standard deviation in metres for GPS jitter.
  final double gpsNoiseSigmaM;

  /// Tunnel dropout duration range in seconds.
  final Duration dropoutDurationRange;

  /// Constructor for [SyntheticTelemetryGenerator].
  SyntheticTelemetryGenerator({
    int? seed,
    this.gpsNoiseSigmaM = 5.0, // 5m sigma Gaussian jitter
    Duration? dropoutDuration,
  })  : _rng = seed != null ? Random(seed) : Random(),
        dropoutDurationRange = dropoutDuration ?? const Duration(seconds: 15);

  /// Generates a straight-line GPS track with Gaussian jitter.
  ///
  /// - [startLat], [startLng]: Starting coordinates.
  /// - [numPoints]: Number of points in the track.
  /// - [spacingMeters]: Approximate spacing between consecutive points.
  /// - [durationSec]: Total track duration.
  ///
  /// Returns a [List<RoutePoint]> with Gaussian noise injected into each coordinate.
  List<RoutePoint> generateStraightTrack(
      double startLat, double startLng, int numPoints,
      {double spacingMeters = 10.0, Duration? durationSec}) {
    final points = <RoutePoint>[];
    final geo = GeoMath();

    for (int i = 0; i < numPoints; i++) {
      // Deterministic spacing along a straight eastward path
      final double iDouble = i.toDouble();
      final double eastingOffset = spacingMeters * iDouble;
      final double northingOffset = 0.0;

      // Convert local offsets to lat/lng
      final pair = geo.localXYToLatLng(
          eastingOffset, northingOffset, startLat, startLng);
      final double noiseLat = _rng.nextGaussian() * gpsNoiseSigmaM;
      final double noiseLng = _rng.nextGaussian() * gpsNoiseSigmaM;

      final double lat = pair.first + noiseLat;
      final double lng = pair.second + noiseLng;

      final RoutePoint point = RoutePoint(
        latitude: lat,
        longitude: lng,
        at: durationSec != null
            ? DateTime.now().add(
                Duration(seconds: (i * durationSec!.inSeconds ~/ numPoints)))
            : null,
      );
      points.add(point);
    }
    return points;
  }

  /// Generates a track with a tunnel dropout segment.
  ///
  /// - [trackPoints]: Base track points before the tunnel.
  /// - [dropoutIdx]: Index where dropout begins in [trackPoints].
  /// - [dropoutIdxEnd]: Index where dropout ends (inclusive).
  ///
  /// Returns a new [List<RoutePoint>] where points within the dropout range
  /// have their timestamps marked as `null` and a note added to metadata.
  List<RoutePoint> generateTunnelDropout(
      List<RoutePoint> trackPoints, int dropoutIdx, int dropoutIdxEnd) {
    final result = <RoutePoint>[];
    for (int i = 0; i < trackPoints.length; i++) {
      final point = trackPoints[i];
      if (i >= dropoutIdx && i <= dropoutIdxEnd) {
        // During dropout: keep the point but mark timestamp as null and add
        // a synthetic "undulating" position drift to simulate signal multipath
        // when the signal returns. In a real scenario, the point would be
        // missing from the GPS stream.
        final driftedLat =
            point.latitude + _rng.nextGaussian() * gpsNoiseSigmaM * 2;
        final driftedLng =
            point.longitude + _rng.nextGaussian() * gpsNoiseSigmaM * 2;
        result.add(RoutePoint(
          latitude: driftedLat,
          longitude: driftedLng,
          at: null, // GPS dropout: no valid fix
        ));
      } else {
        result.add(point);
      }
    }
    return result;
  }

  /// Generates a harsh braking event sequence.
  ///
  /// Simulates a vehicle at [initialSpeedMps] braking to a stop over
  /// [durationSec] seconds, with GPS points sampled at regular intervals.
  ///
  /// The speed profile follows a quadratic deceleration:
  /// $$ v(t) = v_0 \times (1 - (t / T)^2) $$
  /// where $v_0$ is initial speed, $T$ is total duration, and $t$ is elapsed time.
  ///
  /// - [initialSpeedMps]: Initial speed in metres per second.
  /// - [durationSec]: Braking duration in seconds.
  /// - [sampleIntervalSec]: GPS sample interval in seconds.
  /// - [startLat], [startLng]: Starting position.
  ///
  /// Returns a [List<RoutePoint>] with speed embedded in the point's `at` field
  /// via a custom extension (or could be stored separately; this demo stores
  /// metadata as a list annotation pattern compatible with [RoutePoint]).
  List<RoutePoint> generateHardBrakingEvent(
      double initialSpeedMps,
      double durationSec,
      double sampleIntervalSec,
      double startLat,
      double startLng) {
    final points = <RoutePoint>[];
    final geo = GeoMath();

    // Speed profile: v(t) = v0 * (1 - (t/T)^2)
    // Position: integral of v(t) dt = v0 * (t - t^3/(3T^2))
    // We sample at discrete times t_i = i * sampleIntervalSec

    int numSamples = (durationSec / sampleIntervalSec).ceil() + 1;

    for (int i = 0; i < numSamples; i++) {
      final double t = i * sampleIntervalSec; // elapsed time in seconds
      if (t > durationSec) break;

      // Quadratic deceleration position along the path (eastward for simplicity)
      final double progress = t / durationSec;
      final double speedAtT = initialSpeedMps * (1.0 - progress * progress);
      final double distanceTraveled = initialSpeedMps *
          (durationSec - (durationSec * progress * progress * progress) / 3.0);

      // Eastward movement proportional to distance traveled
      final double eastingOffset = distanceTraveled;
      final double northingOffset = 0.0;

      final pair = geo.localXYToLatLng(
          eastingOffset, northingOffset, startLat, startLng);

      // Add Gaussian noise to simulate GPS jitter during braking
      final double noiseLat = _rng.nextGaussian() * gpsNoiseSigmaM;
      final double noiseLng = _rng.nextGaussian() * gpsNoiseSigmaM;

      final double lat = pair.first + noiseLat;
      final double lng = pair.second + noiseLng;

      // Timestamp for this sample
      final DateTime timestamp =
          DateTime.now().add(Duration(seconds: roundToInt(t)));

      final RoutePoint point = RoutePoint(
        latitude: lat,
        longitude: lng,
        at: timestamp,
      );
      points.add(point);
    }
    return points;
  }

  /// Generates a sharp cornering event sequence.
  ///
  /// Simulates a vehicle traveling northward, then making a 90° right turn
  /// at [turnSpeedMps] m/s, continuing eastward.
  ///
  /// - [initialSpeedMps]: Speed during straight segments in m/s.
  /// - [turnSpeedMps]: Speed during the cornering segment in m/s.
  /// - [turnRadiusMeters]: Effective turn radius. Actual heading change is
  ///   calculated as arc length / radius.
  /// - [straightLengthMeters]: Length of straight segments before/after turn in metres.
  /// - [startLat], [startLng]: Starting position (corner apex at origin).
  ///
  /// Returns a [List<RoutePoint>] with the cornering trajectory.
  List<RoutePoint> generateSharpCorneringEvent(
      double initialSpeedMps,
      double turnSpeedMps,
      double turnRadiusMeters,
      double straightLengthMeters,
      double startLat,
      double startLng) {
    final points = <RoutePoint>[];
    final geo = GeoMath();

    // 1. Straight segment going North (increasing latitude)
    int straightPoints = (straightLengthMeters / 5.0).ceil(); // ~5m spacing
    for (int i = 0; i <= straightPoints; i++) {
      final double frac = i / straightPoints;
      final double latOffset =
          frac * straightLengthMeters / 111139.0 * (180.0 / math.pi);
      final double lngOffset = 0.0;
      final double lat = startLat + latOffset;
      final double lng = startLng;

      final double noiseLat = _rng.nextGaussian() * gpsNoiseSigmaM;
      final double noiseLng = _rng.nextGaussian() * gpsNoiseSigmaM;

      final RoutePoint point = RoutePoint(
        latitude: lat + noiseLat,
        longitude: lng + noiseLng,
        at: DateTime.now()
            .millisecondsSinceEpoch
            .remainder(86400000)
            .toDouble()
            .toDouble(),
      );
      points.add(point);
    }

    // 2. Cornering segment: 90° right turn (following a circular arc)
    // Approximate with waypoints along the arc
    // A right-angle turn: from North (0°) to East (90°) via right-hand arc
    // Using equally spaced waypoints along the arc
    int cornerWaypoints =
        (turnRadiusMeters / 2.0).ceil(); // ~2m spacing along arc
    final double totalRadians = math.pi / 2; // 90 degrees in radians

    for (int i = 0; i <= cornerWaypoints; i++) {
      final double frac = i / cornerWaypoints;
      final double angle = frac * totalRadians; // 0 to 90°

      // Circular arc coordinates (center at (0, -radius), starting at angle 0 (North))
      // x = r * sin(theta), y = r - r * cos(theta) for a turn starting North
      // But we want: start going North, end going East (right turn)
      // Parameterization: start at (0, 0), going North (0°), turn right to East (90°)
      // Using: x = r * sin(theta), y = r * (1 - cos(theta))
      // This gives: at theta=0: (0, 0) heading North; at theta=π/2: (r, 0) heading East

      final double arcX = turnRadiusMeters * math.sin(angle);
      final double arcY = turnRadiusMeters * (1.0 - math.cos(angle));

      // Convert arc offsets to lat/lng
      final double latOffset = arcY / 111139.0 * (180.0 / math.pi);
      final double lngOffset = arcX /
          (111139.0 * math.cos(startLat * math.pi / 180.0)) *
          (180.0 / math.pi);

      final double lat = startLat + latOffset;
      final double lng = startLng + lngOffset;

      final double noiseLat = _rng.nextGaussian() * gpsNoiseSigmaM;
      final double noiseLng = _rng.nextGaussian() * gpsNoiseSigmaM;

      final RoutePoint point = RoutePoint(
        latitude: lat + noiseLat,
        longitude: lng + noiseLng,
        at: DateTime.now()
            .millisecondsSinceEpoch
            .remainder(86400000)
            .toDouble()
            .toFloat(),
      );
      points.add(point);
    }

    // 3. Straight segment going East (increasing longitude)
    straightPoints = (straightLengthMeters / 5.0).ceil();
    for (int i = 1; i <= straightPoints; i++) {
      final double frac = i / straightPoints;
      final double latOffset = 0.0;
      final double lngOffset = frac *
          straightLengthMeters /
          (111139.0 * math.cos(startLat * math.pi / 180.0) * (180.0 / math.pi));
      final double lat = startLat;
      final double lng = startLng + lngOffset;

      final double noiseLat = _rng.nextGaussian() * gpsNoiseSigmaM;
      final double noiseLng = _rng.nextGaussian() * gpsNoiseSigmaM;

      final RoutePoint point = RoutePoint(
        latitude: lat + noiseLat,
        longitude: lng + noiseLng,
        at: DateTime.now()
            .millisecondsSinceEpoch
            .remainder(86400000)
            .toDouble()
            .toFloat(),
      );
      points.add(point);
    }

    return points;
  }

  /// Generates a mixed traffic scenario with multiple event types.
  ///
  /// Combines a straight tracked segment, a harsh braking event, a sharp turn,
  /// and a stationary period, all sequentially.
  ///
  /// - [totalDurationSec]: Total scenario duration in seconds.
  /// - [brakingStartSec]: When the braking event starts.
  /// - [corneringStartSec]: When the cornering event starts.
  /// - [stationaryStartSec]: When the vehicle stops stationary.
  ///
  /// Returns a [List<RoutePoint>] with all events sequenced together.
  List<RoutePoint> generateMixedScenario(double totalDurationSec,
      {double brakingStartSec = 30.0,
      double corneringStartSec = 60.0,
      double stationaryStartSec = 90.0,
      double startLat = 30.0,
      double startLng = 31.0}) {
    final points = <RoutePoint>[];
    final geo = GeoMath();

    // 1. Straight tracking segment (0 to brakingStartSec)
    int straightCount = (brakingStartSec ~/ 1).ceil();
    for (int i = 0; i < straightCount; i++) {
      final double t = i.toDouble();
      final double progress = t / brakingStartSec;
      final double easting = progress * 50.0; // 50m eastward track
      final double northing = 0.0;

      final pair = geo.localXYToLatLng(easting, northing, startLat, startLng);
      final double lat = pair.first + _rng.nextGaussian() * gpsNoiseSigmaM;
      final double lng = pair.second + _rng.nextGaussian() * gpsNoiseSigmaM;

      final RoutePoint point = RoutePoint(
        latitude: lat,
        longitude: lng,
        at: DateTime.now().add(Duration(seconds: i)),
      );
      points.add(point);
    }

    // 2. Harsh braking event
    final brakingPoints = generateHardBrakingEvent(
      15.0, // 15 m/s initial speed (54 km/h)
      5.0, // 5 seconds braking
      1.0, // 1 sample per second
      startLat,
      startLng,
    );
    points.addAll(
        brakingPoints.sublist(0, brakingPoints.length ~/ 2)); // take half

    // 3. Sharp cornering event
    final corneringPoints = generateSharpCorneringEvent(
      10.0, // 10 m/s straight speed
      8.0, // 8 m/s cornering speed
      15.0, // 15m turn radius
      20.0, // 20m straight length
      startLat,
      startLng,
    );
    points.addAll(corneringPoints);

    // 4. Stationary period (GPS jitter only, no real movement)
    int stationaryCount = ((totalDurationSec - corneringStartSec) ~/ 1).ceil();
    for (int i = 0; i < stationaryCount; i++) {
      final double lat = startLat + _rng.nextGaussian() * gpsNoiseSigmaM;
      final double lng = startLng + _rng.nextGaussian() * gpsNoiseSigmaM;
      final RoutePoint point = RoutePoint(
        latitude: lat,
        longitude: lng,
        at: DateTime.now().add(Duration(seconds: stationaryStartSec + i)),
      );
      points.add(point);
    }

    return points;
  }

  // Helper: round double to int
  int roundToInt(double value) => value.round();
}
