import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/services/location_service.dart';
import 'package:routenote/src/utils/magnetic_declination.dart';
import 'package:routenote/src/utils/qibla_calculator.dart';
import 'package:routenote/src/widgets/qibla_indicator.dart';

/// Builds a [Position] with the fields geolocator 14 requires.
Position _fix(double lat, double lon) => Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// A magnetometer sample. [CompassEvent] only exposes the `fromList` factory;
/// index 2 is the accuracy, and `-1` maps to "unknown".
CompassEvent _heading(double degrees) =>
    CompassEvent.fromList(<double>[degrees, 0, -1]);

/// Declination stub injected by the widget tests so the compass never depends
/// on the real WMM model (whose values would shift the expected alignment).
double? _zeroDeclination(double latitude, double longitude) => 0;

/// Location source that never touches the geolocator channels. Every
/// [trackingPositionStream] call returns a fresh, hand-driven controller so a
/// test can push fixes and observe whether the widget cancelled its
/// subscription.
class _FakeLocationService extends LocationService {
  _FakeLocationService();

  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;

  /// When set, [isServiceEnabled] waits on it. Used to dispose the widget while
  /// the first `await` of `_startLocation` is still in flight.
  Completer<void>? gate;

  final List<StreamController<Position>> opened = <StreamController<Position>>[];
  int cancelled = 0;

  @override
  Future<bool> isServiceEnabled() async {
    final Completer<void>? pending = gate;
    if (pending != null) await pending.future;
    return serviceEnabled;
  }

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Stream<Position> trackingPositionStream({
    LocationSettings? settings,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    final StreamController<Position> controller =
        StreamController<Position>(onCancel: () => cancelled++);
    opened.add(controller);
    return controller.stream;
  }

  /// The OS-cached fix returned by [lastKnownPosition]; null by default so the
  /// other tests keep exercising the pure live-stream path.
  Position? lastKnown;

  @override
  Future<Position?> lastKnownPosition() async => lastKnown;
}

Widget _host(QiblaIndicator child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('QiblaCalculator.bearingFrom', () {
    test('points due north/south/east/west of Mecca correctly', () {
      // A point south of Mecca sees Mecca to the north, and so on. The
      // east/west bearings are close to (but not exactly) 90°/270° because the
      // great-circle initial bearing curves at a shared latitude.
      expect(
        QiblaCalculator.bearingFrom(
          QiblaCalculator.meccaLat - 1,
          QiblaCalculator.meccaLon,
        ),
        closeTo(0, 0.01),
      );
      expect(
        QiblaCalculator.bearingFrom(
          QiblaCalculator.meccaLat + 1,
          QiblaCalculator.meccaLon,
        ),
        closeTo(180, 0.01),
      );
      expect(
        QiblaCalculator.bearingFrom(
          QiblaCalculator.meccaLat,
          QiblaCalculator.meccaLon - 1,
        ),
        closeTo(90, 0.5),
      );
      expect(
        QiblaCalculator.bearingFrom(
          QiblaCalculator.meccaLat,
          QiblaCalculator.meccaLon + 1,
        ),
        closeTo(270, 0.5),
      );
    });

    test('rejects out-of-range latitudes', () {
      expect(QiblaCalculator.bearingFrom(91, 0), isNull);
      expect(QiblaCalculator.bearingFrom(-91, 0), isNull);
    });

    test('always returns a bearing within [0, 360)', () {
      const List<List<double>> points = <List<double>>[
        <double>[0, 0],
        <double>[51.5, -0.12], // London
        <double>[-33.87, 151.21], // Sydney
        <double>[40.71, -74.0], // New York
        <double>[-90, 0],
        <double>[90, 0],
      ];
      for (final List<double> point in points) {
        final double bearing = QiblaCalculator.bearingFrom(point[0], point[1])!;
        expect(bearing, greaterThanOrEqualTo(0));
        expect(bearing, lessThan(360));
      }
    });
  });

  group('MagneticDeclination.degreesAt', () {
    test('reproduces the published NOAA WMM-2020 test values', () {
      // WMM2020 Report, Table 6 (height 0 km): declination D in degrees, east
      // positive. The bundled model is WMM-2020, so it is exact at the epoch.
      expect(
        MagneticDeclination.degreesAt(80, 0, date: DateTime.utc(2020, 1, 1)),
        closeTo(-1.28, 0.2),
      );
      expect(
        MagneticDeclination.degreesAt(0, 120, date: DateTime.utc(2020, 1, 1)),
        closeTo(0.16, 0.2),
      );
      // The official table lists this point at longitude 240°E (≡ 120°W).
      expect(
        MagneticDeclination.degreesAt(-80, -120, date: DateTime.utc(2020, 1, 1)),
        closeTo(69.36, 0.2),
      );
    });

    test('is westward (negative) in New York and eastward (positive) in Sydney',
        () {
      expect(MagneticDeclination.degreesAt(40.71, -74.0), lessThan(-5));
      expect(MagneticDeclination.degreesAt(-33.87, 151.21), greaterThan(5));
    });

    test('returns null for out-of-range or non-finite coordinates', () {
      expect(MagneticDeclination.degreesAt(91, 0), isNull);
      expect(MagneticDeclination.degreesAt(-91, 0), isNull);
      expect(MagneticDeclination.degreesAt(0, 181), isNull);
      expect(MagneticDeclination.degreesAt(double.nan, 0), isNull);
      expect(MagneticDeclination.degreesAt(0, double.infinity), isNull);
    });
  });

  group('QiblaIndicator', () {
    testWidgets('applies the magnetic declination to the true heading',
        (WidgetTester tester) async {
      final _FakeLocationService locations = _FakeLocationService();
      final StreamController<CompassEvent> compass =
          StreamController<CompassEvent>.broadcast();

      await tester.pumpWidget(
        _host(
          QiblaIndicator(
            locationService: locations,
            compassEvents: compass.stream,
            declination: (double latitude, double longitude) => 10,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      locations.opened.single.add(_fix(30.0444, 31.2357));
      await tester.pump();
      await tester.pump();

      final double bearing = QiblaCalculator.bearingFrom(30.0444, 31.2357)!;

      // Declination is +10°, so the magnetometer must read 10° *less* than the
      // true Qibla bearing for the phone to actually point at Qibla.
      compass.add(_heading((bearing - 10 + 360) % 360));
      await tester.pump();
      await tester.pump();
      expect(find.text('Aligned with Qibla'), findsOneWidget);

      // Reading the raw, uncorrected bearing is now 10° off — the correction
      // really is applied, with the right sign.
      compass.add(_heading(bearing));
      await tester.pump();
      await tester.pump();
      expect(find.text('Aligned with Qibla'), findsNothing);

      await compass.close();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('shows the Qibla bearing once a GPS fix arrives',
        (WidgetTester tester) async {
      final _FakeLocationService locations = _FakeLocationService();
      final StreamController<CompassEvent> compass =
          StreamController<CompassEvent>.broadcast();

      await tester.pumpWidget(
        _host(
          QiblaIndicator(
            locationService: locations,
            compassEvents: compass.stream,
            declination: _zeroDeclination,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Before a fix: the placeholder copy, and no bearing text.
      expect(find.text('No GPS fix available'), findsOneWidget);
      expect(find.textContaining('°'), findsNothing);
      expect(locations.opened, hasLength(1));

      // A fix in Cairo.
      locations.opened.single.add(_fix(30.0444, 31.2357));
      await tester.pump();
      await tester.pump();

      final double bearing = QiblaCalculator.bearingFrom(30.0444, 31.2357)!;
      expect(find.textContaining('${bearing.round() % 360}°'), findsOneWidget);
      expect(find.text('No GPS fix available'), findsNothing);

      await compass.close();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a heading matching the Qibla bearing reports alignment',
        (WidgetTester tester) async {
      final _FakeLocationService locations = _FakeLocationService();
      final StreamController<CompassEvent> compass =
          StreamController<CompassEvent>.broadcast();

      await tester.pumpWidget(
        _host(
          QiblaIndicator(
            locationService: locations,
            compassEvents: compass.stream,
            declination: _zeroDeclination,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      locations.opened.single.add(_fix(30.0444, 31.2357));
      await tester.pump();
      await tester.pump();

      final double bearing = QiblaCalculator.bearingFrom(30.0444, 31.2357)!;

      // Point the phone at the Qibla: heading == bearing ⇒ relative ≈ 0.
      compass.add(_heading(bearing));
      await tester.pump();
      await tester.pump();
      expect(find.text('Aligned with Qibla'), findsOneWidget);

      // Turn 90° away: the alignment cue disappears.
      compass.add(_heading((bearing + 90) % 360));
      await tester.pump();
      await tester.pump();
      expect(find.text('Aligned with Qibla'), findsNothing);
      expect(find.text('Adjust phone direction to see Qibla'), findsOneWidget);

      await compass.close();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('disposing mid-await never subscribes and leaks nothing',
        (WidgetTester tester) async {
      final _FakeLocationService locations = _FakeLocationService()
        ..gate = Completer<void>();
      final StreamController<CompassEvent> compass =
          StreamController<CompassEvent>.broadcast();

      await tester.pumpWidget(
        _host(
          QiblaIndicator(
            locationService: locations,
            compassEvents: compass.stream,
            declination: _zeroDeclination,
          ),
        ),
      );
      await tester.pump();

      // The first `await` is still pending, so dismiss the sheet now.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      // Release the platform call *after* disposal.
      locations.gate!.complete();
      await tester.pump();
      await tester.pump();

      // The stale attempt must not have opened a position stream.
      expect(locations.opened, isEmpty);
      expect(locations.cancelled, 0);

      await compass.close();
    });

    testWidgets('cancels the position subscription on disposal',
        (WidgetTester tester) async {
      final _FakeLocationService locations = _FakeLocationService();
      final StreamController<CompassEvent> compass =
          StreamController<CompassEvent>.broadcast();

      await tester.pumpWidget(
        _host(
          QiblaIndicator(
            locationService: locations,
            compassEvents: compass.stream,
            declination: _zeroDeclination,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      locations.opened.single.add(_fix(0, 0));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('°'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pump();

      expect(locations.cancelled, 1);

      await compass.close();
    });

    testWidgets('a position stream error keeps the last fix',
        (WidgetTester tester) async {
      final _FakeLocationService locations = _FakeLocationService();
      final StreamController<CompassEvent> compass =
          StreamController<CompassEvent>.broadcast();

      await tester.pumpWidget(
        _host(
          QiblaIndicator(
            locationService: locations,
            compassEvents: compass.stream,
            declination: _zeroDeclination,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      locations.opened.single.add(_fix(0, 0));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('°'), findsOneWidget);

      // A transient error must not clear the reading or detach the widget.
      locations.opened.single.addError(StateError('boom'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('°'), findsOneWidget);

      await compass.close();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a denied permission is reported without subscribing',
        (WidgetTester tester) async {
      final _FakeLocationService locations = _FakeLocationService()
        ..permission = LocationPermission.deniedForever;
      final StreamController<CompassEvent> compass =
          StreamController<CompassEvent>.broadcast();

      await tester.pumpWidget(
        _host(
          QiblaIndicator(
            locationService: locations,
            compassEvents: compass.stream,
            declination: _zeroDeclination,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Location permission needed'), findsOneWidget);
      expect(locations.opened, isEmpty);

      await compass.close();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('renders the bearing from the last known fix before any live fix',
        (WidgetTester tester) async {
      final _FakeLocationService locations = _FakeLocationService()
        ..lastKnown = _fix(30.0444, 31.2357);
      final StreamController<CompassEvent> compass =
          StreamController<CompassEvent>.broadcast();

      await tester.pumpWidget(
        _host(
          QiblaIndicator(
            locationService: locations,
            compassEvents: compass.stream,
            declination: _zeroDeclination,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // The cached fix seeds the bearing without the live stream emitting once.
      final double bearing = QiblaCalculator.bearingFrom(30.0444, 31.2357)!;
      expect(find.textContaining('${bearing.round() % 360}°'), findsOneWidget);
      expect(find.text('No GPS fix available'), findsNothing);

      // The live stream is still subscribed so the seeded bearing can refine.
      expect(locations.opened, hasLength(1));
      expect(locations.opened.single.hasListener, isTrue);

      await compass.close();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a live fix refines the bearing seeded by the last known fix',
        (WidgetTester tester) async {
      final _FakeLocationService locations = _FakeLocationService()
        ..lastKnown = _fix(0, 0);
      final StreamController<CompassEvent> compass =
          StreamController<CompassEvent>.broadcast();

      await tester.pumpWidget(
        _host(
          QiblaIndicator(
            locationService: locations,
            compassEvents: compass.stream,
            declination: _zeroDeclination,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final double seededBearing = QiblaCalculator.bearingFrom(0, 0)!;
      expect(find.textContaining('${seededBearing.round() % 360}°'), findsOneWidget);

      // A fresh Cairo fix replaces the seeded bearing.
      locations.opened.single.add(_fix(30.0444, 31.2357));
      await tester.pump();
      await tester.pump();

      final double liveBearing = QiblaCalculator.bearingFrom(30.0444, 31.2357)!;
      expect(find.textContaining('${liveBearing.round() % 360}°'), findsOneWidget);
      expect(
        find.textContaining('${seededBearing.round() % 360}°'),
        findsNothing,
      );

      await compass.close();
      await tester.pumpWidget(const SizedBox());
    });
  });
}
