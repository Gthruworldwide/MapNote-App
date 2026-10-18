import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:routenote/src/services/fused_location_service.dart';
import 'package:routenote/src/services/location_service.dart';

/// Builds a [Position] with the required fields for geolocator 14.
/// Coordinates are invented test values — no user data in this file.
Position _fix(
  double lat,
  double lon, {
  DateTime? at,
  double speed = 0,
  double accuracy = 5,
}) {
  return Position(
    latitude: lat,
    longitude: lon,
    timestamp: at ?? DateTime.now(),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
  );
}

/// Lets pending stream deliveries and microtasks land.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 10));

/// A [LocationService] that records every inner stream the fused service
/// opens (with the settings it was opened on) and hands back a stream the
/// test drives by hand — no platform involved.
class _RecordingLocationService extends LocationService {
  /// The settings of every inner stream, in open order.
  final List<LocationSettings> openedSettings = <LocationSettings>[];

  /// The controllers backing every inner stream, in open order.
  final List<StreamController<Position>> openedControllers =
      <StreamController<Position>>[];

  /// Whether the subscription of the inner stream at that index was cancelled
  /// (either superseded by a tier switch or torn down with the session).
  final List<bool> cancelled = <bool>[];

  /// The `onError` hook the fused service passed to each inner open.
  final List<void Function(Object error, StackTrace stackTrace)?> errorHooks =
      <void Function(Object, StackTrace)?>[];

  @override
  Stream<Position> trackingPositionStream({
    LocationSettings? settings,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    final int index = openedControllers.length;
    openedSettings.add(settings ?? LocationService.trackingLocationSettings);
    errorHooks.add(onError);
    cancelled.add(false);
    final StreamController<Position> controller = StreamController<Position>(
      onCancel: () {
        cancelled[index] = true;
      },
    );
    openedControllers.add(controller);
    return controller.stream;
  }

  /// Mimics one failure of the production reconnecting wrapper: report the
  /// failure through the [errorHooks] hook *and* let the raw error escape to
  /// whoever is listening on the inner stream.
  void deliverFailure(int index, Object error) {
    errorHooks[index]?.call(error, StackTrace.current);
    openedControllers[index].addError(error, StackTrace.current);
  }
}

void main() {
  group('FusedLocationService', () {
    test('opens the session on the high-accuracy tier immediately', () async {
      final _RecordingLocationService locationService =
          _RecordingLocationService();
      final FusedLocationService service = FusedLocationService(
        locationService: locationService,
        fallbackAfter: const Duration(milliseconds: 40),
        highAccuracyRetryEvery: const Duration(seconds: 10),
      );
      final LocationSettings high =
          LocationService.trackingSettingsFor();
      final LocationSettings network = LocationService.trackingSettingsFor(
        accuracy: LocationAccuracy.medium,
      );

      final StreamSubscription<Position> subscription = service
          .track(highSettings: high, networkSettings: network)
          .listen((Position _) {});
      await _settle();

      expect(service.mode, FusedLocationMode.highAccuracy);
      expect(locationService.openedSettings, hasLength(1));
      // The exact tracker profile is passed through untouched.
      expect(identical(locationService.openedSettings.single, high), isTrue);
      expect(locationService.openedSettings.single.accuracy,
          LocationAccuracy.high);

      await subscription.cancel();
    });

    test('falls back to the network tier when the high tier stays silent',
        () async {
      final _RecordingLocationService locationService =
          _RecordingLocationService();
      final FusedLocationService service = FusedLocationService(
        locationService: locationService,
        fallbackAfter: const Duration(milliseconds: 40),
        highAccuracyRetryEvery: const Duration(seconds: 10),
      );
      final LocationSettings high = LocationService.trackingSettingsFor();
      final LocationSettings network = LocationService.trackingSettingsFor(
        accuracy: LocationAccuracy.medium,
      );

      final List<double> latitudes = <double>[];
      final List<Object> outerErrors = <Object>[];
      final List<Object> hookErrors = <Object>[];
      final StreamSubscription<Position> subscription = service
          .track(
            highSettings: high,
            networkSettings: network,
            onError: (Object error, StackTrace _) => hookErrors.add(error),
          )
          .listen(
            (Position position) => latitudes.add(position.latitude),
            onError: (Object error, StackTrace _) => outerErrors.add(error),
          );

      await Future<void>.delayed(const Duration(milliseconds: 120));

      // After fallbackAfter of silence the session re-opened on the
      // low-power tier…
      expect(service.mode, FusedLocationMode.networkFallback);
      expect(locationService.openedSettings, hasLength(2));
      expect(locationService.openedSettings[1].accuracy,
          LocationAccuracy.medium);
      expect(identical(locationService.openedSettings[1], network), isTrue);
      // …the superseded high stream was released…
      expect(locationService.cancelled[0], isTrue);
      // …the switch itself is silent: no error on either channel…
      expect(outerErrors, isEmpty);
      expect(hookErrors, isEmpty);
      // …and the ORIGINAL subscription keeps receiving fixes that arrive on
      // the newly opened network stream.
      locationService.openedControllers[1].add(_fix(30.0444, 31.2357));
      await _settle();
      expect(latitudes, <double>[30.0444]);

      await subscription.cancel();
    });

    test('forwards fixes from whichever inner stream is current', () async {
      final _RecordingLocationService locationService =
          _RecordingLocationService();
      final FusedLocationService service = FusedLocationService(
        locationService: locationService,
        fallbackAfter: const Duration(milliseconds: 40),
        highAccuracyRetryEvery: const Duration(seconds: 10),
      );
      final LocationSettings high = LocationService.trackingSettingsFor();
      final LocationSettings network = LocationService.trackingSettingsFor(
        accuracy: LocationAccuracy.medium,
      );

      final List<double> latitudes = <double>[];
      final StreamSubscription<Position> subscription = service
          .track(highSettings: high, networkSettings: network)
          .listen((Position position) => latitudes.add(position.latitude));

      // A fix on the high tier, while it is the current stream.
      await _settle();
      locationService.openedControllers[0].add(_fix(1.5, 2.5));
      await _settle();
      expect(latitudes, <double>[1.5]);

      // Wait out fallbackAfter so the session moves to the network tier.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(locationService.openedSettings, hasLength(2));
      expect(service.mode, FusedLocationMode.networkFallback);

      locationService.openedControllers[1].add(_fix(3.5, 4.5));
      await _settle();
      expect(latitudes, <double>[1.5, 3.5]);

      // A fix arriving on the superseded stream is dropped, not misrouted.
      locationService.openedControllers[0].add(_fix(9.9, 9.9));
      await _settle();
      expect(latitudes, <double>[1.5, 3.5]);

      await subscription.cancel();
    });

    test('re-probes the high tier after the retry interval, then falls back '
        'again', () async {
      final _RecordingLocationService locationService =
          _RecordingLocationService();
      final FusedLocationService service = FusedLocationService(
        locationService: locationService,
        // Wide enough that every observation below lands comfortably inside
        // the window the mode is expected to hold.
        fallbackAfter: const Duration(milliseconds: 200),
        highAccuracyRetryEvery: const Duration(milliseconds: 400),
      );
      final LocationSettings high = LocationService.trackingSettingsFor();
      final LocationSettings network = LocationService.trackingSettingsFor(
        accuracy: LocationAccuracy.medium,
      );

      final StreamSubscription<Position> subscription = service
          .track(highSettings: high, networkSettings: network)
          .listen((Position _) {});

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(service.mode, FusedLocationMode.highAccuracy);
      expect(locationService.openedSettings, hasLength(1));

      // fallbackAfter elapsed: the session fell back to the network tier.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(service.mode, FusedLocationMode.networkFallback);
      expect(locationService.openedSettings, hasLength(2));
      expect(locationService.openedSettings[1].accuracy,
          LocationAccuracy.medium);

      // highAccuracyRetryEvery elapsed: the retry re-probed the high tier…
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(service.mode, FusedLocationMode.highAccuracy);
      expect(locationService.openedSettings, hasLength(3));
      expect(locationService.openedSettings[2].accuracy, LocationAccuracy.high);
      expect(identical(locationService.openedSettings[2], high), isTrue);

      // …and because that probe also stayed silent, the next fallback timer
      // dropped the session back to the network tier on its own.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(service.mode, FusedLocationMode.networkFallback);
      expect(locationService.openedSettings, hasLength(4));
      expect(locationService.openedSettings[3].accuracy,
          LocationAccuracy.medium);

      await subscription.cancel();
    });

    test('promotes back to the high tier the moment the service reports '
        'enabled', () async {
      final _RecordingLocationService locationService =
          _RecordingLocationService();
      // The retry probe is deliberately far away (10 s): the promotion below
      // must come from the service-status event, not from the retry timer.
      final FusedLocationService service = FusedLocationService(
        locationService: locationService,
        fallbackAfter: const Duration(milliseconds: 60),
        highAccuracyRetryEvery: const Duration(seconds: 10),
      );
      final LocationSettings high = LocationService.trackingSettingsFor();
      final LocationSettings network = LocationService.trackingSettingsFor(
        accuracy: LocationAccuracy.medium,
      );
      final StreamController<ServiceStatus> status =
          StreamController<ServiceStatus>();

      final StreamSubscription<Position> subscription = service
          .track(
            highSettings: high,
            networkSettings: network,
            serviceStatus: status.stream,
          )
          .listen((Position _) {});

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(service.mode, FusedLocationMode.networkFallback);
      expect(locationService.openedSettings, hasLength(2));

      status.add(ServiceStatus.enabled);
      await _settle();

      expect(service.mode, FusedLocationMode.highAccuracy);
      expect(locationService.openedSettings, hasLength(3));
      expect(locationService.openedSettings[2].accuracy, LocationAccuracy.high);
      expect(identical(locationService.openedSettings[2], high), isTrue);

      await subscription.cancel();
      await status.close();
    });

    test('surfaces inner-stream errors to the onError hook and the outer '
        'stream', () async {
      final _RecordingLocationService locationService =
          _RecordingLocationService();
      final FusedLocationService service = FusedLocationService(
        locationService: locationService,
        fallbackAfter: const Duration(seconds: 10),
        highAccuracyRetryEvery: const Duration(seconds: 10),
      );
      final LocationSettings high = LocationService.trackingSettingsFor();
      final LocationSettings network = LocationService.trackingSettingsFor(
        accuracy: LocationAccuracy.medium,
      );

      final List<Object> hookErrors = <Object>[];
      final List<Object> outerErrors = <Object>[];
      final List<double> latitudes = <double>[];
      final StreamSubscription<Position> subscription = service
          .track(
            highSettings: high,
            networkSettings: network,
            onError: (Object error, StackTrace _) => hookErrors.add(error),
          )
          .listen(
            (Position position) => latitudes.add(position.latitude),
            onError: (Object error, StackTrace _) => outerErrors.add(error),
          );
      await _settle();

      // The hook is plumbed into every inner open…
      expect(locationService.errorHooks, hasLength(1));
      expect(locationService.errorHooks.single, isNotNull);

      // …and a failure is reported on both paths (the engine arms gap
      // recovery from the hook; the raw error also reaches the subscriber).
      final Object error = StateError('gps receiver lost');
      locationService.deliverFailure(0, error);
      await _settle();

      expect(hookErrors, hasLength(1));
      expect(identical(hookErrors.single, error), isTrue);
      expect(outerErrors, hasLength(1));
      expect(identical(outerErrors.single, error), isTrue);

      // The session survives the error: the same inner stream keeps feeding
      // fixes afterwards.
      locationService.openedControllers[0].add(_fix(7.7, 8.8));
      await _settle();
      expect(latitudes, <double>[7.7]);

      await subscription.cancel();
    });

    test('cancels timers and inner subscriptions with the outer subscription',
        () async {
      final _RecordingLocationService locationService =
          _RecordingLocationService();
      final FusedLocationService service = FusedLocationService(
        locationService: locationService,
        fallbackAfter: const Duration(milliseconds: 40),
        highAccuracyRetryEvery: const Duration(seconds: 10),
      );
      final LocationSettings high = LocationService.trackingSettingsFor();
      final LocationSettings network = LocationService.trackingSettingsFor(
        accuracy: LocationAccuracy.medium,
      );
      final StreamController<ServiceStatus> status =
          StreamController<ServiceStatus>();

      final StreamSubscription<Position> subscription = service
          .track(
            highSettings: high,
            networkSettings: network,
            serviceStatus: status.stream,
          )
          .listen((Position _) {});

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(locationService.openedSettings, hasLength(2));
      expect(status.hasListener, isTrue);

      await subscription.cancel();

      // Every inner stream ever opened is released, and the OS provider feed
      // is unsubscribed too.
      expect(locationService.cancelled, everyElement(isTrue));
      expect(status.hasListener, isFalse);

      // A longer wait than fallbackAfter: a leaked fallback timer (or retry
      // timer) would re-open the stream here.
      final int opensAtCancel = locationService.openedSettings.length;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(locationService.openedSettings, hasLength(opensAtCancel));
      expect(service.mode, FusedLocationMode.networkFallback);

      await status.close();
    });

    test('runs two sequential sessions independently with fresh fallback '
        'timers', () async {
      final _RecordingLocationService locationService =
          _RecordingLocationService();
      final FusedLocationService service = FusedLocationService(
        locationService: locationService,
        fallbackAfter: const Duration(milliseconds: 40),
        highAccuracyRetryEvery: const Duration(seconds: 10),
      );
      final LocationSettings high = LocationService.trackingSettingsFor();
      final LocationSettings network = LocationService.trackingSettingsFor(
        accuracy: LocationAccuracy.medium,
      );

      // Session one runs, falls back, and is cancelled.
      final StreamSubscription<Position> first = service
          .track(highSettings: high, networkSettings: network)
          .listen((Position _) {});
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(service.mode, FusedLocationMode.networkFallback);
      expect(locationService.openedSettings, hasLength(2));
      await first.cancel();

      // Session two starts fresh: high tier first, its own fallback timer.
      final StreamSubscription<Position> second = service
          .track(highSettings: high, networkSettings: network)
          .listen((Position _) {});
      await _settle();
      expect(service.mode, FusedLocationMode.highAccuracy);
      expect(locationService.openedSettings, hasLength(3));
      expect(locationService.openedSettings[2].accuracy, LocationAccuracy.high);

      // …and that fresh timer falls back exactly once more.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(service.mode, FusedLocationMode.networkFallback);
      expect(locationService.openedSettings, hasLength(4));

      await second.cancel();
    });
  });
}
