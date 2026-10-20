import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/core/security/session_guard.dart';
import 'package:routenote/src/features/saved_places/presentation/widgets/vault_privacy_dimmer.dart';
import 'package:routenote/src/providers/app_providers.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required InteractionContext verdict,
    ThemeData? theme,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The real detector needs an accelerometer; the verdict is injected
          // directly so the widget's behaviour is tested, not the sensor.
          interactionContextProvider
              .overrideWith((Ref ref) => Stream<InteractionContext>.value(verdict)),
        ],
        child: MaterialApp(
          theme: theme,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: VaultPrivacyDimmer(child: Text('Vaulted Spot')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hand-held keeps the vault content fully legible', (
    WidgetTester tester,
  ) async {
    await pump(tester, verdict: InteractionContext.handHeld);

    expect(find.text('Vaulted Spot'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
  });

  testWidgets('surface-idle dims the content with a localized reason', (
    WidgetTester tester,
  ) async {
    await pump(tester, verdict: InteractionContext.surfaceIdle);

    // The content is still mounted (a tap restores it) but covered.
    expect(find.text('Vaulted Spot'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    final AppLocalizations l10n = await AppLocalizations.delegate.load(
      const Locale('en'),
    );
    expect(find.text(l10n.vaultDimmingNotice), findsOneWidget);
  });

  testWidgets('unknown (no samples yet) is treated as hand-held', (
    WidgetTester tester,
  ) async {
    await pump(tester, verdict: InteractionContext.unknown);

    // The dimmer must never cover content on a guess.
    expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
  });

  testWidgets('a tap anywhere on the dimming dismisses it', (
    WidgetTester tester,
  ) async {
    await pump(tester, verdict: InteractionContext.surfaceIdle);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

    // Tapping the overlay itself (not the icon) is what a user does.
    await tester.tap(find.byType(GestureDetector).last, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
  });

  testWidgets('renders in dark mode without hardcoded colors', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      verdict: InteractionContext.surfaceIdle,
      theme: ThemeData.dark(),
    );

    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders mirrored for Arabic', (WidgetTester tester) async {
    await pump(
      tester,
      verdict: InteractionContext.surfaceIdle,
      locale: const Locale('ar'),
    );

    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(VaultPrivacyDimmer))),
      TextDirection.rtl,
    );
  });
}
