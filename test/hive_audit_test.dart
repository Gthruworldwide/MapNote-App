// Regression tests for the offline Hive privacy auditor's coordinate
// detector (`tool/hive_audit.dart`).
//
// The point of these tests is that the detector is not *vacuous*: a check
// that never fires would also "pass" on a box that leaks coordinates. So
// every "clean" assertion is paired with a "must catch" assertion.

import 'package:flutter_test/flutter_test.dart';

// Relative import: `tool/` sits outside `lib/`, so it is not reachable
// through a `package:routenote/...` URI.
import '../tool/hive_audit.dart';

/// Builds the raw bytes of a Latin-1 (single byte) Hive-like payload.
List<int> _bytes(String content) => content.codeUnits;

void main() {
  group('scanRawBytes', () {
    test('reports nothing for a clean health-log payload', () {
      const String clean =
          'health_events type uiLatency data screen home frames 60 '
          'janky 2 jankRatio 0.03 worstBuildMs 12.5 worstRasterMs 9.1 '
          'memoryMiB 84.3 backgroundS 0.5 foregroundS 14.2';
      expect(scanRawBytes(_bytes(clean)), isEmpty);
    });

    test('catches a latitude/longitude key', () {
      final List<String> hits = scanRawBytes(
        _bytes('data latitude 30.0444 longitude 31.2357'),
      );
      expect(hits, isNotEmpty);
      expect(hits.join(' '), contains('latitude'));
      expect(hits.join(' '), contains('longitude'));
    });

    test('catches a bare lat/lng number pair', () {
      final List<String> hits = scanRawBytes(_bytes('{"a":30.0444,"b":31.2357}'));
      expect(hits, isNotEmpty);
      expect(hits.join(' '), contains('lat/lng pair'));
    });

    test('catches a coords key', () {
      final List<String> hits = scanRawBytes(_bytes('data coords 30.0,31.0'));
      expect(hits.join(' '), contains('coords'));
    });

    test('does not fire on the uiLatency event type', () {
      // `uiLatency` contains "Lat"; a plain substring match would flag it.
      final List<String> hits = scanRawBytes(
        _bytes('type uiLatency timestamp 2026-10-21T13:42:13.379829Z'),
      );
      expect(hits, isEmpty);
    });

    test('does not fire on a value that merely looks numeric', () {
      // A single number in the latitude range is not a coordinate.
      final List<String> hits = scanRawBytes(_bytes('frames 60 janky 2'));
      expect(hits, isEmpty);
    });
  });

  group('structured event walk', () {
    test('flags a latitude key inside an event payload', () {
      final List<String> hits = <String>[];
      walkEventTree(
        <String, dynamic>{
          'type': 'uiLatency',
          'data': <String, dynamic>{'latitude': 30.0444},
        },
        'health_events',
        hits,
      );
      expect(hits, isNotEmpty);
      expect(hits.join(' '), contains('FORBIDDEN KEY'));
    });

    test('flags a coordinate-shaped key even when it is not forbidden', () {
      final List<String> hits = <String>[];
      walkEventTree(
        <String, dynamic>{
          'type': 'uiLatency',
          'data': <String, dynamic>{'geoLat': 30.0444},
        },
        'health_events',
        hits,
      );
      expect(hits.join(' '), contains('COORDINATE-SHAPED KEY'));
    });

    test('flags a lat/lng pair under a generic key', () {
      final List<String> hits = <String>[];
      walkEventTree(
        <String, dynamic>{
          'type': 'uiLatency',
          'data': <String, dynamic>{
            'a': 30.0444,
            'b': 31.2357,
          },
        },
        'health_events',
        hits,
      );
      expect(hits.join(' '), contains('LAT/LNG PAIR'));
    });

    test('leaves a clean event alone', () {
      final List<String> hits = <String>[];
      walkEventTree(
        <String, dynamic>{
          'type': 'drivingManeuver',
          'data': <String, dynamic>{
            'maneuver': 'harshBraking',
            'peak_mps2': 4.2,
            'duration_ms': 380,
          },
        },
        'health_events',
        hits,
      );
      expect(hits, isEmpty);
    });
  });
}
