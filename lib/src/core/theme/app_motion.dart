import 'package:flutter/material.dart';

/// Shared motion language for the MapNote design system.
///
/// Every screen transition, bottom sheet and list reveal uses the same short,
/// decelerating [Curves.easeOut] motion so the whole app feels consistent.
class AppMotion {
  const AppMotion._();

  /// Micro-interactions such as ink/press feedback.
  static const Duration quick = Duration(milliseconds: 150);

  /// The default duration for sheets, dialogs and list reveals.
  static const Duration standard = Duration(milliseconds: 250);

  /// Slower, deliberate transitions.
  static const Duration slow = Duration(milliseconds: 400);

  /// The house curve — used for page turns, sheets and reaches.
  static const Curve curve = Curves.easeOut;

  /// How far (logical pixels) a sheet or list row travels while fading in.
  static const double rise = 12;

  /// Whether the OS "Reduce Motion" accessibility setting is on.
  ///
  /// When it is, we skip slides/rises entirely and snap to the end state so
  /// vestibular-sensitive users get immediate, motion-free transitions.
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// The bottom-sheet [AnimationStyle] for the current context.
  ///
  /// Zeroes the duration when reduce-motion is enabled so the sheet appears
  /// instantly instead of sliding up.
  static AnimationStyle sheetAnimationStyle(BuildContext context) {
    if (reduceMotion(context)) {
      return const AnimationStyle(
        duration: Duration.zero,
        curve: Curves.linear,
        reverseDuration: Duration.zero,
        reverseCurve: Curves.linear,
      );
    }
    return const AnimationStyle(
      duration: standard,
      curve: curve,
      reverseDuration: quick,
      reverseCurve: Curves.easeIn,
    );
  }
}

/// Apple-style page transition: a gentle fade paired with a small upward slide.
///
/// Replaces the platform default so navigation feels identical on every device.
class MapNotePageTransitionsBuilder extends PageTransitionsBuilder {
  const MapNotePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Respect the OS "Reduce Motion" setting: no fade, no slide — just the
    // destination screen.
    if (AppMotion.reduceMotion(context)) return child;

    final Animation<double> curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.curve,
      reverseCurve: Curves.easeIn,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.015),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// Fades its child in while sliding it up by [AppMotion.rise] once on mount.
///
/// Used for bottom-sheet content so sheets settle into place instead of simply
/// appearing. Animation is driven from the first frame — no timers involved.
class SheetEntrance extends StatefulWidget {
  const SheetEntrance({super.key, required this.child});

  final Widget child;

  @override
  State<SheetEntrance> createState() => _SheetEntranceState();
}

class _SheetEntranceState extends State<SheetEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.standard,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery (and therefore reduce-motion) is only available here, not in
    // initState. With Reduce Motion on we snap straight to the settled state.
    if (AppMotion.reduceMotion(context)) {
      _controller.value = 1;
    } else if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduceMotion(context)) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double t = AppMotion.curve.transform(_controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * AppMotion.rise),
            child: child,
          ),
        );
      },
    );
  }
}

/// Staggered fade + rise reveal for list rows.
///
/// Rows animate on mount, with later [index]es starting further into the shared
/// timeline via an [Interval] curve. Passing [index] `0` (or a [TickerMode]
/// that is disabled) yields an instant, fully-visible row, so this never hides
/// content from accessibility or from `find.*` in tests.
class StaggeredReveal extends StatefulWidget {
  const StaggeredReveal({
    super.key,
    required this.index,
    required this.child,
    this.maxStagger = 8,
  });

  /// Position of the row; drives the delay within the shared timeline.
  final int index;

  /// Number of rows that participate in the stagger before it caps out.
  final int maxStagger;

  final Widget child;

  @override
  State<StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<StaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.standard,
  );

  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: _intervalFor(widget.index),
  );

  Interval _intervalFor(int index) {
    final int clamped = index.clamp(0, widget.maxStagger);
    final double start = widget.maxStagger == 0
        ? 0
        : (clamped / widget.maxStagger) * 0.5;
    return Interval(
      start,
      (start + 0.5).clamp(0.0, 1.0),
      curve: AppMotion.curve,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // With Reduce Motion on, jump to the fully-visible frame immediately.
    if (AppMotion.reduceMotion(context)) {
      _controller.value = 1;
    } else if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduceMotion(context)) return widget.child;

    return AnimatedBuilder(
      animation: _animation,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double t = _animation.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * AppMotion.rise),
            child: child,
          ),
        );
      },
    );
  }
}
