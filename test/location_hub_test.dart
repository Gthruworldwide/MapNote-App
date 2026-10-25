import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:routenote/src/services/location_hub.dart';
import 'package:routenote/src/services/location_service.dart';

/// A [LocationService] that answers every platform call in memory and returns a
/// controllable feed, recording each open and whether the returned stream was
/// cancelled.
///
/// It models the **single-client** shape of `geolocator_android`'s position
/// channel (`StreamHandlerImpl`), because that shape is what decides whether a
/// profile change leaks an OS registration: `onListen` overwrites the plugin's
/// one `LocationClient` *without stopping the previous one*, and `onCancel`
/// stops whichever client is current at that moment — not necessarily the one
/// that was listened to. `liveCount` therefore counts real surviving OS
/// handles, and it must reach 0 once every consumer releases.
class _FakeLocationService extends LocationService {
  _FakeLocationService();

  /// One controller per open, in order, so each subscription's cancellation is
  /// observable independently of the others.
  final List<StreamController<Position>> _controllers =
      <StreamController<Position>>[];

  /// The plugin's one current client, shared by every open (see the class note).
  StreamController<Position>? _current;

  /// How many times a position stream was handed out.
  int get openCount => _controllers.length;

  /// The accuracy each open asked for, in order.
  final List<LocationAccuracy> requestedAccuracies = <LocationAccuracy>[];

  /// The settings each open was made with, in order — so a test can assert the
  /// shared handle actually carries the consumer's cadence and filter.
  final List<LocationSettings> requestedSettings = <LocationSettings>[];

  /// How many handed-out streams are still alive. Must reach 0 once every
  /// consumer releases — that is the OS handle being dropped.
  int get liveCount =>
      _controllers.where((StreamController<Position> c) => !c.isClosed).length;

  /// The settings of the one surviving platform handle, or `null` when the app
  /// is off the provider entirely.
  LocationSettings? get liveSettings {
    for (int i = 0; i < _controllers.length; i++) {
      if (!_controllers[i].isClosed) {
        return i < requestedSettings.length ? requestedSettings[i] : null;
      }
    }
    return null;
  }

  @override
  Future<bool> isServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;

  @override
  Stream<Position> trackingPositionStream({
    LocationSettings? settings,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    requestedAccuracies.add(settings?.accuracy ?? LocationAccuracy.high);
    if (settings != null) requestedSettings.add(settings);
    late final StreamController<Position> controller;
    controller = StreamController<Position>(
      onCancel: () {
        // `onCancel` stops whichever client is current *now*: this is the exact
        // behaviour that turns "listen before cancel" into a permanent leak.
        final StreamController<Position>? current = _current;
        if (current != null && !current.isClosed) {
          unawaited(current.close());
        }
      },
    );
    // `onListen` overwrites the one client, abandoning the previous controller
    // (it is never closed, so `liveCount` keeps counting it — the leak).
    _current = controller;
    _controllers.add(controller);
    return controller.stream;
  }

  /// Emits [position] to every live feed.
  void emit(Position position) {
    for (final StreamController<Position> controller in _controllers) {
      if (!controller.isClosed) controller.add(position);
    }
  }

  /// Closes every live feed, releasing the modelled handles.
  void closeAll() {
    for (final StreamController<Position> controller in _controllers) {
      if (!controller.isClosed) controller.close();
    }
  }
}

Position _position(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026, 1, 1),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  group('LocationHub', () {
    late _FakeLocationService locations;
    late LocationHub hub;

    setUp(() {
      locations = _FakeLocationService();
      // `Duration.zero` disables the hub's own reconnect: the fake feeds are
      // terminal, and the tests below assert on the handle's own lifetime.
      hub = LocationHub(
        locations: locations,
        reconnectDelay: Duration.zero,
      );
    });

    tearDown(() async {
      await hub.dispose();
      locations.closeAll();
    });

    test('opens exactly one platform stream no matter how many listeners',
        () async {
      final Object a = Object();
      final Object b = Object();
      final Object c = Object();

      hub.acquire(a, accuracy: LocationAccuracy.high).listen((_) {});
      hub.acquire(b, accuracy: LocationAccuracy.high).listen((_) {});
      hub.acquire(c, accuracy: LocationAccuracy.high).listen((_) {});

      // Concurrent consumers must not each spawn their own OS handle — that is
      // the `FusedLocationProvider` drain this hub exists to remove.
      expect(locations.openCount, 1);
      expect(hub.consumerCount, 3);

      final List<Position> seen = <Position>[];
      hub.positions.listen(seen.add);
      locations.emit(_position(1, 2));
      await Future<void>.delayed(Duration.zero);
      expect(seen.single.latitude, 1);
    });

    test('cancels the platform subscription the moment the last consumer '
        'releases', () async {
      final Object a = Object();
      final Object b = Object();

      hub.acquire(a, accuracy: LocationAccuracy.high).listen((_) {});
      hub.acquire(b, accuracy: LocationAccuracy.high).listen((_) {});
      expect(hub.isOpen, isTrue);

      await hub.release(a);
      // Still one consumer: the shared handle must stay open.
      expect(hub.isOpen, isTrue);
      expect(hub.consumerCount, 1);

      await hub.release(b);
      // No consumers left: the OS handle is dropped, not left lingering.
      expect(hub.isOpen, isFalse);
      expect(hub.openAccuracy, isNull);
      expect(hub.consumerCount, 0);
    });

    test('pauseAll cancels the subscription outright and forgets consumers',
        () async {
      hub.acquire(Object(), accuracy: LocationAccuracy.high).listen((_) {});
      expect(hub.isOpen, isTrue);

      await hub.pauseAll();

      expect(hub.isOpen, isFalse);
      expect(hub.openAccuracy, isNull);
      expect(hub.consumerCount, 0);
      expect(hub.hasPendingReconnect, isFalse);
    });

    test('releasing an unknown consumer is a no-op', () async {
      hub.acquire(Object(), accuracy: LocationAccuracy.high).listen((_) {});
      expect(hub.isOpen, isTrue);

      await hub.release(Object());

      expect(hub.isOpen, isTrue);
      expect(locations.openCount, 1);
    });

    test('serves a stronger tier by re-opening one handle, never two', () async {
      final Object parked = Object();
      final Object compass = Object();

      hub.acquire(parked, accuracy: LocationAccuracy.lowest).listen((_) {});
      expect(hub.openAccuracy, LocationAccuracy.lowest);

      hub.acquire(compass, accuracy: LocationAccuracy.high).listen((_) {});
      // A tier lift replaces the handle, and a replacement can only be
      // serialized behind the previous platform cancel (see `_syncHandle`), so
      // the swap settles a turn later.
      await pumpEventQueue();
      // The handle was lifted to the strongest request — but it is still the
      // same single client, so only one new open ever happened.
      expect(hub.openAccuracy, LocationAccuracy.high);
      expect(locations.openCount, 2);
      expect(locations.liveCount, 1);
      expect(locations.requestedAccuracies.last, LocationAccuracy.high);

      // Dropping the strong consumer falls back to the parked tier, again on
      // the same single handle.
      await hub.release(compass);
      expect(hub.openAccuracy, LocationAccuracy.lowest);
      expect(locations.openCount, 3);
      expect(locations.liveCount, 1);
    });

    test('acquire is idempotent per consumer and does not stack handles',
        () async {
      final Object consumer = Object();
      hub.acquire(consumer, accuracy: LocationAccuracy.high).listen((_) {});
      hub.acquire(consumer, accuracy: LocationAccuracy.high).listen((_) {});
      hub.acquire(consumer, accuracy: LocationAccuracy.high).listen((_) {});

      expect(hub.consumerCount, 1);
      expect(locations.openCount, 1);
    });

    test('dispose closes the broadcast feed and releases the handle', () async {
      final Stream<Position> feed =
          hub.acquire(Object(), accuracy: LocationAccuracy.high);
      bool done = false;
      feed.listen((_) {}, onDone: () => done = true);

      await hub.dispose();

      expect(hub.isOpen, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
      // A disposed hub hands out nothing and opens nothing.
      expect(await hub.acquire(Object(), accuracy: LocationAccuracy.high).isEmpty,
          isTrue);
      expect(locations.openCount, 1);
    });

    test('a paused hub re-opens cleanly on the next acquire', () async {
      final Object first = Object();
      hub.acquire(first, accuracy: LocationAccuracy.high).listen((_) {});

      await hub.pauseAll();
      expect(hub.isOpen, isFalse);

      final Object second = Object();
      final List<Position> seen = <Position>[];
      hub.acquire(second, accuracy: LocationAccuracy.high).listen(seen.add);
      expect(hub.isOpen, isTrue);

      locations.emit(_position(3, 4));
      await Future<void>.delayed(Duration.zero);
      expect(seen.single.longitude, 4);
    });

    test('the shared handle carries the consumer cadence, not a default',
        () async {
      // Regression: opening the handle without the consumer's interval left
      // Android holding a request at the 5 s default (`@+5s0ms` in
      // `dumpsys location`) even when the profile asked for something else.
      hub.acquire(
        Object(),
        accuracy: LocationAccuracy.high,
        interval: const Duration(seconds: 1),
        distanceFilter: 5,
      ).listen((_) {});
      await pumpEventQueue();

      expect(locations.requestedSettings, isNotEmpty);
      final LocationSettings settings = locations.requestedSettings.last;
      expect(settings.accuracy, LocationAccuracy.high);
      expect(settings.distanceFilter, 5);
      // AndroidSettings carries the pinned interval; the plain settings do not.
      if (settings is AndroidSettings) {
        expect(settings.intervalDuration, const Duration(seconds: 1));
      }
    });

    test('a changed cadence re-opens the one handle', () async {
      final Object consumer = Object();
      hub
          .acquire(
            consumer,
            accuracy: LocationAccuracy.high,
            interval: const Duration(seconds: 1),
          )
          .listen((_) {});
      expect(locations.openCount, 1);

      hub
          .acquire(
            consumer,
            accuracy: LocationAccuracy.high,
            interval: const Duration(seconds: 10),
          )
          .listen((_) {});
      await pumpEventQueue();

      // Still a single client — but at the new cadence.
      expect(hub.consumerCount, 1);
      expect(locations.openCount, 2);
      expect(locations.liveCount, 1);
      final LocationSettings settings = locations.requestedSettings.last;
      if (settings is AndroidSettings) {
        expect(settings.intervalDuration, const Duration(seconds: 10));
      }
    });

    test('a cadence change never leaves the previous OS registration alive',
        () async {
      // Regression: applying the engine profile re-acquires the *same* consumer
      // at a coarser tier. The hub used to listen to the new handle and only
      // then cancel the old one, and `geolocator_android` keeps one client per
      // position channel: `onListen` overwrote it (abandoning the previous
      // registration, never stopped) and the late `onCancel` then stopped the
      // new one. On device that left a permanent `@+5s0ms HIGH_ACCURACY` request
      // in `dumpsys location` for the app's whole life while the hub believed it
      // was running at 15 s / `medium` — and no idle pause could reach it.
      final Object tracker = Object();
      hub
          .acquire(
            tracker,
            accuracy: LocationAccuracy.high,
            interval: const Duration(seconds: 5),
            distanceFilter: 10,
          )
          .listen((_) {});
      expect(locations.openCount, 1);
      expect(locations.liveCount, 1);

      hub
          .acquire(
            tracker,
            accuracy: LocationAccuracy.medium,
            interval: const Duration(seconds: 15),
            distanceFilter: 15,
          )
          .listen((_) {});
      await pumpEventQueue();

      // Exactly one OS handle survives, and it is the *profiled* one.
      expect(locations.openCount, 2);
      expect(locations.liveCount, 1);
      expect(locations.liveSettings?.accuracy, LocationAccuracy.medium);
      final LocationSettings? live = locations.liveSettings;
      if (live is AndroidSettings) {
        expect(live.intervalDuration, const Duration(seconds: 15));
      }

      // And releasing takes the app off the provider entirely: no abandoned
      // registration is left behind to keep the receiver awake.
      await hub.release(tracker);
      expect(hub.isOpen, isFalse);
      expect(locations.liveCount, 0);
    });

    test('pausing mid-replacement still ends with no registration', () async {
      // A `pauseAll` can land while a replacement is waiting for the platform
      // cancel; the swap must not resurrect a handle afterwards.
      final Object tracker = Object();
      hub
          .acquire(
            tracker,
            accuracy: LocationAccuracy.high,
            interval: const Duration(seconds: 5),
          )
          .listen((_) {});
      hub
          .acquire(
            tracker,
            accuracy: LocationAccuracy.medium,
            interval: const Duration(seconds: 15),
          )
          .listen((_) {});

      await hub.pauseAll();
      await pumpEventQueue();

      expect(hub.isOpen, isFalse);
      expect(hub.consumerCount, 0);
      expect(locations.liveCount, 0);
    });
  });
}
