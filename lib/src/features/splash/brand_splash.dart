import 'package:flutter/material.dart';

import '../../core/brand/brand_lockup.dart';

/// Plays the approved RouteNote entrance animation over the app on cold start,
/// then cross-fades to it.
///
/// Mounted from [MaterialApp.builder], so it sits *above* the navigator: the
/// home route (and any share-intent or shortcut navigation) is live from the
/// first frame, and the splash never has to be popped or replaced. It is built
/// once with the app and kept for the app's lifetime, so navigating, or leaving
/// and returning from the background, never replays it.
///
/// Startup contract: `main()` finishes Firebase/storage initialization before
/// `runApp`, so the app is ready by the time the first frame paints (the OS
/// launch screen - now a plain brand-coloured background - covers that window).
/// The splash therefore continues as soon as its entrance has played: it adds no
/// fixed delay, and a slower initialization would simply hold the finished
/// lockup on screen, with the app's own loading/error handling live underneath.
class BrandSplash extends StatefulWidget {
  const BrandSplash({super.key, required this.child});

  /// The app (in practice the navigator) handed back once the entrance is done.
  final Widget child;

  /// Length of the entrance, from the motion reference
  /// (`RouteNote / Motion / Horizontal / 2s`).
  ///
  /// The reference file runs for 2.0 s, but its last 1.15 s is the final hold -
  /// the stretch where the finished lockup is simply held. The entrance itself
  /// ends when the wordmark settles, at 0.85 s.
  static const Duration entrance = Duration(milliseconds: 850);

  /// The mark fades in over 0.00 s .. 0.50 s ...
  static const Duration markFadeEnd = Duration(milliseconds: 500);

  /// ... and scales up over 0.00 s .. 0.60 s, its centre fixed.
  static const Duration markScaleEnd = Duration(milliseconds: 600);
  static const double markScaleBegin = 0.88;

  /// The wordmark starts at 0.28 s and settles at 0.85 s, fading in as it rises
  /// by [wordmarkRise] logical pixels.
  static const Duration wordmarkBegin = Duration(milliseconds: 280);
  static const double wordmarkRise = 6;

  /// Cross-fade to the app once the entrance has played.
  static const Duration exitFade = Duration(milliseconds: 250);

  /// The lockup is asked for [widthFraction] of the screen width, bounded by
  /// [minLockupWidth] and [maxLockupWidth]; a screen too narrow for even the
  /// minimum scales the whole lockup down together rather than clipping it.
  static const double widthFraction = 0.7;
  static const double minLockupWidth = 200;
  static const double maxLockupWidth = 300;

  /// Guard band around the lockup, inside the safe area.
  static const double padding = 24;

  @override
  State<BrandSplash> createState() => _BrandSplashState();
}

class _BrandSplashState extends State<BrandSplash>
    with TickerProviderStateMixin {
  /// The design's easing, `cubic-bezier(0, 0, 0.58, 1)`: ease-out, no overshoot.
  static const Curve _easing = Curves.easeOut;

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: BrandSplash.entrance,
  );
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: BrandSplash.exitFade,
  );

  late final Animation<double> _markOpacity = Tween<double>(begin: 0, end: 1)
      .animate(
        CurvedAnimation(
          parent: _entrance,
          curve: Interval(0, _at(BrandSplash.markFadeEnd), curve: _easing),
        ),
      );

  late final Animation<double> _markScale =
      Tween<double>(begin: BrandSplash.markScaleBegin, end: 1).animate(
        CurvedAnimation(
          parent: _entrance,
          curve: Interval(0, _at(BrandSplash.markScaleEnd), curve: _easing),
        ),
      );

  late final Animation<double> _wordmarkProgress = CurvedAnimation(
    parent: _entrance,
    curve: Interval(_at(BrandSplash.wordmarkBegin), 1, curve: _easing),
  );

  bool _dismissed = false;

  /// [moment] as a fraction of the entrance timeline, for the [Interval]s above.
  static double _at(Duration moment) =>
      moment.inMicroseconds / BrandSplash.entrance.inMicroseconds;

  @override
  void initState() {
    super.initState();
    _entrance.addStatusListener(_handleEntranceStatus);
    _exit.addStatusListener(_handleExitStatus);
    _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _exit.dispose();
    super.dispose();
  }

  void _handleEntranceStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _exit.forward();
    }
  }

  void _handleExitStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted && !_dismissed) {
      setState(() => _dismissed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_entrance, _exit]),
      builder: (BuildContext context, Widget? child) {
        // The app keeps slot 0 whether or not the overlay is up, so finishing
        // the splash never re-parents the navigator underneath (which would
        // rebuild it and drop whatever route was open).
        return Stack(
          children: <Widget>[
            widget.child,
            if (!_dismissed)
              Positioned.fill(
                child: Opacity(
                  opacity: 1 - _exit.value,
                  child: _SplashCover(
                    markOpacity: _markOpacity.value,
                    markScale: _markScale.value,
                    wordmarkProgress: _wordmarkProgress.value,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The opaque splash surface: the brand background plus the lockup, with the
/// two halves at the positions the entrance timeline gives them.
class _SplashCover extends StatelessWidget {
  const _SplashCover({
    required this.markOpacity,
    required this.markScale,
    required this.wordmarkProgress,
  });

  /// The mark's opacity, 0 -> 1.
  final double markOpacity;

  /// The mark's scale about its own centre, 0.88 -> 1.
  final double markScale;

  /// The wordmark's progress, 0 -> 1, over its 0.28 s .. 0.85 s window.
  final double wordmarkProgress;

  @override
  Widget build(BuildContext context) {
    // Light brand background is pure white, dark is pure AMOLED black. The
    // resolved theme already folds in the app's light/dark preference, so the
    // splash matches the app from its very first frame with no flash.
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    // Reduce Motion: show the finished lockup immediately. The timeline still
    // runs, as a plain timer, so the splash keeps its shape on screen.
    final bool still = MediaQuery.disableAnimationsOf(context);
    final double markAlpha = still ? 1 : markOpacity;
    final double markScaleValue = still ? 1 : markScale;
    final double wordmark = still ? 1 : wordmarkProgress;

    final double lockupWidth =
        (MediaQuery.sizeOf(context).width * BrandSplash.widthFraction)
            .clamp(BrandSplash.minLockupWidth, BrandSplash.maxLockupWidth)
            .toDouble();

    return ColoredBox(
      color: dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(BrandSplash.padding),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: BrandLockup(
                width: lockupWidth,
                // The wrapper hands back the mark already sized, so scaling it
                // here cannot shift the wordmark beside it.
                markWrapper: (Widget child) => Transform.scale(
                  scale: markScaleValue,
                  child: Opacity(opacity: markAlpha, child: child),
                ),
                wordmarkWrapper: (Widget child) => Transform.translate(
                  offset: Offset(
                    0,
                    BrandSplash.wordmarkRise * (1 - wordmark),
                  ),
                  child: Opacity(opacity: wordmark, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
