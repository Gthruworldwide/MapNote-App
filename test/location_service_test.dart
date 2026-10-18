import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:routenote/src/services/location_service.dart';

/// Builds a [Position] with the required fields for geolocator 14.
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

void main() {
  group('reconnectingPositionStream', () {
    test('forwards fixes from the live source', () async {
      final StreamController<Position> source = StreamController<Position>();
      final Stream<Position> stream = reconnectingPositionStream(
        () => source.stream,
      );

      final List<double> latitudes = <double>[];
      final StreamSubscription<Position> subscription = stream.listen(
        (Position position) => latitudes.add(position.latitude),
      );

      source.add(_fix(1, 1));
      source.add(_fix(2, 2));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(latitudes, <double>[1, 2]);

      await subscription.cancel();
      await source.close();
    });

    test('re-opens the source after it errors', () async {
      final StreamController<Position> first = StreamController<Position>();
      final StreamController<Position> second = StreamController<Position>();
      int opened = 0;
      final List<Object> errors = <Object>[];

      final Stream<Position> stream = reconnectingPositionStream(
        () {
          opened += 1;
          return opened == 1 ? first.stream : second.stream;
        },
        initialBackoff: const Duration(milliseconds: 10),
        onError: (Object error, StackTrace _) => errors.add(error),
      );

      final List<double> latitudes = <double>[];
      final StreamSubscription<Position> subscription = stream.listen(
        (Position position) => latitudes.add(position.latitude),
      );

      first.add(_fix(1, 1));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(latitudes, <double>[1]);

      // The platform stream dies: the wrapper must report it and reconnect.
      first.addError(StateError('gps receiver lost'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(opened, 2);
      expect(errors, hasLength(1));

      // ...and the replacement stream keeps feeding fixes through.
      second.add(_fix(2, 2));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(latitudes, <double>[1, 2]);

      await subscription.cancel();
      await first.close();
      await second.close();
    });

    test('re-opens the source when it closes without an error', () async {
      final StreamController<Position> first = StreamController<Position>();
      final StreamController<Position> second = StreamController<Position>();
      int opened = 0;

      final Stream<Position> stream = reconnectingPositionStream(
        () {
          opened += 1;
          return opened == 1 ? first.stream : second.stream;
        },
        initialBackoff: const Duration(milliseconds: 10),
      );

      final List<double> latitudes = <double>[];
      final StreamSubscription<Position> subscription = stream.listen(
        (Position position) => latitudes.add(position.latitude),
      );

      // A stream that just ends is as dead as one that throws.
      await first.close();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(opened, 2);

      second.add(_fix(7, 7));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(latitudes, <double>[7]);

      await subscription.cancel();
      await second.close();
    });

    test('cancelling stops the reconnect loop', () async {
      final StreamController<Position> source = StreamController<Position>();
      int opened = 0;

      final Stream<Position> stream = reconnectingPositionStream(
        () {
          opened += 1;
          return source.stream;
        },
        initialBackoff: const Duration(milliseconds: 10),
      );

      final StreamSubscription<Position> subscription = stream.listen(
        (Position position) {},
      );

      source.addError(StateError('boom'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await subscription.cancel();

      final int openedAtCancel = opened;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // No new attempt after the tracker unsubscribed.
      expect(opened, openedAtCancel);

      await source.close();
    });
  });

  group('LocationService tracking settings', () {
    test('uses high accuracy with a 10 m movement filter', () {
      expect(LocationService.trackingDistanceFilterMeters, 10);
      expect(
        LocationService.trackingLocationSettings.accuracy,
        LocationAccuracy.high,
      );
      expect(LocationService.trackingLocationSettings.distanceFilter, 10);
    });
  });

  group('LocationService.trackingSettingsFor', () {
    // The request interval only exists on the platform-specific settings
    // (AndroidSettings.intervalDuration); the generic fallback settings of
    // the test host have no such field, so defaults are asserted on Android.
    void overrideToAndroid() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
    }

    test('defaults to high accuracy, a 5 s interval and the 10 m filter', () {
      overrideToAndroid();

      final LocationSettings settings = LocationService.trackingSettingsFor();
      expect(settings, isA<AndroidSettings>());
      final AndroidSettings android = settings as AndroidSettings;
      expect(android.accuracy, LocationAccuracy.high);
      expect(android.intervalDuration, const Duration(seconds: 5));
      expect(
        android.distanceFilter,
        LocationService.trackingDistanceFilterMeters,
      );
      // A Fused Location Provider request, not the legacy LocationManager.
      expect(android.forceLocationManager, isFalse);
    });

    test('honours explicit interval/accuracy overrides for sampling profiles',
        () {
      overrideToAndroid();

      final AndroidSettings settings = LocationService.trackingSettingsFor(
        accuracy: LocationAccuracy.medium,
        intervalDuration: const Duration(seconds: 15),
      ) as AndroidSettings;
      expect(settings.accuracy, LocationAccuracy.medium);
      expect(settings.intervalDuration, const Duration(seconds: 15));
      // The movement filter is independent of the request cadence.
      expect(
        settings.distanceFilter,
        LocationService.trackingDistanceFilterMeters,
      );
    });

    test('the background cap is medium accuracy at the same 5 s / 10 m '
        'cadence', () {
      overrideToAndroid();

      // The background-cap decision: medium is geolocator's name for
      // Android's balanced-power tier.
      expect(
        LocationService.backgroundTrackingLocationSettings.accuracy,
        LocationAccuracy.medium,
      );
      expect(
        LocationService.backgroundTrackingLocationSettings.distanceFilter,
        LocationService.trackingDistanceFilterMeters,
      );

      // The profile that decision is built from keeps the 5 s default —
      // only the accuracy tier changes between visible and backgrounded.
      final AndroidSettings backgroundProfile =
          LocationService.trackingSettingsFor(
        accuracy: LocationAccuracy.medium,
      ) as AndroidSettings;
      expect(backgroundProfile.accuracy, LocationAccuracy.medium);
      expect(backgroundProfile.intervalDuration, const Duration(seconds: 5));
      expect(backgroundProfile.forceLocationManager, isFalse);
    });
  });
}
