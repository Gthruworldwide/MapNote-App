import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/core/theme/app_motion.dart';
import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/features/home/widgets/place_card.dart';

/// Accessibility guardrails for the MapNote design system: dynamic-type
/// overflow safety and the OS "Reduce Motion" behaviour.
void main() {
  Place place() => Place(
    id: 'place-1',
    name: 'A deliberately long location name that must never overflow',
    notes: 'A long note that also needs to truncate gracefully at 200%.',
    latitude: 30.0444,
    longitude: 31.2357,
    timestamp: DateTime(2026, 1, 1),
  );

  Widget cardHost({required TextScaler textScaler}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: Scaffold(
        body: PlaceCard(place: place(), onTap: () {}, onNavigate: () {}),
      ),
    ),
  );

  group('dynamic type & overflow safety', () {
    testWidgets('PlaceCard does not overflow at 200% text scale', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        cardHost(textScaler: const TextScaler.linear(2.0)),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('PlaceCard does not overflow at 300% text scale', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        cardHost(textScaler: const TextScaler.linear(3.0)),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('reduce motion', () {
    Widget withMedia({
      required bool disableAnimations,
      required Widget child,
    }) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: child,
      ),
    );

    testWidgets('bottom sheets appear instantly when reduce-motion is on', (
      WidgetTester tester,
    ) async {
      late AnimationStyle style;
      await tester.pumpWidget(
        withMedia(
          disableAnimations: true,
          child: Builder(
            builder: (BuildContext context) {
              style = AppMotion.sheetAnimationStyle(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(style.duration, Duration.zero);
      expect(style.reverseDuration, Duration.zero);
    });

    testWidgets('bottom sheets keep the house motion by default', (
      WidgetTester tester,
    ) async {
      late AnimationStyle style;
      await tester.pumpWidget(
        withMedia(
          disableAnimations: false,
          child: Builder(
            builder: (BuildContext context) {
              style = AppMotion.sheetAnimationStyle(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(style.duration, AppMotion.standard);
      expect(style.curve, AppMotion.curve);
    });

    testWidgets('SheetEntrance drops its fade/rise when reduce-motion is on', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        withMedia(
          disableAnimations: true,
          child: const Scaffold(body: SheetEntrance(child: Text('sheet body'))),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(SheetEntrance),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      expect(find.text('sheet body'), findsOneWidget);
    });

    testWidgets('StaggeredReveal is fully visible when reduce-motion is on', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        withMedia(
          disableAnimations: true,
          child: const Scaffold(
            body: StaggeredReveal(index: 3, child: Text('row')),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(StaggeredReveal),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      expect(find.text('row'), findsOneWidget);
    });

    testWidgets('page turns are bypassed when reduce-motion is on', (
      WidgetTester tester,
    ) async {
      late Widget built;
      await tester.pumpWidget(
        withMedia(
          disableAnimations: true,
          child: Builder(
            builder: (BuildContext context) {
              built = const MapNotePageTransitionsBuilder()
                  .buildTransitions<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const SizedBox.shrink(),
                    ),
                    context,
                    const AlwaysStoppedAnimation<double>(1),
                    const AlwaysStoppedAnimation<double>(0),
                    const Text('page'),
                  );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // No FadeTransition/SlideTransition wrapper: the destination paints
      // immediately.
      expect(built, isA<Text>());
    });
  });
}
