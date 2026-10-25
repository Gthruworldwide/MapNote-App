import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/data/models/daily_gps_summary.dart';
import 'package:routenote/src/data/models/track_point.dart';
import 'package:routenote/src/services/polyline_smoother.dart';

TrackPoint _point({
  double latitude = 30.123456789,
  double longitude = 31.987654321,
  double speed = 12.5,
  bool hasSpeed = true,
  double accuracy = 4,
  String activity = TrackPoint.inVehicle,
  int? steps,
}) => TrackPoint(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime(2026, 10, 20, 8, 30, 15),
  speed: speed,
  hasSpeed: hasSpeed,
  accuracy: accuracy,
  detectedActivity: activity,
  steps: steps,
);

void main() {
  group('TrackPoint compact form', () {
    test('round-trips coordinates at 5 decimals and keeps every scalar', () {
      final TrackPoint point = _point();
      final TrackPoint parsed = TrackPoint.tryFromList(point.toList())!;

      // ~1.1 m precision, the same convention as the stored `path`.
      expect(parsed.latitude, closeTo(point.latitude, 1e-5));
      expect(parsed.longitude, closeTo(point.longitude, 1e-5));
      expect(parsed.timestamp, point.timestamp);
      expect(parsed.speed, 12.5);
      expect(parsed.hasSpeed, isTrue);
      expect(parsed.accuracy, 4);
      expect(parsed.detectedActivity, TrackPoint.inVehicle);
    });

    test('a fix with no reported speed parses back as "not measured"', () {
      final TrackPoint parsed = TrackPoint.tryFromList(
        _point(hasSpeed: false, speed: 0, activity: '').toList(),
      )!;

      expect(parsed.hasSpeed, isFalse);
      expect(parsed.speed, 0);
      expect(parsed.detectedActivity, isEmpty);
    });

    test('a reported 0 m/s stays a measurement', () {
      // The classifier needs to tell "parked" apart from "speed unknown": the
      // first trust the zero, the second derives speed from the geometry.
      final List<Object?> row = _point(
        speed: 0,
        activity: TrackPoint.still,
      ).toList();

      expect(row[3], 0);
      final TrackPoint parsed = TrackPoint.tryFromList(row)!;
      expect(parsed.hasSpeed, isTrue);
      expect(parsed.speed, 0);
    });

    test('malformed rows are rejected, never thrown', () {
      expect(TrackPoint.tryFromList(null), isNull);
      expect(TrackPoint.tryFromList(<Object?>[]), isNull);
      expect(TrackPoint.tryFromList(<Object?>[30.0, 31.0]), isNull);
      expect(TrackPoint.tryFromList(<Object?>['x', 31.0, 1]), isNull);
      expect(TrackPoint.tryFromList(<Object?>[30.0, 'y', 1]), isNull);
      expect(TrackPoint.tryFromList(<Object?>[30.0, 31.0, 'z']), isNull);
    });

    test('the steps slot round-trips a measured count', () {
      // Exactly-representable coordinates, so the value identity assertion
      // below tests the steps slot rather than the 5-decimal rounding.
      final TrackPoint point = _point(
        latitude: 30.12346,
        longitude: 31.98765,
        steps: 24,
        activity: TrackPoint.walking,
      );
      final List<Object?> row = point.toList();

      expect(row, hasLength(7));
      expect(row[6], 24);

      final TrackPoint parsed = TrackPoint.tryFromList(row)!;
      expect(parsed.steps, 24);
      expect(parsed, point);
      expect(parsed.hashCode, point.hashCode);
    });

    test('a null steps slot means "not measured", not zero', () {
      final List<Object?> row = _point().toList();

      expect(row, hasLength(7));
      expect(row[6], isNull);
      expect(TrackPoint.tryFromList(row)!.steps, isNull);
    });

    test('a row written before the pedometer parses as "not measured"', () {
      // The upgrade case: today's parser reads yesterday's six-slot record.
      final List<Object?> modern = _point(steps: 12).toList();
      final List<Object?> legacy = modern.sublist(0, 6);

      expect(TrackPoint.tryFromList(legacy)!.steps, isNull);

      // …and the same row built literally, as the box would hold it.
      final TrackPoint parsed = TrackPoint.tryFromList(<Object?>[
        30.5,
        31.25,
        1760918400000,
        1.4,
        5,
        TrackPoint.codeWalking,
      ])!;
      expect(parsed.steps, isNull);
      expect(parsed.detectedActivity, TrackPoint.walking);
    });

    test('a negative slot cannot be a step count and stays unmeasured', () {
      // Only a corrupt or hand-edited record could carry this; rewinding a
      // day's totals would be worse than admitting the count is unknown.
      final List<Object?> row = _point(steps: 5).toList()..[6] = -3;

      expect(TrackPoint.tryFromList(row)!.steps, isNull);
    });

    test('withSteps copies the point and changes only the count', () {
      final TrackPoint point = _point();
      final TrackPoint counted = point.withSteps(7);

      expect(counted.steps, 7);
      expect(point.steps, isNull);
      expect(counted.latitude, point.latitude);
      expect(counted.longitude, point.longitude);
      expect(counted.timestamp, point.timestamp);
      expect(counted.speed, point.speed);
      expect(counted.hasSpeed, point.hasSpeed);
      expect(counted.accuracy, point.accuracy);
      expect(counted.detectedActivity, point.detectedActivity);
      expect(counted, isNot(point));
    });

    test('a bare three-column row parses with safe defaults', () {
      final TrackPoint parsed = TrackPoint.tryFromList(<Object?>[
        30.5,
        31.25,
        1760918400000,
      ])!;

      expect(parsed.latitude, 30.5);
      expect(parsed.longitude, 31.25);
      expect(parsed.speed, 0);
      expect(parsed.hasSpeed, isFalse);
      expect(parsed.accuracy, 0);
      expect(parsed.detectedActivity, isEmpty);
    });

    test('activity codes map both ways and unknown labels map to none', () {
      expect(
        TrackPoint.codeOf(TrackPoint.inVehicle),
        TrackPoint.codeInVehicle,
      );
      expect(TrackPoint.codeOf(TrackPoint.walking), TrackPoint.codeWalking);
      expect(TrackPoint.codeOf(TrackPoint.still), TrackPoint.codeStill);
      expect(TrackPoint.codeOf('Cycling'), TrackPoint.codeNone);
      expect(TrackPoint.codeOf(''), TrackPoint.codeNone);

      expect(
        TrackPoint.activityOf(TrackPoint.codeInVehicle),
        TrackPoint.inVehicle,
      );
      expect(TrackPoint.activityOf(TrackPoint.codeWalking), TrackPoint.walking);
      expect(TrackPoint.activityOf(TrackPoint.codeStill), TrackPoint.still);
      expect(TrackPoint.activityOf(TrackPoint.codeNone), isEmpty);
      expect(TrackPoint.activityOf(99), isEmpty);
    });

    test('fromRoutePoint carries geometry and time but no motion scalars', () {
      final TrackPoint point = TrackPoint.fromRoutePoint(
        RoutePoint(
          latitude: 30.5,
          longitude: 31.25,
          at: DateTime(2026, 10, 20, 9),
        ),
      );

      expect(point.latitude, 30.5);
      expect(point.longitude, 31.25);
      expect(point.timestamp, DateTime(2026, 10, 20, 9));
      expect(point.hasSpeed, isFalse);
      expect(point.accuracy, 0);
      expect(point.detectedActivity, isEmpty);
    });
  });

  group('DailyGpsSummary.track_points', () {
    final DateTime day = DateTime(2026, 10, 20);

    test('toMap writes the additive key and fromMap restores it', () {
      final List<TrackPoint> points = <TrackPoint>[
        _point(),
        TrackPoint(
          latitude: 30.2,
          longitude: 31.3,
          timestamp: DateTime(2026, 10, 20, 8, 31),
          speed: 0,
          hasSpeed: true,
          accuracy: 6,
          detectedActivity: TrackPoint.still,
        ),
      ];
      final DailyGpsSummary summary = DailyGpsSummary(
        date: day,
        totalKm: 1.2,
        trackPoints: points,
      );

      final Map<String, dynamic> map = summary.toMap();
      expect(map['track_points'], isA<List<Object?>>());
      expect((map['track_points']! as List<Object?>), hasLength(2));

      final DailyGpsSummary restored = DailyGpsSummary.fromMap(map);
      expect(restored.trackPoints, hasLength(2));
      expect(restored.trackPoints!.first.latitude,
          closeTo(points.first.latitude, 1e-5));
      expect(restored.trackPoints!.first.hasSpeed, isTrue);
      expect(restored.trackPoints!.last.detectedActivity, TrackPoint.still);
    });

    test('a summary written before the key existed parses as null', () {
      final DailyGpsSummary legacy = DailyGpsSummary(date: day, totalKm: 3);

      expect(legacy.toMap()['track_points'], isNull);
      expect(DailyGpsSummary.fromMap(legacy.toMap()).trackPoints, isNull);

      // …and a record that lacks the key entirely (the real upgrade case).
      final Map<String, dynamic> withoutKey = legacy.toMap()
        ..remove('track_points');
      expect(DailyGpsSummary.fromMap(withoutKey).trackPoints, isNull);
    });

    test('malformed rows are skipped instead of dropping the day', () {
      final List<TrackPoint> points = <TrackPoint>[_point()];
      final Map<String, dynamic> map = DailyGpsSummary(
        date: day,
        trackPoints: points,
      ).toMap();
      (map['track_points']! as List<Object?>)
        ..add(<Object?>[1, 2])
        ..add(<Object?>['nope', 31.0, 1]);

      final DailyGpsSummary restored = DailyGpsSummary.fromMap(map);
      expect(restored.trackPoints, hasLength(1));
      expect(restored.totalKm, 0);
    });

    test('track points do not change value identity', () {
      // Two summaries for the same day with the same metrics stay equal even
      // though their point lists differ: identity is the day's numbers.
      final DailyGpsSummary withoutPoints = DailyGpsSummary(date: day, totalKm: 2);
      final DailyGpsSummary withPoints = DailyGpsSummary(
        date: day,
        totalKm: 2,
        trackPoints: <TrackPoint>[_point()],
      );

      expect(withPoints, withoutPoints);
      expect(withPoints.hashCode, withoutPoints.hashCode);
    });
  });
}
