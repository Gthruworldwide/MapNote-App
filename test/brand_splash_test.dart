import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/core/brand/brand_lockup.dart';
import 'package:routenote/src/features/splash/brand_splash.dart';

/// The splash wrapper as [MaterialApp] mounts it, optionally forcing Reduce
/// Motion (the nearest [MediaQuery] wins, so overriding here reaches the splash).
Widget _app({bool reduceMotion = false, Widget? home}) {
  return MaterialApp(
    builder: (BuildContext context, Widget? child) {
      final Widget splash = BrandSplash(child: child ?? const SizedBox.shrink());
      if (!reduceMotion) {
        return splash;
      }
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: splash,
      );
    },
    home: home ?? const Scaffold(body: Center(child: Text('home'))),
  );
}

/// The innermost [Opacity] wrapping [part].
double _opacityOf(WidgetTester tester, Type part) {
  return tester
      .widget<Opacity>(
        find.ancestor(of: find.byType(part), matching: find.byType(Opacity)).first,
      )
      .opacity;
}

/// The innermost [Transform] wrapping [part].
Matrix4 _transformOf(WidgetTester tester, Type part) {
  return tester
      .widget<Transform>(
        find.ancestor(of: find.byType(part), matching: find.byType(Transform)).first,
      )
      .transform;
}

/// The x-axis scale of the innermost [Transform] wrapping [part].
///
/// `Transform.scale` builds a `diagonal3Values(s, s, 1)` matrix, so
/// `getMaxScaleOnAxis()` would always report the untouched z axis.
double _scaleOf(WidgetTester tester, Type part) =>
    _transformOf(tester, part).entry(0, 0);

void main() {
  testWidgets('covers the app, then fades away leaving it live', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app());

    // The lockup is up, but the app underneath is already built and live.
    expect(find.byType(BrandLockup), findsOneWidget);
    expect(find.text('home'), findsOneWidget);

    await tester.pumpAndSettle();

    // Fully faded: the overlay is gone and the app is untouched.
    expect(find.byType(BrandLockup), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('the entrance follows the reference timeline', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app());

    // 0.00 s: the mark is invisible and 88% scale, the wordmark hidden six
    // logical pixels below its final resting place.
    expect(_opacityOf(tester, BrandMark), 0);
    expect(_scaleOf(tester, BrandMark), 0.88);
    expect(_opacityOf(tester, BrandWordmark), 0);
    expect(_transformOf(tester, BrandWordmark).getTranslation().y, 6);

    // 0.50 s: the mark has finished fading in, but is still scaling up.
    await tester.pump(const Duration(milliseconds: 500));
    expect(_opacityOf(tester, BrandMark), 1);
    expect(_scaleOf(tester, BrandMark), lessThan(1));

    // 0.60 s: the mark has reached full size, the wordmark is still on its way.
    await tester.pump(const Duration(milliseconds: 100));
    expect(_scaleOf(tester, BrandMark), 1);
    expect(_opacityOf(tester, BrandWordmark), lessThan(1));

    // 0.85 s: the wordmark has settled at full opacity and offset zero.
    await tester.pump(const Duration(milliseconds: 250));
    expect(_opacityOf(tester, BrandWordmark), 1);
    expect(_transformOf(tester, BrandWordmark).getTranslation().y, 0);
  });

  testWidgets('shows the finished lockup straight away under Reduce Motion', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(reduceMotion: true));

    // No fade, no scale, no rise: the final lockup, immediately.
    expect(_opacityOf(tester, BrandMark), 1);
    expect(_scaleOf(tester, BrandMark), 1);
    expect(_opacityOf(tester, BrandWordmark), 1);
    expect(_transformOf(tester, BrandWordmark).getTranslation().y, 0);

    await tester.pumpAndSettle();
    expect(find.byType(BrandLockup), findsNothing);
  });

  testWidgets('never rebuilds the app underneath when the splash ends', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app());

    final Element before = tester.element(find.text('home'));
    await tester.pumpAndSettle();

    // Same element: the overlay leaving the tree cannot have re-parented (and so
    // re-created) the navigator, which would drop the open route's state.
    expect(identical(tester.element(find.text('home')), before), isTrue);
  });
}
