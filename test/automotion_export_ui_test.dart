import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/data/local/auto_motion_data_source.dart';
import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/models/daily_gps_summary.dart';
import 'package:routenote/src/features/automotion/automotion_screen.dart';
import 'package:routenote/src/features/automotion/widgets/auto_motion_export_sheet.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/app_health_logger.dart';
import 'package:routenote/src/services/auto_motion_service.dart';
import 'package:routenote/src/services/location_service.dart';
import 'package:routenote/src/services/auto_motion_export_service.dart';

class _SilentStore extends AutoMotionDataSource {
  _SilentStore(super.box);
  @override
  Future<void> save(DailyGpsSummary summary) async {}
}

class _ScriptedMotion extends AutoMotionService {
  _ScriptedMotion(AutoMotionDataSource store) : super(dailyStore: store);
  @override
  Future<bool> start({
    LocationService? locations,
    Stream<Position>? positions,
  }) async =>
      true;
}

void main() {
  late Directory tempDir;
  late HiveDatabase database;
  late Box<dynamic> placesBox;
  late Box<dynamic> settingsBox;
  late Box<dynamic> motionBox;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mapnote_export_ui');
    Hive.init(tempDir.path);
    placesBox = await Hive.openBox<dynamic>('places');
    settingsBox = await Hive.openBox<dynamic>('settings');
    motionBox = await Hive.openBox<dynamic>('auto_motion_box');
    database = HiveDatabase(
      placesBox: placesBox,
      settingsBox: settingsBox,
      autoMotionBox: motionBox,
    );
  });

  tearDown(() async {
    await placesBox.close();
    await settingsBox.close();
    await motionBox.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('export sheet renders CSV/JSON buttons and range picker', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hiveDatabaseProvider.overrideWithValue(database),
          appHealthLoggerProvider.overrideWithValue(AppHealthLogger(null)),
          autoMotionServiceProvider.overrideWithValue(
            _ScriptedMotion(_SilentStore(motionBox)),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AutoMotionExportBottomSheet()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Export as CSV'), findsOneWidget);
    expect(find.text('Export as JSON'), findsOneWidget);
    expect(find.text('Select date range'), findsOneWidget);
  });

  testWidgets('AutoMotion screen shows export action icon', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hiveDatabaseProvider.overrideWithValue(database),
          appHealthLoggerProvider.overrideWithValue(AppHealthLogger(null)),
          autoMotionServiceProvider.overrideWithValue(
            _ScriptedMotion(_SilentStore(motionBox)),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AutoMotionScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.file_download_outlined), findsOneWidget);
  });

  testWidgets('exported JSON contains no coordinate keys', (tester) async {
    // Seed a day.
    await tester.runAsync(() => motionBox.put(
          DailyGpsSummary.dayKey(DateTime(2026, 5, 5)),
          DailyGpsSummary(
            date: DateTime(2026, 5, 5),
            totalKm: 3,
            maxSpeedKmh: 20,
            walkKm: 1,
            vehicleKm: 2,
          ).toMap(),
        ));

    final store = AutoMotionDataSource(motionBox);
    final service = AutoMotionExportService(store);
    final String json = service.exportJson();
    expect(json.contains('latitude'), isFalse);
    expect(json.contains('longitude'), isFalse);
    expect(json.contains('lat'), isFalse);
    expect(json.contains('lng'), isFalse);
  });
}
