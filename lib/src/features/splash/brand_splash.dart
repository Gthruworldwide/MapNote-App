import 'package:flutter/material.dart';

import '../../core/brand/brand_assets.dart';
import '../../core/brand/brand_logo.dart';

/// Holds the RouteNote lockup over the app on cold start, then cross-fades to
/// the app itself.
///
/// Mounted from [MaterialApp.builder], so it sits *above* the navigator: the
/// home route (and any share-intent or shortcut navigation) is live from the
/// first frame, and the splash never has to be popped or replaced.
class BrandSplash extends StatefulWidget {
  const BrandSplash({super.key, required this.child});

  /// The app (in practice the navigator) handed back once the fade completes.
  final Widget child;

  /// How long the lockup is held fully opaque before the fade starts.
  static const Duration hold = Duration(milliseconds: 700);

  /// Length of the cross-fade to the app.
  static const Duration fade = Duration(milliseconds: 300);

  /// Rendered logo width, in logical pixels. The lockup artboard carries
  /// padding, so the visible mark lands near 75% of this.
  static const double logoWidth = 200;

  @override
  State<BrandSplash> createState() => _BrandSplashState();
}

class _BrandSplashState extends State<BrandSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: BrandSplash.hold + BrandSplash.fade,
  );

  late final Animation<double> _opacity = TweenSequence<double>(
    <TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: ConstantTween<double>(1),
        weight: BrandSplash.hold.inMilliseconds.toDouble(),
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 0),
        weight: BrandSplash.fade.inMilliseconds.toDouble(),
      ),
    ],
  ).animate(_controller);

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (BuildContext context, Widget? child) {
        final double opacity = _opacity.value;
        if (opacity <= 0) {
          // Fully faded: drop the overlay so nothing is left on top of the app.
          return widget.child;
        }
        return Stack(
          children: <Widget>[
            widget.child,
            Positioned.fill(
              child: Opacity(opacity: opacity, child: const _SplashCover()),
            ),
          ],
        );
      },
    );
  }
}

/// The opaque splash surface: the brand surface colour plus the lockup.
class _SplashCover extends StatelessWidget {
  const _SplashCover();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: BrandLogo(
          BrandAssets.lockupVertical,
          width: BrandSplash.logoWidth,
        ),
      ),
    );
  }
}
