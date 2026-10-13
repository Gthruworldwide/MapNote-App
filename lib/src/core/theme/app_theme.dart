import 'package:flutter/material.dart';

import 'app_motion.dart';

/// The MapNote colour tokens.
///
/// Every colour used across the app resolves back to one of these values (via
/// the [ThemeData] built by [AppTheme]) so the light and AMOLED dark palettes
/// stay in lock-step.
class AppColors {
  const AppColors._();

  // --- Brand accents -------------------------------------------------------
  /// Primary accent — used for primary actions, focus rings and highlights.
  ///
  /// This is the *only* accent in light mode: it keeps every on-white surface
  /// at WCAG AA/AAA contrast.
  static const Color primaryBlue = Color(0xFF145CFF);

  /// Glow accent reserved for the AMOLED dark palette (borders, highlights and
  /// glows). It is never used on white, where cyan would drop below AA.
  static const Color secondaryCyan = Color(0xFF00CFFF);

  /// Clears the AA/AAA bar for normal body text on a light/white surface.
  static const double minTextContrast = 4.5;

  // --- Light palette -------------------------------------------------------
  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFF9F9FB);
  static const Color lightTextPrimary = Color(0xFF0A0A0A);
  static const Color lightTextMuted = Color(0xFF4A4A4A);

  // --- Dark palette (AMOLED) ----------------------------------------------
  /// Pure black so dark screens draw the least possible power on OLED panels.
  static const Color darkBackground = Color(0xFF000000);

  /// Deep dark — one step above the background so cards still read as raised.
  static const Color darkSurface = Color(0xFF0A0A0A);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextMuted = Color(0xFF8E8E93);

  static const Color error = Color(0xFFE5484D);

  /// Subtle 1px card border in light mode (electric blue @ 15%).
  static final Color lightBorder = primaryBlue.withValues(alpha: 0.15);

  /// Slightly stronger border, e.g. outlines and focus affordances.
  static final Color lightBorderStrong = primaryBlue.withValues(alpha: 0.25);

  /// Subtle 1px card border in dark mode (cyan @ 20%).
  static final Color darkBorder = secondaryCyan.withValues(alpha: 0.20);

  static final Color darkBorderStrong = secondaryCyan.withValues(alpha: 0.30);
}

/// Corner radii used throughout the design system.
class AppRadii {
  const AppRadii._();

  static const double pill = 999;
  static const double sheet = 28;
  static const double card = 20;
  static const double input = 16;
  static const double row = 14;
}

/// Centralised "MapNote" Material 3 theme: colours, Manrope typography and the
/// component shapes (pill buttons, 20px cards, 16px inputs) that give the app
/// its Apple-style minimal look.
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isLight = brightness == Brightness.light;

    final Color background = isLight
        ? AppColors.lightBackground
        : AppColors.darkBackground;
    final Color surface = isLight
        ? AppColors.lightSurface
        : AppColors.darkSurface;
    final Color textPrimary = isLight
        ? AppColors.lightTextPrimary
        : AppColors.darkTextPrimary;
    final Color textMuted = isLight
        ? AppColors.lightTextMuted
        : AppColors.darkTextMuted;
    final Color border = isLight ? AppColors.lightBorder : AppColors.darkBorder;
    final Color borderStrong = isLight
        ? AppColors.lightBorderStrong
        : AppColors.darkBorderStrong;

    // Cyan is an AMOLED-only accent. In light mode every accent resolves back
    // to Electric Blue so text, icons and borders keep WCAG AA/AAA contrast on
    // white instead of washing out to a low-contrast cyan.
    final Color accent = isLight
        ? AppColors.primaryBlue
        : AppColors.secondaryCyan;
    final Color onAccent = isLight ? Colors.white : const Color(0xFF00131A);

    final ColorScheme scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primaryBlue,
          brightness: brightness,
        ).copyWith(
          primary: AppColors.primaryBlue,
          onPrimary: Colors.white,
          primaryContainer: AppColors.primaryBlue.withValues(alpha: 0.12),
          onPrimaryContainer: isLight
              ? AppColors.primaryBlue
              : AppColors.secondaryCyan,
          secondary: accent,
          onSecondary: onAccent,
          secondaryContainer: isLight
              ? AppColors.primaryBlue.withValues(alpha: 0.10)
              : AppColors.secondaryCyan.withValues(alpha: 0.16),
          onSecondaryContainer: isLight
              ? AppColors.primaryBlue
              : AppColors.secondaryCyan,
          tertiary: accent,
          onTertiary: onAccent,
          error: AppColors.error,
          onError: Colors.white,
          surface: surface,
          onSurface: textPrimary,
          onSurfaceVariant: textMuted,
          outline: borderStrong,
          outlineVariant: border,
          surfaceContainerHighest: surface,
        );

    final TextTheme text = _textTheme(brightness, textPrimary, textMuted);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardColor: surface,
      dividerColor: border,
      textTheme: text,
      primaryTextTheme: text,
      splashColor: AppColors.primaryBlue.withValues(alpha: 0.08),
      highlightColor: AppColors.primaryBlue.withValues(alpha: 0.04),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primaryBlue,
        selectionColor: AppColors.primaryBlue.withValues(alpha: 0.25),
        selectionHandleColor: AppColors.primaryBlue,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: background,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      iconTheme: IconThemeData(color: textPrimary, size: 22),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        hintStyle: TextStyle(color: textMuted, fontWeight: FontWeight.w400),
        labelStyle: TextStyle(color: textMuted),
        floatingLabelStyle: const TextStyle(
          color: AppColors.primaryBlue,
          fontWeight: FontWeight.w600,
        ),
        prefixIconColor: textMuted,
        suffixIconColor: textMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: const BorderSide(
            color: AppColors.primaryBlue,
            width: 1.6,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: const BorderSide(color: AppColors.error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: const BorderSide(color: AppColors.error, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll<double>(0),
          minimumSize: const WidgetStatePropertyAll<Size>(Size(64, 54)),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            StadiumBorder(
              side: BorderSide(
                color: accent.withValues(alpha: 0.30),
                width: 1.2,
              ),
            ),
          ),
          textStyle: WidgetStatePropertyAll<TextStyle>(
            TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w600,
              fontSize: 16,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll<double>(0),
          backgroundColor: const WidgetStatePropertyAll<Color>(
            AppColors.primaryBlue,
          ),
          foregroundColor: const WidgetStatePropertyAll<Color>(Colors.white),
          minimumSize: const WidgetStatePropertyAll<Size>(Size(64, 54)),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            StadiumBorder(
              side: BorderSide(
                color: accent.withValues(alpha: 0.30),
                width: 1.2,
              ),
            ),
          ),
          textStyle: WidgetStatePropertyAll<TextStyle>(
            TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w600,
              fontSize: 16,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll<double>(0),
          foregroundColor: WidgetStatePropertyAll<Color>(textPrimary),
          minimumSize: const WidgetStatePropertyAll<Size>(Size(64, 52)),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          ),
          side: WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: borderStrong),
          ),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(StadiumBorder()),
          textStyle: WidgetStatePropertyAll<TextStyle>(
            TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w600,
              fontSize: 15,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll<Color>(
            AppColors.primaryBlue,
          ),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(StadiumBorder()),
          textStyle: WidgetStatePropertyAll<TextStyle>(
            TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: AppColors.primaryBlue.withValues(alpha: 0.12),
        disabledColor: surface,
        side: BorderSide(color: border),
        shape: const StadiumBorder(),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: TextStyle(
          fontFamily: 'Manrope',
          color: textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: 'Manrope',
          color: AppColors.primaryBlue,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: border),
        ),
        titleTextStyle: text.titleLarge?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        contentTextStyle: text.bodyMedium?.copyWith(color: textMuted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: borderStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight
            ? const Color(0xFF0A0A0A)
            : const Color(0xFF1C1C1E),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        // Drawn on the near-black snackbar surface, so this is a dark-surface
        // highlight (≈11:1) rather than a light-palette accent.
        actionTextColor: AppColors.secondaryCyan,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.row),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.primaryBlue,
        textColor: textPrimary,
        titleTextStyle: text.titleMedium?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: text.bodySmall?.copyWith(color: textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.row),
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? AppColors.primaryBlue
              : null,
        ),
        thumbColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) =>
              states.contains(WidgetState.selected) ? Colors.white : null,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primaryBlue,
        linearTrackColor: border,
      ),
      dividerTheme: DividerThemeData(space: 1, thickness: 1, color: border),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: MapNotePageTransitionsBuilder(),
          TargetPlatform.iOS: MapNotePageTransitionsBuilder(),
          TargetPlatform.macOS: MapNotePageTransitionsBuilder(),
          TargetPlatform.windows: MapNotePageTransitionsBuilder(),
          TargetPlatform.linux: MapNotePageTransitionsBuilder(),
          TargetPlatform.fuchsia: MapNotePageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Builds the Manrope [TextTheme] with the MapNote tracking and weights.
  static TextTheme _textTheme(
    Brightness brightness,
    Color textPrimary,
    Color textMuted,
  ) {
    // Use the locally bundled Manrope family (declared in pubspec.yaml) rather
    // than any runtime font loader, so text paints correctly offline.
    final TextTheme raw = brightness == Brightness.light
        ? ThemeData.light().textTheme
        : ThemeData.dark().textTheme;
    final TextTheme base = raw.apply(fontFamily: 'Manrope');

    TextStyle? headline(TextStyle? style) => style?.copyWith(
      color: textPrimary,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    );

    return base.copyWith(
      displayLarge: headline(base.displayLarge),
      displayMedium: headline(base.displayMedium),
      displaySmall: headline(base.displaySmall),
      headlineLarge: headline(base.headlineLarge),
      headlineMedium: headline(base.headlineMedium),
      headlineSmall: headline(base.headlineSmall),
      titleLarge: base.titleLarge?.copyWith(
        color: textPrimary,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleMedium: base.titleMedium?.copyWith(
        color: textPrimary,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleSmall: base.titleSmall?.copyWith(
        color: textPrimary,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        color: textPrimary,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        color: textMuted,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: base.bodySmall?.copyWith(
        color: textMuted,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: base.labelLarge?.copyWith(
        color: textPrimary,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: base.labelMedium?.copyWith(
        color: textMuted,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
      labelSmall: base.labelSmall?.copyWith(
        color: textMuted,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
  }
}
