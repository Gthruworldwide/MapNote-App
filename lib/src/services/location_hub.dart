import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'location_service.dart';

/// The single owner of MapNote's live OS location subscription.
///
/// Android's `FusedLocationProvider` registers an app as a *location client*
/// for every distinct request it holds, and every open `getPositionStream` is
/// one such client. Two Dart listeners therefore mean two OS handles, two
/// `WorkSource` entries, and two reasons for the OS to keep the GNSS receiver
/// awake — which is what the system surfaces to the user as "frequently checks
/// your location".
///
/// This hub is the one client: it opens **exactly one** platform subscription,
/// fans the fixes out to any number of broadcast listeners, and is
/// reference-counted so the handle is released the moment the last consumer
/// lets go. The Qibla compass, the daily trackers and any future consumer all
/// share it instead of each spawning their own handle.
///
/// ## Settings are part of the identity
///
/// A consumer asks for a power tier ([LocationAccuracy]) and a cadence. The hub
/// serves the **strongest** tier any live consumer has asked for and re-opens
/// the platform stream only when that resolved tier changes — so a compass
/// wanting `high` while a tracker is parked on `lowest` lifts the single shared
/// handle rather than adding a second one. When every consumer releases, the
/// handle is cancelled outright ([release] / [pauseAll]), which is the state
/// the idle engine wants: zero registered clients, receiver asleep.
///
/// Refcounted opening is deliberately *not* tried-and-keep-open: a lingering
/// "passthrough" handle is exactly the drain this class exists to remove. See
/// `AGENT_SKILLS.md` §6.
class LocationHub {
  LocationHub({
    this.locations = const LocationService(),
    this.reconnectDelay = const Duration(seconds: 2),
  });

  /// The location source the single shared handle is opened from. Injectable so
  /// tests can drive fixes without touching the geolocator platform channels.
  final LocationService locations;

  /// Backoff before re-opening after an unexpected stream end. Kept short: the
  /// daily trackers apply their own, longer, capped backoff on top when they
  /// need resilience, and the hub's job is only to not leave a dead handle.
  /// [Duration.zero] disables the hub's own reconnect entirely (tests that want
  /// the platform stream to be terminal).
  final Duration reconnectDelay;

  final StreamController<Position> _positions =
      StreamController<Position>.broadcast(sync: true);

  /// Consumers currently holding the handle open, with the accuracy each wants.
  final Map<Object, LocationAccuracy> _consumers =
      <Object, LocationAccuracy>{};

  /// The accuracy the live handle was opened at, or `null` when none is open.
  LocationAccuracy? _openAccuracy;

  StreamSubscription<Position>? _subscription;
  Timer? _reconnectTimer;
  bool _closed = false;

  /// A shared broadcast feed of live fixes. Buffers nothing while unlistened.
  Stream<Position> get positions => _positions.stream;

  /// Whether an OS location handle is currently registered.
  bool get isOpen => _subscription != null;

  /// How many consumers hold the handle open (diagnostics/tests).
  int get consumerCount => _consumers.length;

  /// The accuracy the open handle runs at, or `null` when closed.
  LocationAccuracy? get openAccuracy => _openAccuracy;

  /// Requests a fix feed for [consumer] at [accuracy], re-opening the single
  /// shared handle if this raises the resolved tier.
  ///
  /// Idempotent per consumer: calling it again only changes that consumer's
  /// requested tier. Returns the shared stream.
  Stream<Position> acquire(
    Object consumer, {
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) {
    if (_closed) return const Stream<Position>.empty();
    _consumers[consumer] = accuracy;
    // Open (or lift) the single handle *synchronously*: a consumer that calls
    // `acquire` must be able to observe `isOpen` right away, and the soonest
    // possible registration is the point — deferring it a microtask would leave
    // a window where the app is tracked as "active" with no handle.
    _syncHandle();
    return _positions.stream;
  }

  /// Drops [consumer]'s interest. The handle is cancelled as soon as no
  /// consumer remains — this is the operation that lets the receiver sleep.
  Future<void> release(Object consumer) async {
    if (_consumers.remove(consumer) == null) return;
    // Detach synchronously so no window exists where the app is registered but
    // nobody wants fixes; the returned Future only awaits the platform cancel.
    await _syncHandle();
  }

  /// Cancels the OS subscription outright and forgets every consumer.
  ///
  /// This is the `locationPaused` / `idleStandby` action: it is deliberately
  /// *not* conditional on a grace period, because Android counts the handle's
  /// mere existence as an active client. The next [acquire] re-opens cleanly.
  Future<void> pauseAll() async {
    _consumers.clear();
    final StreamSubscription<Position>? subscription = _subscription;
    // Detach in this turn: `isOpen` must read false the instant the pause is
    // requested, not after the platform cancel resolves.
    _subscription = null;
    _openAccuracy = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await subscription?.cancel();
  }

  /// Releases every handle and closes the broadcast stream. The hub is unusable
  /// afterwards; used from `ref.onDispose`.
  Future<void> dispose() async {
    _closed = true;
    await pauseAll();
    await _positions.close();
  }

  /// Re-opens the handle when the resolved tier changed, or closes it when the
  /// last consumer left. Never opens a second concurrent subscription.
  ///
  /// The teardown and the re-open happen *before* the first `await`, so the
  /// hub's observable state flips in the same turn as the caller's
  /// `acquire`/`release`; only the platform cancel is awaited.
  Future<void> _syncHandle() async {
    if (_closed) return;
    final LocationAccuracy? wanted = _resolveAccuracy();

    if (wanted == null) {
      // Everyone left: drop the handle so no client is registered at all.
      await pauseAll();
      return;
    }
    if (wanted == _openAccuracy && _subscription != null) {
      return;
    }

    // Replace, never stack: cancel the old handle *before* opening the new one,
    // so the app is at most one client on the fused provider at any instant.
    final StreamSubscription<Position>? previous = _subscription;
    _subscription = null;
    _openAccuracy = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _open(wanted);
    await previous?.cancel();
  }

  /// The strongest tier any live consumer has asked for, or `null` when there
  /// are none. Enum order is precision order, so `max` is the strongest.
  LocationAccuracy? _resolveAccuracy() {
    if (_consumers.isEmpty) return null;
    return _consumers.values.reduce(
      (LocationAccuracy a, LocationAccuracy b) =>
          a.index >= b.index ? a : b,
    );
  }

  void _open(LocationAccuracy accuracy) {
    if (_closed) return;
    _openAccuracy = accuracy;
    try {
      _subscription = locations
          .trackingPositionStream(
            settings: LocationService.trackingSettingsFor(accuracy: accuracy),
          )
          .listen(
        (Position position) {
          if (_closed || _positions.isClosed) return;
          _positions.add(position);
        },
        onError: (Object _) {
          // The reconnecting wrapper underneath normally absorbs these; if one
          // escapes, re-open rather than leaving a dead handle behind.
          _scheduleReconnect(accuracy);
        },
        onDone: () => _scheduleReconnect(accuracy),
        cancelOnError: true,
      );
    } catch (_) {
      // Platform channel unavailable (tests / unsupported platform): stay
      // closed rather than pretending a handle exists.
      _subscription = null;
      _openAccuracy = null;
    }
  }

  void _scheduleReconnect(LocationAccuracy accuracy) {
    // The handle is *not* cleared here. The connected platform stream can
    // complete transiently — a provider hiccup, or the fused provider
    // re-registering — while the app still legitimately holds the handle. The
    // durable layer underneath ([LocationService.trackingPositionStream])
    // already reconnects with capped backoff, so tearing our registration down
    // on every `onDone` would flap the OS client. We only re-open if the
    // subscription actually died without being replaced.
    if (reconnectDelay == Duration.zero) return;
    if (_reconnectTimer?.isActive ?? false) return;
    _reconnectTimer = Timer(reconnectDelay, () {
      _reconnectTimer = null;
      if (_closed || _subscription != null) return;
      _open(_resolveAccuracy() ?? accuracy);
    });
  }

  @visibleForTesting
  bool get hasPendingReconnect => _reconnectTimer?.isActive ?? false;
}
