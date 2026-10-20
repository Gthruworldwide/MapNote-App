import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:routenote/src/services/location_hub.dart';
import 'package:routenote/src/services/location_service.dart';

/// A [LocationService] that answers every platform call in memory and returns a
/// controllable broadcast feed, recording each open and whether the returned
/// stream was cancelled.
///
/// This is the instrument that makes the "no OS handle survives" claim
/// checkable: `openCount` counts how many times a platform stream was
/// requested, and `liveCount` how many of those are still uncancelled.
class _FakeLocationService extends LocationService {
  _FakeLocationService();

  /// One controller per open, so each subscription's cancellation is
  /// observable independently of the others.
  final List<StreamController<Position>> _controllers =
      <StreamController<Position>>[];

  /// How many times a position stream was handed out.
  int openCount = 0;

  /// The accuracy each open asked for, in order.
  final List<LocationAccuracy> requestedAccuracies = <LocationAccuracy>[];

  /// How many handed-out streams are still alive. Must reach 0 once every
  /// consumer releases — that is the OS handle being dropped.
  int get liveCount =>
      _controllers.where((StreamController<Position> c) => !c.isClosed).length;

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
    openCount++;
    requestedAccuracies.add(settings?.accuracy ?? LocationAccuracy.high);
    final StreamController<Position> controller =
        StreamController<Position>.broadcast(
      onCancel: () {
        // Broadcast streams keep the controller usable after the last listener
        // leaves, so "cancelled" is modelled explicitly.
      },
    );
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
      // The handle was lifted to the strongest request — but it is still the
      // same single client, so only one new open ever happened.
      expect(hub.openAccuracy, LocationAccuracy.high);
      expect(locations.openCount, 2);
      expect(locations.requestedAccuracies.last, LocationAccuracy.high);

      // Dropping the strong consumer falls back to the parked tier, again on
      // the same single handle.
      await hub.release(compass);
      expect(hub.openAccuracy, LocationAccuracy.lowest);
      expect(locations.openCount, 3);
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
  });
}
