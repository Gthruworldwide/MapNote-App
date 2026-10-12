import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/core/brand/brand_logo.dart';
import 'package:routenote/src/features/splash/brand_splash.dart';

void main() {
  testWidgets('BrandSplash covers the app, then fades away leaving it live', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            BrandSplash(child: child ?? const SizedBox.shrink()),
        home: const Scaffold(body: Center(child: Text('home'))),
      ),
    );

    // The lockup is up, but the app underneath is already built and live.
    expect(find.byType(BrandLogo), findsOneWidget);
    expect(find.text('home'), findsOneWidget);

    await tester.pumpAndSettle();

    // Fully faded: the overlay is gone and the app is untouched.
    expect(find.byType(BrandLogo), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });
}
