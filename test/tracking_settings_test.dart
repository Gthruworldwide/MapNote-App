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
import 'package:routenote/src/data/remote/auth_service.dart';
import 'package:routenote/src/features/settings/settings_screen.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/app_health_logger.dart';
import 'package:routenote/src/services/auto_motion_service.dart';
import 'package:routenote/src/services/location_service.dart';

/// Builds a [Position] with the required fields for geolocator 14.
Position _fix(
  double lat,
  double lon, {
  double speed = 0,
  DateTime? at,
}) {
  return Position(
    latitude: lat,
    longitude: lon,
    timestamp: at ?? DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
    hasAccuracy: true,
    hasSpeed: true,
  );
}

/// In-memory store: a real Hive write can never complete inside a widget test's
/// FakeAsync zone, so persistence is a no-op here.
class _SilentStore extends AutoMotionDataSource {
  _SilentStore(super.box);

  @override
  Future<void> save(DailyGpsSummary summary) async {}
}

/// AutoMotion tracker that reports "started" without touching platform
/// channels, so the test controls the fixes through [recordPosition].
class _ScriptedMotion extends AutoMotionService {
  _ScriptedMotion(AutoMotionDataSource store) : super(dailyStore: store);

  @override
  Future<bool> start({
    LocationService? locations,
    Stream<Position>? positions,
  }) async =>
      true;
}

class _FakeAuthService implements AuthService {
  @override
  AuthUser? get currentUser => null;

  @override
  bool get isSignedIn => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<AuthUser?> signInSilently() async => null;

  @override
  Future<AuthUser> signIn() => throw UnimplementedError();

  @override
  Future<void> signOut() async {}

  @override
  Future<Map<String, String>?> authorizationHeaders({
    bool prompt = false,
  }) async {
    return null;
  }
}

void main() {
  late Directory tempDir;
  late HiveDatabase database;
  late Box<dynamic> placesBox;
  late Box<dynamic> settingsBox;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mapnote_tracking_test');
    Hive.init(tempDir.path);
    placesBox = await Hive.openBox<dynamic>('places');
    settingsBox = await Hive.openBox<dynamic>('settings');
    database = HiveDatabase(placesBox: placesBox, settingsBox: settingsBox);
  });

  tearDown(() async {
    await placesBox.close();
    await settingsBox.close();
    await tempDir.delete(recursive: true);
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    AutoMotionService? motion,
  }) async {
    // Taller viewport so every settings section is mounted.
    tester.view.physicalSize = const Size(800, 1900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hiveDatabaseProvider.overrideWithValue(database),
          authServiceProvider.overrideWithValue(_FakeAuthService()),
          appHealthLoggerProvider.overrideWithValue(AppHealthLogger(null)),
          if (motion != null)
            autoMotionServiceProvider.overrideWithValue(motion),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('the today report refreshes as fixes arrive (no toggle needed)', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() => settingsBox.put('enable_auto_motion', true));
    final _ScriptedMotion motion = _ScriptedMotion(_SilentStore(settingsBox));

    await pumpSettings(tester, motion: motion);

    expect(find.text('Distance today'), findsOneWidget);
    expect(find.text('0.00 km'), findsOneWidget);

    // Two fixes ~1 km apart at 10 m/s ⇒ 36 km/h.
    motion.recordPosition(_fix(0, 0));
    motion.recordPosition(_fix(0.009, 0, speed: 10));
    await tester.pump();
    await tester.pump();

    expect(find.text('1.00 km'), findsOneWidget);
    expect(find.text('36.0 km/h'), findsOneWidget);
  });

  testWidgets('the tracking card renders exactly one report block with both '
      'engines enabled', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await settingsBox.put('gps_tracking_enabled', true);
      await settingsBox.put('enable_auto_motion', true);
    });

    await pumpSettings(
      tester,
      motion: _ScriptedMotion(_SilentStore(settingsBox)),
    );

    // One shared report: never duplicated per engine.
    expect(find.text('Distance today'), findsOneWidget);
    expect(find.text('Max speed'), findsOneWidget);
    expect(find.text('Enable AutoMotion'), findsOneWidget);
    expect(find.text('Enable daily GPS tracking'), findsOneWidget);
  });

  testWidgets('with both engines off no report tile is shown',
      (WidgetTester tester) async {
    await pumpSettings(tester);

    expect(find.text('Distance today'), findsNothing);
    expect(find.text('Max speed'), findsNothing);
  });
}
