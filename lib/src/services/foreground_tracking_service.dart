import 'package:flutter/services.dart';

/// Owns the Android **foreground service** that keeps the daily GPS trackers
/// alive while MapNote is in the background, plus the runtime permissions that
/// service needs.
///
/// Android only delivers location to a backgrounded app through a foreground
/// service, and since Android 10 that service also needs
/// `ACCESS_BACKGROUND_LOCATION`; from Android 13 the notification it posts
/// needs `POST_NOTIFICATIONS`. Both are requested here, from the platform side
/// (see `MainActivity.kt`), so they are only ever requested *after* a tracker
/// actually started — i.e. once foreground location is already granted, which
/// is what Android 11+ requires before it will even show the
/// "Allow all the time" dialog.
///
/// Every call is best-effort: on iOS, on the web and in unit/widget tests the
/// channel has no handler, so the methods resolve as no-ops instead of
/// throwing — and every start/stop is time-bounded (see [invokeTimeout]) so a
/// dead native side cannot stall the caller's serialized queue.
class ForegroundTrackingService {
  ForegroundTrackingService({
    MethodChannel? channel,
    this.invokeTimeout = const Duration(seconds: 20),
  }) : _channel = channel ?? const MethodChannel(channelName);

  /// Must match `TRACKING_CHANNEL` in `MainActivity.kt`.
  static const String channelName = 'com.routenote.routenote/tracking';

  /// Upper bound on any start/stop call. A native side that never replies
  /// (destroyed activity, dropped message) must not stall the serialized
  /// tracker lifecycle queue: the call reports failure, `isRunning` stays
  /// false, and the next sync retries — permission dialogs keep their own,
  /// longer bound (see [_requestPermission]).
  final Duration invokeTimeout;

  final MethodChannel _channel;

  bool _running = false;

  /// Whether the native foreground service has been started and not stopped.
  bool get isRunning => _running;

  /// Brings the native service in line with the trackers: starts it when
  /// [needed] and it is not running, stops it when it is running and no longer
  /// needed. Idempotent, so callers can fire it after every start/stop.
  Future<void> sync({required bool needed}) async {
    if (needed == _running) return;
    if (needed) {
      await requestPermissions();
      final bool started = await _invoke<bool>('startForeground') ?? false;
      _running = started;
      return;
    }
    await _invoke<Object>('stopForeground');
    _running = false;
  }

  /// Asks for `POST_NOTIFICATIONS` (Android 13+) and
  /// `ACCESS_BACKGROUND_LOCATION` (Android 10+) when they are missing.
  ///
  /// Sequential on purpose: from Android 11 the background-location dialog may
  /// not be bundled with any other request.
  Future<void> requestPermissions() async {
    await _requestPermission('requestNotificationPermission');
    await _requestPermission('requestBackgroundLocationPermission');
  }

  /// A permission dialog must never leave Dart awaiting forever (the activity
  /// can be destroyed while it is up), so each request is bounded.
  Future<bool> _requestPermission(String method) async {
    try {
      return await _channel
              .invokeMethod<bool>(method)
              .timeout(const Duration(seconds: 25)) ??
          false;
    } on MissingPluginException {
      // Not Android (or a test): nothing to request.
      return false;
    } catch (_) {
      // Timeout or PlatformException: report "not granted" and carry on.
      return false;
    }
  }

  Future<T?> _invoke<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method).timeout(invokeTimeout);
    } on MissingPluginException {
      // Not Android (or a test): nothing to start or stop.
      return null;
    } catch (_) {
      // Timeout, or PlatformException (e.g. the OS refused a background
      // service start): report "not started" and let the next sync retry.
      return null;
    }
  }
}
