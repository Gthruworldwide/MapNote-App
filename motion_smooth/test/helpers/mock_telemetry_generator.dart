import 'dart:math' as math;
import 'dart:typed_data';

import 'package:motion_smooth/motion_smooth.dart';

/// Zero-dependency synthetic telemetry generator for headless QA and simulation.
///
/// Generates realistic mock GPS/Telemetry streams representing standard and
/// edge-case driving conditions. All data uses the package's own types
/// (RoutePoint, DrivingEventType) and is fully deterministic given a seed
/// for reproducible testing.
@immutable
class MockTelemetryGenerator {
  /// Random number generator seeded for reproducibility.
  final Random _rng;

  /// Gaussian noise standard deviation in metres for GPS jitter.
  final double gpsNoiseSigmaM;

  /// Tunnel dropout duration in seconds.
  final Duration dropoutDuration;

  /// Constructor for [MockTelemetryGenerator].
  MockTelemetryGenerator({
    int? seed,
    this.gpsNoiseSigmaM = 2.0, // ±2m Gaussian jitter for "normal cruise"
    Duration? dropoutDuration,
  })  : _rng = seed != null ? Random(seed) : Random(),
        dropoutDuration = dropoutDuration ?? const Duration(seconds: 15);

  /// Generates a straight-line GPS track with Gaussian jitter for "normal cruise".
  ///
  /// - [startLat], [startLng]: Starting coordinates.
  /// - [numPoints]: Number of points in the track.
  /// - [spacingMeters]: Approximate spacing between consecutive points (~5m).
  /// - [durationSec]: Total track duration.
  ///
  /// Returns a [List<RoutePoint]> with Gaussian noise injected into each coordinate.
  List<RoutePoint> generateNormalCruise({
    required double startLat,
    required double startLng,
    required int numPoints,
    double spacingMeters = 5.0,
    Duration? durationSec,
  }) {
    final points = <RoutePoint>[];
    final geo = GeoMath();

    for (int i = 0; i < numPoints; i++) {
      // Deterministic spacing along a straight path
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

  /// Generates a track with a tunnel dropout segment for "signal loss" testing.
  ///
  /// - [trackPoints]: Base track points before the tunnel.
  /// - [dropoutStartIdx]: Index where dropout begins.
  /// - [dropoutEndIdx]: Index where dropout ends (inclusive).
  ///
  /// Returns a new [List<RoutePoint>] where points within the dropout range
  /// have their timestamps set to `null` to simulate GPS signal loss.
  List<RoutePoint> generateTunnelDropout({
    required List<RoutePoint> trackPoints,
    required int dropoutStartIdx,
    required int dropoutEndIdx,
  }) {
    final result = <RoutePoint>[];
    for (int i = 0; i < trackPoints.length; i++) {
      final point = trackPoints[i];
      if (i >= dropoutStartIdx && i <= dropoutEndIdx) {
        // During dropout: keep the point but mark timestamp as null
        result.add(RoutePoint(
          latitude: point.latitude,
          longitude: point.longitude,
          at: null, // GPS dropout: no valid fix
        ));
      } else {
        result.add(point);
      }
    }
    return result;
  }

  /// Generates a hard braking event sequence.
  ///
  /// Simulates a vehicle at [initialSpeedMps] braking to a stop over
  /// [durationSec] seconds, with GPS points sampled at regular intervals.
  ///
  /// The speed profile follows a quadratic deceleration:
  /// $$ v(t) = v_0 \times (1 - (t / T)^2) $$
  ///
  /// - [initialSpeedMps]: Initial speed in metres per second (e.g., 22.2 m/s = 80 km/h).
  /// - [durationSec]: Braking duration in seconds (e.g., 2.5 s).
  /// - [sampleIntervalSec]: GPS sample interval in seconds (e.g., 0.5 s).
  /// - [startLat], [startLng]: Starting position.
  ///
  /// Returns a [List<RoutePoint>] with speed encoded via the point timestamp
  /// metadata pattern compatible with [MotionBehaviorAnalyzer.observeSpeed].
  List<RoutePoint> generateHardBrakingEvent({
    required double initialSpeedMps,
    required double durationSec,
    required double sampleIntervalSec,
    required double startLat,
    required double startLng,
  }) {
    final points = <RoutePoint>[];
    final geo = GeoMath();

    int numSamples = (durationSec / sampleIntervalSec).ceil() + 1;

    for (int i = 0; i < numSamples; i++) {
      final double t = i * sampleIntervalSec; // elapsed time in seconds
      if (t > durationSec) break;

      // Quadratic deceleration: v(t) = v0 * (1 - (t/T)^2)
      final double progress = t / durationSec;
      final double speedAtT = initialSpeedMps * (1.0 - progress * progress);

      // Position: integral of v(t) dt = v0 * (t - t^3/(3T^2))
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

  /// Generates a sharp cornering (90° right turn) event sequence.
  ///
  /// Simulates a vehicle traveling northward, then making a 90° right turn
  /// at [turnSpeedMps] m/s, continuing eastward.
  ///
  /// - [initialSpeedMps]: Speed during straight segments in m/s.
  /// - [turnSpeedMps]: Speed during the cornering segment in m/s.
  /// - [turnRadiusMeters]: Effective turn radius.
  /// - [straightLengthMeters]: Length of straight segments before/after turn in metres.
  /// - [startLat], [startLng]: Starting position (corner apex at origin).
  ///
  /// Returns a [List<RoutePoint>] with the cornering trajectory.
  List<RoutePoint> generateSharpCorneringEvent({
    required double initialSpeedMps,
    required double turnSpeedMps,
    required double turnRadiusMeters,
    required double straightLengthMeters,
    required double startLat,
    required double startLng,
  }) {
    final points = <RoutePoint>[];
    final geo = GeoMath();

    // 1. Straight segment going North (increasing latitude)
    int straightPoints = (straightLengthMeters / 5.0).ceil();
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
            .toFloat(),
      );
      points.add(point);
    }

    // 2. Cornering segment: 90° right turn (following a circular arc)
    // Approximate with waypoints along the arc
    // A right-angle turn: from North (0°) to East (90°) via right-hand arc
    int cornerWaypoints = (turnRadiusMeters / 2.0).ceil();
    final double totalRadians = math.pi / 2; // 90 degrees in radians

    for (int i = 0; i <= cornerWaypoints; i++) {
      final double frac = i / cornerWaypoints;
      final double angle = frac * totalRadians; // 0 to 90°

      // Circular arc coordinates (center at (0, -radius), starting at angle 0 (North))
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

  /// Generates a "stationary jitter" period for testing noise filtering.
  ///
  /// Vehicle stopped at traffic light ($0$ km/h) with fluctuating raw GPS points
  /// to verify noise filtering and that the analyzer never interprets jitter as
  /// a maneuver.
  ///
  /// - [durationSec]: Duration of stationary period in seconds.
  /// - [startLat], [startLng]: Approximate stationary position.
  /// - [sampleIntervalSec]: GPS sample interval in seconds.
  ///
  /// Returns a [List<RoutePoint>] with no true movement, only Gaussian jitter.
  List<RoutePoint> generateStationaryJitter({
    required double durationSec,
    required double startLat,
    required double startLng,
    required double sampleIntervalSec,
  }) {
    final points = <RoutePoint>[];
    int sampleCount = (durationSec / sampleIntervalSec).ceil() + 1;

    for (int i = 0; i < sampleCount; i++) {
      final double lat = startLat + _rng.nextGaussian() * gpsNoiseSigmaM;
      final double lng = startLng + _rng.nextGaussian() * gpsNoiseSigmaM;
      final DateTime timestamp =
          DateTime.now().add(Duration(seconds: i * sampleIntervalSec));

      final RoutePoint point = RoutePoint(
        latitude: lat,
        longitude: lng,
        at: timestamp,
      );
      points.add(point);
    }
    return points;
  }

  /// Generates a complete mixed scenario containing all edge cases sequentially:
  /// normal cruise → tunnel dropout → hard braking → sharp cornering → stationary jitter.
  ///
  /// - [totalDurationSec]: Total scenario duration in seconds.
  /// - [startLat], [startLng]: Starting position.
  ///
  /// Returns a [List<RoutePoint>] with all scenarios sequenced together.
  List<RoutePoint> generateFullScenario({
    required double totalDurationSec,
    required double startLat,
    required double startLng,
  }) {
    final points = <RoutePoint>[];
    final geo = GeoMath();
    final double gpsSigma = gpsNoiseSigmaM;

    // 1. Normal cruise segment (0-15s): constant speed, Gaussian jitter
    points.addAll(generateNormalCruise(
      startLat: startLat,
      startLng: startLng,
      numPoints: 30,
      spacingMeters: 5.0,
      durationSec: 15.0,
    ));

    // 2. Tunnel dropout segment (15-30s): GPS signal loss
    points.addAll(generateTunnelDropout(
      trackPoints: points,
      dropoutStartIdx: points.length - 1,
      dropoutEndIdx: points.length + 20 - 1, // approximate
    ));

    // 3. Hard braking event (30-32.5s): 80 km/h → 0 km/h in 2.5 s
    // Start braking from where cruise left off (approx 50m east)
    final brakingPoints = generateHardBrakingEvent(
      initialSpeedMps: 22.2, // 80 km/h ≈ 22.2 m/s
      durationSec: 2.5,
      sampleIntervalSec: 0.5,
      startLat: startLat,
      startLng: startLng + 0.0005,
    );
    points.addAll(brakingPoints);

    // 4. Sharp 90° cornering (32.5-34s): 90° right turn
    final corneringPoints = generateSharpCorneringEvent(
      initialSpeedMps: 10.0,
      turnSpeedMps: 8.0,
      turnRadiusMeters: 15.0,
      straightLengthMeters: 20.0,
      startLat: startLat,
      startLng: startLng + 0.001,
    );
    points.addAll(corneringPoints);

    // 5. Stationary jitter (34-35s): vehicle stopped at traffic light
    points.addAll(generateStationaryJitter(
      durationSec: 1.0,
      startLat: startLat,
      startLng: startLng + 0.002,
      sampleIntervalSec: 0.2,
    ));

    return points;
  }

  // Helper: round double to int
  int roundToInt(double value) => value.round();
}
