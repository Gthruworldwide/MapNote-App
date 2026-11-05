import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'src/core/config/app_config.dart';
import 'src/data/local/hive_database.dart';
import 'src/data/local/settings_repository.dart';
import 'src/providers/app_providers.dart';

import 'src/services/database_seeder.dart';

// Localization and UI components
import 'l10n/generated/app_localizations.dart';
import 'src/core/theme/app_theme.dart';
import 'src/features/home/home_screen.dart';
import 'src/features/splash/brand_splash.dart';

// Defines the font scale presets used in Work Edition.
enum WorkFontScalePreset {
  small,
  standard,
  large,
  extraLarge,
}

/// Convert [settings_repository.FontScalePreset] to [WorkFontScalePreset].
WorkFontScalePreset _toWorkFontScalePreset(FontScalePreset preset) {
  switch (preset) {
    case FontScalePreset.small:
      return WorkFontScalePreset.small;
    case FontScalePreset.standard:
      return WorkFontScalePreset.standard;
    case FontScalePreset.large:
      return WorkFontScalePreset.large;
    case FontScalePreset.extraLarge:
      return WorkFontScalePreset.extraLarge;
  }
}

/// Launch point for **MapNote Work Edition** — a no‑automation, offline‑first
/// version of MapNote.
///
/// Removes all background workers (AutomationService, session timers, inactivity
/// clocks, dynamic shortcuts). Keeps:
/// - Hive database (stations + settings)
/// - Google Drive backup (user‑initiated, `drive.appdata` scope)
/// - Core UI: home, place detail, vault, settings
/// - First‑launch seed engine for default stations
///
/// The [DatabaseSeeder.maybeSeed] merges the bundled `assets/data/stations.json`
/// catalogue into the places box once per catalogue version.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase (best‑effort).
  await Firebase.initializeApp();

  // Offline‑first storage.
  await Hive.initFlutter();
  final HiveDatabase database = HiveDatabase(
    placesBox: await Hive.openBox<dynamic>(AppConfig.placesBoxName),
    settingsBox: await Hive.openBox<dynamic>(AppConfig.settingsBoxName),
    stationBox: await Hive.openBox<dynamic>('station_data'),
    gpsDailyBox: await Hive.openBox<dynamic>(AppConfig.gpsDailyBoxName),
  );

  // First‑launch seed — merges the bundled catalogue into the places box.
  await DatabaseSeeder.maybeSeed(
    placesBox: database.placesBox,
    settingsBox: database.settingsBox,
  );

  runApp(
    ProviderScope(
      overrides: [
        hiveDatabaseProvider.overrideWithValue(database),
        appEditionProvider.overrideWithValue(AppEdition.work),
      ],
      child: const MapNoteWorkApp(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Work‑Edition widget tree (minimal, no automation).
// ---------------------------------------------------------------------------
class MapNoteWorkApp extends ConsumerWidget {
  const MapNoteWorkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    // Convert the settings repository's FontScalePreset to our local type.
    final workFontScale = _toWorkFontScalePreset(ref.watch(fontScaleProvider));

    double fontScaleFactor(WorkFontScalePreset preset) {
      switch (preset) {
        case WorkFontScalePreset.small:
          return 0.85;
        case WorkFontScalePreset.standard:
          return 1.0;
        case WorkFontScalePreset.large:
          return 1.15;
        case WorkFontScalePreset.extraLarge:
          return 1.3;
      }
    }

    return MaterialApp(
      // navigatorKey removed — Work Edition uses default navigator.
      onGenerateTitle: (BuildContext context) =>
          AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: ref.watch(localeControllerProvider),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      navigatorObservers: ref.watch(analyticsNavigatorObserversProvider),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(fontScaleFactor(workFontScale)),
          ),
          child: BrandSplash(child: child ?? const SizedBox.shrink()),
        );
      },
      home: HomeScreen(),
    );
  }
}