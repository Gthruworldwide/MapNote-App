import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'app.dart';
import 'src/core/config/app_config.dart';
import 'src/data/local/hive_database.dart';
import 'src/providers/app_providers.dart';
import 'src/services/app_logger.dart';
import 'src/services/background_sync_scheduler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- Firebase (Crashlytics + Analytics) ------------------------------------
  // Best-effort: MapNote is offline-first, so a missing or incomplete
  // google-services.json must never stop the app from launching. Crashlytics is
  // only used once init succeeded.
  bool crashlyticsReady = false;
  try {
    await Firebase.initializeApp();
    crashlyticsReady = true;
  } catch (error, stack) {
    debugPrint('Firebase.initializeApp() failed: $error');
    AppLogger.log(
      category: 'FIREBASE',
      message: 'Firebase.initializeApp() failed; Crashlytics disabled',
      error: error,
      stackTrace: stack,
    );
  }

  // --- Automatic Global Error Handling & App Logging ------------------------
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    AppLogger.log(
      category: 'FLUTTER_FRAMEWORK',
      message: details.exceptionAsString(),
      error: details.exception,
      stackTrace: details.stack,
    );
    if (crashlyticsReady) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    }
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLogger.log(
      category: 'UNCAUGHT_ASYNC',
      message: error.toString(),
      error: error,
      stackTrace: stack,
    );
    if (crashlyticsReady) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
    return true;
  };

  // --- Offline-first storage -------------------------------------------------
  await Hive.initFlutter();
  final HiveDatabase database = HiveDatabase(
    placesBox: await Hive.openBox<dynamic>(AppConfig.placesBoxName),
    settingsBox: await Hive.openBox<dynamic>(AppConfig.settingsBoxName),
    gpsDailyBox: await Hive.openBox<dynamic>(AppConfig.gpsDailyBoxName),
    autoMotionBox: await Hive.openBox<dynamic>(AppConfig.autoMotionBoxName),
  );

  runApp(
    ProviderScope(
      overrides: [hiveDatabaseProvider.overrideWithValue(database)],
      child: const MapNoteApp(),
    ),
  );

  // --- Background backup (best-effort) ---------------------------------------
  const BackgroundSyncScheduler scheduler = BackgroundSyncScheduler();
  unawaited(
    scheduler.initialize().then((void _) => scheduler.schedulePeriodicBackup()),
  );
}
