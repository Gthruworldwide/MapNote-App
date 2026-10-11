import 'dart:async';

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

  // --- Automatic Global Error Handling & App Logging ------------------------
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    AppLogger.log(
      category: 'FLUTTER_FRAMEWORK',
      message: details.exceptionAsString(),
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLogger.log(
      category: 'UNCAUGHT_ASYNC',
      message: error.toString(),
      error: error,
      stackTrace: stack,
    );
    return true;
  };

  // --- Offline-first storage -------------------------------------------------
  await Hive.initFlutter();
  final HiveDatabase database = HiveDatabase(
    placesBox: await Hive.openBox<dynamic>(AppConfig.placesBoxName),
    settingsBox: await Hive.openBox<dynamic>(AppConfig.settingsBoxName),
    gpsDailyBox: await Hive.openBox<dynamic>(AppConfig.gpsDailyBoxName),
  );

  runApp(
    ProviderScope(
      overrides: [hiveDatabaseProvider.overrideWithValue(database)],
      child: const RouteNoteApp(),
    ),
  );

  // --- Background backup (best-effort) ---------------------------------------
  const BackgroundSyncScheduler scheduler = BackgroundSyncScheduler();
  unawaited(
    scheduler.initialize().then((void _) => scheduler.schedulePeriodicBackup()),
  );
}
