import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'location_service.dart';

/// Which provider tier a [FusedLocationService] session is currently drawing
/// its fixes from.
enum FusedLocationMode {
  /// Best-available accuracy (Android `PRIORITY_HIGH_ACCURACY` fused requests,
  /// iOS best): the GPS receiver is awake.
  highAccuracy,

  /// Low-power fallback (`LocationAccuracy.medium` =
  /// `PRIORITY_BALANCED_POWER_ACCURACY`): Wi-Fi / cell / on-sensor fixes only,
  /// used while the GPS is off or delivers nothing.
  networkFallback,
}

/// Seamless high-precision ⇄ low-power fallback over [LocationService].
///
/// A long-running tracker that demands a continuous GPS lock loses every fix
/// — and therefore every metre — the moment the receiver goes quiet: GPS
/// switched off indoors, no sky view, an OEM throttling the sensor. This
/// service keeps the session alive through those stretches by re-opening the
/// position stream on the **low-power network tier**:
///
/// * no fix within [fallbackAfter] of opening the high-accuracy stream →
///   reopen on the network tier ([FusedLocationMode.networkFallback]);
/// * the OS provider reporting *enabled* again, or the periodic
///   [highAccuracyRetryEvery] probe, promotes the session back to
///   [FusedLocationMode.highAccuracy];
/// * fixes already flowing on either tier keep flowing — a mode switch only
///   happens on silence, so a healthy session never churns.
///
/// Mode switches are silent by design: the delivered stream is continuous, so
/// the track engine sees one unbroken session and its measurement rules
/// (jitter, min-step, speed caps) treat a coarse network fix exactly like any
/// other fix. Errors from the underlying platform stream are reported through
/// `onError` (the engine uses that hook to arm gap recovery) and treated as
/// silence for switching purposes.
///
/// No location data leaves the device here — this only decides *how* the
/// platform is asked for fixes.
class FusedLocationService {
  FusedLocationService({
    required this._locationService,
    this.fallbackAfter = const Duration(seconds: 20),
    this.highAccuracyRetryEvery = const Duration(minutes: 3),
  });

  /// How long the high-accuracy tier may stay silent before the session falls
  /// back to the network tier. Long enough for a normal first fix outdoors,
  /// short enough that a dead receiver is not waited on for a minute.
  final Duration fallbackAfter;

  /// While on the network tier, how often the high-accuracy tier is probed
  /// again (the probe is just another stream reopen — no fix is lost if it
  /// also stays silent, because [fallbackAfter] then falls back again).
  final Duration highAccuracyRetryEvery;

  final LocationService _locationService;

  /// Mode of the most recently opened stream (diagnostics/tests).
  FusedLocationMode get mode => _mode;

  FusedLocationMode _mode = FusedLocationMode.highAccuracy;

  /// Opens a session. [highSettings] is the accuracy profile the tracker
  /// wants when the receiver is healthy; [networkSettings] is the low-power
  /// profile the session falls back to (typically the same tracker profile at
  /// [LocationAccuracy.medium]).
  ///
  /// [serviceStatus] is the OS provider's off/on feed; an *enabled* event is
  /// the strongest possible evidence the GPS is usable again, so it promotes
  /// the session back to the high tier immediately.
  ///
  /// The returned stream is single-subscription (the tracker attaches once)
  /// and cancels every timer and inner subscription on cancellation.
  Stream<Position> track({
    required LocationSettings highSettings,
    required LocationSettings networkSettings,
    void Function(Object error, StackTrace stackTrace)? onError,
    Stream<ServiceStatus>? serviceStatus,
  }) {
    final _FusedSession session = _FusedSession(
      service: this,
      highSettings: highSettings,
      networkSettings: networkSettings,
      onError: onError,
      serviceStatus: serviceStatus,
    );
    late final StreamController<Position> controller;
    controller = StreamController<Position>(
      onListen: () => session.start(controller),
      onCancel: session.cancel,
    );
    return controller.stream;
  }

  /// Opens the stream on [settings], recording the resulting mode.
  Stream<Position> _open(
    LocationSettings settings,
    FusedLocationMode mode,
    void Function(Object error, StackTrace stackTrace)? onError,
  ) {
    _mode = mode;
    return _locationService.trackingPositionStream(
      settings: settings,
      onError: onError,
    );
  }
}

/// One live [FusedLocationService.track] session: its inner subscription, its
/// fallback / retry timers and its teardown. Exists so timer bookkeeping never
/// leaks into the service itself.
class _FusedSession {
  _FusedSession({
    required this.service,
    required this.highSettings,
    required this.networkSettings,
    required this.onError,
    required this.serviceStatus,
  });

  final FusedLocationService service;
  final LocationSettings highSettings;
  final LocationSettings networkSettings;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final Stream<ServiceStatus>? serviceStatus;

  StreamController<Position>? _controller;
  StreamSubscription<Position>? _inner;
  StreamSubscription<ServiceStatus>? _statusSubscription;
  Timer? _fallbackTimer;
  Timer? _retryTimer;
  bool _onNetwork = false;
  bool _cancelled = false;

  void start(StreamController<Position> controller) {
    _controller = controller;
    _openHigh();
    final Stream<ServiceStatus>? status = serviceStatus;
    if (status != null) {
      _statusSubscription = status.listen(_onStatus);
    }
  }

  void _onStatus(ServiceStatus status) {
    if (_cancelled) return;
    // GPS switched back on: the strongest possible "try the high tier" signal.
    if (status == ServiceStatus.enabled && _onNetwork) {
      _openHigh();
    }
  }

  void _openHigh() {
    _onNetwork = false;
    _open(highSettings, FusedLocationMode.highAccuracy);
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer(service.fallbackAfter, _openNetwork);
  }

  void _openNetwork() {
    if (_cancelled) return;
    _onNetwork = true;
    _open(networkSettings, FusedLocationMode.networkFallback);
    // Never stay on the fallback forever: probe the high tier again so a
    // receiver that merely needed time to acquire is retried.
    _retryTimer?.cancel();
    _retryTimer = Timer(service.highAccuracyRetryEvery, _openHigh);
  }

  void _open(LocationSettings settings, FusedLocationMode mode) {
    final StreamController<Position>? controller = _controller;
    if (controller == null || controller.isClosed) return;
    unawaited(_inner?.cancel());
    _inner = service._open(settings, mode, onError).listen(
      (Position position) {
        if (_cancelled || controller.isClosed) return;
        controller.add(position);
      },
      onError: (Object error, StackTrace stackTrace) {
        // The reconnecting wrapper normally swallows these; if one escapes,
        // surface it (the engine arms gap recovery) and treat the tier as
        // silent so the fallback timer can act.
        if (_cancelled || controller.isClosed) return;
        controller.addError(error, stackTrace);
      },
    );
  }

  Future<void> cancel() async {
    _cancelled = true;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    final StreamSubscription<Position>? inner = _inner;
    _inner = null;
    await inner?.cancel();
    final StreamSubscription<ServiceStatus>? statusSubscription =
        _statusSubscription;
    _statusSubscription = null;
    await statusSubscription?.cancel();
  }
}
