import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/services/location_hub.dart';
import 'package:routenote/src/services/location_service.dart';
import 'package:routenote/src/utils/magnetic_declination.dart';
import 'package:routenote/src/utils/qibla_calculator.dart';

/// Live Qibla compass.
///
/// Fuses the two device sources that a real compass needs:
/// - the **magnetometer heading** (`flutter_compass`), which rotates the dial
///   with the phone, and
/// - the **GPS position stream** (`geolocator`), which fixes where Qibla is.
///
/// So that opening the sheet never shows a blank dial while the receiver powers
/// up, the bearing is first seeded from the OS's **last known position** and
/// then refined by the live stream as fresh fixes arrive.
///
/// The magnetometer reports a **magnetic** heading while the Qibla bearing is
/// measured from **true** north, so the two are reconciled with the local
/// magnetic declination (see [MagneticDeclination]) before the needle is drawn.
///
/// Both sources are optional and every platform call is guarded, so a missing
/// sensor, a denied permission or a transient stream error can never freeze or
/// crash the widget: the bearing is still shown, with a clear status line that
/// explains what is missing.
class QiblaIndicator extends StatefulWidget {
  const QiblaIndicator({
    super.key,
    this.locationService = const LocationService(),
    this.locationHub,
    this.compassEvents,
    this.declination = MagneticDeclination.degreesAt,
  });

  /// Location source. Injectable so tests can drive fixes deterministically
  /// without touching the geolocator platform channels.
  final LocationService locationService;

  /// The app-wide single location client (see [LocationHub]).
  ///
  /// When present the compass shares the one OS subscription with the daily
  /// trackers instead of opening a second `FusedLocationProvider` client, and
  /// releases its registration — not just its listener — when it is disposed.
  /// `null` in standalone embeds and most widget tests, which then fall back to
  /// a private stream.
  final LocationHub? locationHub;

  /// Magnetometer source. Defaults to [FlutterCompass.events]; injectable so
  /// tests can emit headings without the platform event channel.
  final Stream<CompassEvent>? compassEvents;

  /// Resolves the local magnetic declination (east-positive degrees) for a
  /// latitude/longitude, turning the magnetometer's magnetic heading into a
  /// true-north heading. Defaults to the offline WMM-2020 model; injectable so
  /// widget tests never depend on the model's real values.
  final double? Function(double latitude, double longitude) declination;

  @override
  State<QiblaIndicator> createState() => _QiblaIndicatorState();
}

/// Why the GPS half of the compass is (or is not) working.
enum _FixState { calculating, ready, serviceOff, permissionDenied, unavailable }

/// Internal state for [QiblaIndicator].
class _QiblaIndicatorState extends State<QiblaIndicator> {
  /// Below this many degrees of error the needle counts as "on Qibla".
  static const double _alignedTolerance = 5;

  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<Position>? _positionSub;

  /// Whether [_positionSub] is a [LocationHub] registration that must be
  /// *released* on teardown, not merely cancelled — cancelling the listener
  /// alone would leave the app registered as a location client.
  bool _hubSubscriptionHeld = false;

  /// Bumped by every [_startLocation] call and by [dispose], so a slow platform
  /// call that resolves after the widget is gone (or after a newer attempt has
  /// started) can neither touch state nor leave a subscription behind.
  int _locationAttempt = 0;

  /// Device **magnetic** heading in degrees (0 = North), null until the sensor
  /// delivers its first sample.
  double? _heading;

  /// Local magnetic declination in degrees (east-positive) for the current fix,
  /// applied to [_heading] to obtain a true-north heading. Stays 0 until the
  /// first GPS fix, when the compass falls back to the raw magnetic heading.
  double _declination = 0;

  /// Calculated Qibla bearing to Mecca (0°..360°), null until there is a fix.
  double? _qiblaBearing;

  double? _latitude;
  double? _longitude;

  _FixState _fixState = _FixState.calculating;

  @override
  void initState() {
    super.initState();
    _startCompass();
    unawaited(_startLocation());
  }

  @override
  void dispose() {
    // Invalidate any in-flight `_startLocation` await so it can never attach a
    // subscription after we are gone (the "sheet dismissed mid-await" leak),
    // then cancel whatever is live.
    _locationAttempt++;
    _compassSub?.cancel();
    _compassSub = null;
    // A hub registration must be *released*, not just cancelled: cancelling the
    // listener would leave the app registered as a location client and keep the
    // receiver awake. The release is un-awaited (dispose cannot be async) but
    // runs synchronously up to its first await, which is where the bookkeeping
    // happens.
    final bool heldHub = _hubSubscriptionHeld;
    _hubSubscriptionHeld = false;
    final StreamSubscription<Position>? positionSub = _positionSub;
    _positionSub = null;
    if (positionSub != null) {
      unawaited(positionSub.cancel());
    }
    if (heldHub) {
      unawaited(widget.locationHub?.release(this));
    }
    super.dispose();
  }

  // ---------------------------------------------------------------- sensors

  /// Subscribes to the magnetometer. Silently no-ops when the platform has no
  /// compass (for example web or a device without a magnetometer).
  void _startCompass() {
    try {
      final Stream<CompassEvent>? events =
          widget.compassEvents ?? FlutterCompass.events;
      if (events == null) return;
      _compassSub = events.listen(
        (CompassEvent event) {
          final double? heading = event.heading;
          if (!mounted || heading == null || heading.isNaN) return;
          setState(() => _heading = (heading + 360) % 360);
        },
        onError: (Object _) {
          // Sensor hiccup: keep the last heading rather than freezing the UI.
        },
        cancelOnError: false,
      );
    } catch (_) {
      // Platform channel unavailable — the static bearing still works.
    }
  }

  /// Subscribes to the live GPS position stream, checking the service and the
  /// runtime permission first so failures are reported instead of swallowed.
  ///
  /// Every `await` is followed by a `mounted`/attempt guard: the bottom sheet
  /// can be dismissed while a platform call is still in flight, and a
  /// subscription created after disposal would leak for the app's lifetime.
  Future<void> _startLocation() async {
    final int attempt = ++_locationAttempt;
    // Drop any previous registration completely — a hub release included —
    // before starting a new one, so a retry never stacks two OS handles.
    if (_hubSubscriptionHeld) {
      _hubSubscriptionHeld = false;
      unawaited(widget.locationHub?.release(this));
    }
    await _positionSub?.cancel();
    _positionSub = null;
    if (!mounted || attempt != _locationAttempt) return;

    final LocationService locations = widget.locationService;
    try {
      if (!await locations.isServiceEnabled()) {
        if (!mounted || attempt != _locationAttempt) return;
        _setFixState(_FixState.serviceOff);
        return;
      }

      LocationPermission permission = await locations.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await locations.requestPermission();
      }
      if (!mounted || attempt != _locationAttempt) return;
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _setFixState(_FixState.permissionDenied);
        return;
      }

      // Seed from the OS's cached fix first: `getLastKnownPosition` returns
      // immediately (it does not power up the receiver), so the sheet shows a
      // Qibla bearing at once instead of waiting for a fresh live fix. The live
      // stream below then refines it.
      final Position? lastKnown = await _lastKnownPosition();
      if (!mounted || attempt != _locationAttempt) return;
      if (lastKnown != null) {
        _updateQiblaFromPosition(lastKnown);
      }

      // Use the app-wide single location client rather than opening a second
      // OS subscription: two `getPositionStream` handles means two
      // `FusedLocationProvider` clients, which is what makes Android report a
      // background-location drain. The hub shares one handle with the daily
      // trackers and is reference-counted, so closing this sheet releases it.
      final LocationHub? hub = widget.locationHub;
      final StreamSubscription<Position> subscription;
      if (hub != null) {
        subscription = hub
            .acquire(
              this,
              accuracy: LocationAccuracy.high,
              interval: const Duration(seconds: 1),
              distanceFilter: 25,
            )
            .listen(
              _updateQiblaFromPosition,
              onError: (Object _) {
                // A transient stream error keeps the last known fix.
              },
              cancelOnError: false,
            );
        _hubSubscriptionHeld = true;
      } else {
        // No hub wired in (tests, or a standalone embed): fall back to a
        // private stream, still cancelled with the widget.
        subscription = locations
            .trackingPositionStream(
              settings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 25,
              ),
              onError: (Object _, StackTrace _) {
                // Transient failure; the wrapper reconnects, we keep the fix.
              },
            )
            .listen(
              _updateQiblaFromPosition,
              onError: (Object _) {
                // A transient stream error keeps the last known fix.
              },
              cancelOnError: false,
            );
      }

      // The platform calls above may have resolved after disposal, or a newer
      // attempt may have superseded this one: never hold a subscription the
      // state can no longer cancel.
      if (!mounted || attempt != _locationAttempt) {
        if (_hubSubscriptionHeld) {
          _hubSubscriptionHeld = false;
          unawaited(widget.locationHub?.release(this));
        }
        await subscription.cancel();
        return;
      }
      _positionSub = subscription;
    } catch (_) {
      // Platform channel unavailable (tests / unsupported platform).
      if (!mounted || attempt != _locationAttempt) return;
      _setFixState(_FixState.unavailable);
    }
  }

  /// Reads the OS-cached fix, treating an unavailable platform channel (or any
  /// other failure) as "no cached fix" rather than an error: without one we
  /// simply fall straight through to the live stream.
  Future<Position?> _lastKnownPosition() async {
    try {
      return await widget.locationService.lastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  void _setFixState(_FixState state) {
    if (!mounted) return;
    setState(() => _fixState = state);
  }

  void _updateQiblaFromPosition(Position position) {
    final double? bearing =
        QiblaCalculator.bearingFrom(position.latitude, position.longitude);
    if (!mounted) return;
    setState(() {
      _qiblaBearing = bearing;
      _latitude = position.latitude;
      _longitude = position.longitude;
      _declination =
          widget.declination(position.latitude, position.longitude) ?? 0;
      _fixState = bearing == null ? _FixState.unavailable : _FixState.ready;
    });
  }

  /// Manual retry for the GPS half (the magnetometer stream reconnects itself).
  Future<void> _retry() async {
    _setFixState(_FixState.calculating);
    await _startLocation();
  }

  // ------------------------------------------------------------------ maths

  static double _radians(double degrees) => degrees * math.pi / 180;

  static double _normalize(double degrees) {
    final double value = degrees % 360;
    return value < 0 ? value + 360 : value;
  }

  /// Formats a bearing into a 16-point compass abbreviation.
  static String _abbrev(double bearing) {
    const List<String> labels = <String>[
      'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
    ];
    final int index = ((bearing + 11.25) / 22.5).round() % 16;
    return labels[index];
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final double? qibla = _qiblaBearing;
    final double? heading = _heading;
    final bool hasQibla = qibla != null;

    // The magnetometer reports a *magnetic* heading, but the Qibla bearing is
    // measured from *true* north: add the local declination to reconcile them.
    final double? trueHeading =
        heading == null ? null : _normalize(heading + _declination);

    // Angle from the top of the phone to Qibla: without a heading the dial is
    // treated as pointing North so the bearing is still meaningful.
    final double relative =
        hasQibla ? _normalize(qibla - (trueHeading ?? 0)) : 0;
    final bool aligned = hasQibla &&
        trueHeading != null &&
        (relative <= _alignedTolerance ||
            relative >= 360 - _alignedTolerance);

    final String bearingText = hasQibla
        ? '${qibla.round() % 360}° ${_abbrev(qibla)}'
        : l10n.qiblaUnavailable;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 172,
          height: 172,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // Face.
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surfaceContainerHighest,
                  border: Border.all(color: scheme.outline),
                ),
                child: const SizedBox.expand(),
              ),
              // Rotating compass rose (ticks + cardinal letters).
              Transform.rotate(
                angle: _radians(-(trueHeading ?? 0)),
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    CustomPaint(
                      size: const Size.square(172),
                      painter: _CompassRosePainter(
                        tickColor: scheme.outline,
                        northColor: scheme.error,
                      ),
                    ),
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _RoseLabel(
                          text: l10n.compassNorth,
                          color: scheme.error,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _RoseLabel(text: 'E', color: scheme.onSurfaceVariant),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _RoseLabel(text: 'S', color: scheme.onSurfaceVariant),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _RoseLabel(text: 'W', color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
              // Qibla needle.
              if (hasQibla)
                Transform.rotate(
                  angle: _radians(relative),
                  child: Icon(
                    Icons.navigation,
                    size: 72,
                    color: aligned ? scheme.tertiary : scheme.primary,
                  ),
                ),
              // Pivot.
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                ),
                child: const SizedBox(width: 10, height: 10),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: hasQibla ? scheme.secondaryContainer : scheme.surface,
            border: Border.all(
              color: hasQibla ? scheme.secondary : scheme.outline,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            bearingText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: hasQibla
                  ? scheme.onSecondaryContainer
                  : scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          aligned ? l10n.qiblaAligned : l10n.headingInstruction,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: aligned ? scheme.tertiary : scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _statusText(l10n),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        IconButton(
          tooltip: l10n.compassTitle,
          onPressed: _retry,
          icon: const Icon(Icons.refresh, size: 20),
        ),
      ],
    );
  }

  /// Human-readable location status, reusing the shared permission/error copy.
  String _statusText(AppLocalizations l10n) {
    switch (_fixState) {
      case _FixState.ready:
        final double? lat = _latitude;
        final double? lon = _longitude;
        if (lat == null || lon == null) return l10n.compassCalculating;
        return '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';
      case _FixState.serviceOff:
        return l10n.locationServicesDisabled;
      case _FixState.permissionDenied:
        return l10n.locationChipPermissionDenied;
      case _FixState.unavailable:
        return l10n.locationUnavailable;
      case _FixState.calculating:
        return l10n.compassCalculating;
    }
  }
}

/// A single cardinal letter on the rotating compass rose.
class _RoseLabel extends StatelessWidget {
  const _RoseLabel({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Draws the 60 one-degree ticks around the dial, with a longer, coloured tick
/// at North so the dial reads at a glance even before a GPS fix arrives.
class _CompassRosePainter extends CustomPainter {
  const _CompassRosePainter({required this.tickColor, required this.northColor});

  final Color tickColor;
  final Color northColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double outer = size.width / 2;
    final Paint paint = Paint()..strokeCap = StrokeCap.round;
    for (int i = 0; i < 60; i++) {
      final double angle = i * 6 * math.pi / 180;
      final bool isNorth = i == 0;
      final bool isMajor = i % 5 == 0;
      final double inner = outer - (isNorth ? 16 : (isMajor ? 12 : 6));
      final double dx = math.sin(angle);
      final double dy = -math.cos(angle);
      paint
        ..color = isNorth ? northColor : tickColor
        ..strokeWidth = isNorth ? 3 : (isMajor ? 2 : 1);
      canvas.drawLine(
        center + Offset(dx * inner, dy * inner),
        center + Offset(dx * outer, dy * outer),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CompassRosePainter oldDelegate) =>
      oldDelegate.tickColor != tickColor || oldDelegate.northColor != northColor;
}
