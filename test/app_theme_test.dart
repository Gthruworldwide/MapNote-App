import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routenote/src/core/theme/app_motion.dart';
import 'package:routenote/src/core/theme/app_theme.dart';

/// WCAG 2.1 relative luminance for a single sRGB channel.
double _linear(double channel) {
  final double c = channel;
  return c <= 0.03928
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// WCAG contrast ratio between two opaque colours (1:1 … 21:1).
double _contrast(Color a, Color b) {
  final double la =
      0.2126 * _linear(a.r) + 0.7152 * _linear(a.g) + 0.0722 * _linear(a.b);
  final double lb =
      0.2126 * _linear(b.r) + 0.7152 * _linear(b.g) + 0.0722 * _linear(b.b);
  final double hi = math.max(la, lb);
  final double lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // The bundled-font test below reads from rootBundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MapNote design system — light theme', () {
    final ThemeData theme = AppTheme.light();

    test('uses the pure-white background and off-white surface', () {
      expect(theme.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
      expect(theme.cardColor, const Color(0xFFF9F9FB));
      expect(theme.colorScheme.surface, const Color(0xFFF9F9FB));
      expect(theme.brightness, Brightness.light);
    });

    test('exposes the brand accents and text tokens', () {
      expect(theme.colorScheme.primary, const Color(0xFF145CFF));
      // Cyan is AMOLED-only: light mode resolves every accent to Electric Blue.
      expect(theme.colorScheme.secondary, const Color(0xFF145CFF));
      expect(theme.colorScheme.tertiary, const Color(0xFF145CFF));
      expect(theme.colorScheme.onSurface, const Color(0xFF0A0A0A));
      expect(theme.colorScheme.onSurfaceVariant, const Color(0xFF4A4A4A));
    });

    test('cards are 20px, flat, with a subtle electric-blue border', () {
      final RoundedRectangleBorder shape =
          theme.cardTheme.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(AppRadii.card));
      expect(theme.cardTheme.elevation, 0);
      expect((shape.side.color), AppColors.lightBorder);
      expect(shape.side.width, 1);
    });

    test('inputs are 16px with an electric-blue focus ring', () {
      final OutlineInputBorder focused =
          theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder;
      expect(focused.borderRadius, BorderRadius.circular(AppRadii.input));
      expect(focused.borderSide.color, const Color(0xFF145CFF));
      expect(focused.borderSide.width, 1.6);
    });

    test('primary buttons are pills', () {
      final OutlinedBorder shape = theme.filledButtonTheme.style!.shape!
          .resolve(<WidgetState>{})!;
      expect(shape, isA<StadiumBorder>());
    });
  });

  group('MapNote design system — AMOLED dark theme', () {
    final ThemeData theme = AppTheme.dark();

    test('draws on pure black with a deep-dark surface', () {
      expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
      expect(theme.cardColor, const Color(0xFF0A0A0A));
      expect(theme.colorScheme.surface, const Color(0xFF0A0A0A));
      expect(theme.brightness, Brightness.dark);
    });

    test('uses white primary text and the muted grey token', () {
      expect(theme.colorScheme.onSurface, const Color(0xFFFFFFFF));
      expect(theme.colorScheme.onSurfaceVariant, const Color(0xFF8E8E93));
    });

    test('cards carry a subtle cyan border', () {
      final RoundedRectangleBorder shape =
          theme.cardTheme.shape! as RoundedRectangleBorder;
      expect(shape.side.color, AppColors.darkBorder);
    });
  });

  group('MapNote design system — typography & motion', () {
    test('applies Manrope across heading and body styles', () {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.light(),
        AppTheme.dark(),
      ]) {
        expect(theme.textTheme.headlineMedium?.fontFamily, 'Manrope');
        expect(theme.textTheme.bodyLarge?.fontFamily, 'Manrope');
        expect(theme.textTheme.labelLarge?.fontFamily, 'Manrope');
        // No secondary/fallback family: Manrope is the only face, resolved
        // from the local asset bundle.
        expect(theme.textTheme.bodyLarge?.fontFamilyFallback, isNull);
      }
    });

    test(
      'bundles every Manrope weight locally (no runtime fetching)',
      () async {
        const List<String> weights = <String>[
          'ExtraLight',
          'Light',
          'Regular',
          'Medium',
          'SemiBold',
          'Bold',
          'ExtraBold',
        ];
        for (final String weight in weights) {
          final ByteData bytes = await rootBundle.load(
            'assets/fonts/Manrope-$weight.ttf',
          );
          expect(
            bytes.lengthInBytes,
            greaterThan(1000),
            reason: 'assets/fonts/Manrope-$weight.ttf should be bundled',
          );
        }
      },
    );

    test('headlines are bold with tight tracking', () {
      final TextStyle headline = AppTheme.light().textTheme.headlineMedium!;
      expect(headline.fontWeight, FontWeight.w700);
      expect(headline.letterSpacing, -0.5);
    });

    test('routes every platform through the ease-out transition', () {
      final PageTransitionsTheme transitions =
          AppTheme.light().pageTransitionsTheme;
      for (final TargetPlatform platform in TargetPlatform.values) {
        expect(
          transitions.builders[platform],
          isA<MapNotePageTransitionsBuilder>(),
        );
      }
    });
  });

  group('MapNote design system — WCAG contrast & accent policy', () {
    test('light mode text meets WCAG AA/AAA on every surface', () {
      final ThemeData theme = AppTheme.light();
      final Color surface = theme.cardColor;
      final Color background = theme.scaffoldBackgroundColor;

      expect(
        _contrast(theme.colorScheme.onSurface, background),
        greaterThanOrEqualTo(AppColors.minTextContrast),
      );
      expect(
        _contrast(theme.colorScheme.onSurface, surface),
        greaterThanOrEqualTo(AppColors.minTextContrast),
      );
      expect(
        _contrast(theme.colorScheme.onSurfaceVariant, background),
        greaterThanOrEqualTo(AppColors.minTextContrast),
      );
      expect(
        _contrast(theme.colorScheme.onSurfaceVariant, surface),
        greaterThanOrEqualTo(AppColors.minTextContrast),
      );
    });

    test('AMOLED text meets WCAG AA/AAA on black', () {
      final ThemeData theme = AppTheme.dark();
      for (final Color surface in <Color>[
        theme.scaffoldBackgroundColor,
        theme.cardColor,
      ]) {
        expect(
          _contrast(theme.colorScheme.onSurface, surface),
          greaterThanOrEqualTo(AppColors.minTextContrast),
        );
        expect(
          _contrast(theme.colorScheme.onSurfaceVariant, surface),
          greaterThanOrEqualTo(AppColors.minTextContrast),
        );
      }
    });

    test('cyan is reserved for the AMOLED palette', () {
      // Cyan must never leak into the light scheme.
      expect(
        AppTheme.light().colorScheme.secondary,
        isNot(AppColors.secondaryCyan),
      );
      expect(
        AppTheme.light().colorScheme.tertiary,
        isNot(AppColors.secondaryCyan),
      );
      // …and is the accent of choice in dark mode.
      expect(AppTheme.dark().colorScheme.secondary, AppColors.secondaryCyan);
    });

    test('light cards and inputs use 10–15% electric blue, never cyan', () {
      final Color border = AppColors.lightBorder;
      expect(border.r, AppColors.primaryBlue.r);
      expect(border.g, AppColors.primaryBlue.g);
      expect(border.b, AppColors.primaryBlue.b);
      expect(border.a, inInclusiveRange(0.10, 0.15));

      final ThemeData theme = AppTheme.light();
      final OutlineInputBorder enabled =
          theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
      expect(enabled.borderSide.color, AppColors.lightBorder);
    });

    test('the dark card border is cyan, the light one is blue', () {
      RoundedRectangleBorder shapeOf(ThemeData theme) =>
          theme.cardTheme.shape! as RoundedRectangleBorder;

      expect(shapeOf(AppTheme.light()).side.color, AppColors.lightBorder);
      expect(shapeOf(AppTheme.dark()).side.color, AppColors.darkBorder);
    });

    test('primary pill borders follow the accent policy (blue / cyan)', () {
      Color borderOf(ThemeData theme) => theme.filledButtonTheme.style!.shape!
          .resolve(<WidgetState>{})!
          .side
          .color;

      final Color light = borderOf(AppTheme.light());
      expect(light.r, AppColors.primaryBlue.r);
      expect(light.b, AppColors.primaryBlue.b);

      final Color dark = borderOf(AppTheme.dark());
      expect(dark, AppColors.secondaryCyan.withValues(alpha: 0.30));
    });
  });
}
