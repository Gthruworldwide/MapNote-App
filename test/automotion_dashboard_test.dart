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
import 'package:routenote/src/features/home/widgets/auto_motion_card.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/app_health_logger.dart';
import 'package:routenote/src/services/auto_motion_service.dart';
import 'package:routenote/src/services/location_service.dart';

/// Builds a [Position] with the required fields for geolocator 14.
Position _fix(double lat, double lon, {double speed = 0}) {
  return Position(
    latitude: lat,
    longitude: lon,
    timestamp: DateTime.now(),
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
/// FakeAsync zone, so persistence is a no-op here and days are seeded directly.
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

void main() {
  late Directory tempDir;
  late HiveDatabase database;
  late Box<dynamic> placesBox;
  late Box<dynamic> settingsBox;
  late Box<dynamic> motionBox;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mapnote_motion_dashboard');
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

  /// Pumps a screen inside a fully-offline provider scope. The AutoMotion
  /// tracker is always scripted so no platform channels are touched.
  Future<void> pump(
    WidgetTester tester,
    _ScriptedMotion motion, {
    Widget home = const AutoMotionScreen(),
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hiveDatabaseProvider.overrideWithValue(database),
          appHealthLoggerProvider.overrideWithValue(AppHealthLogger(null)),
          autoMotionServiceProvider.overrideWithValue(motion),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('driver mode shows the live current speed and today\'s totals',
      (WidgetTester tester) async {
    await tester.runAsync(() => settingsBox.put('enable_auto_motion', true));
    final _ScriptedMotion motion = _ScriptedMotion(_SilentStore(motionBox));

    await pump(tester, motion);
    expect(find.text('Driver mode'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);

    // Two fixes ~1 km apart at 10 m/s ⇒ 36 km/h.
    motion.recordPosition(_fix(0, 0));
    motion.recordPosition(_fix(0.009, 0, speed: 10));
    await tester.pump();
    await tester.pump();

    expect(find.text('36.0'), findsOneWidget); // current speed headline
    expect(find.text('1.00 km'), findsOneWidget); // today's distance
    expect(find.text('36.0 km/h'), findsOneWidget); // today's max speed
  });

  testWidgets('trip history lists stored days newest-first',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await motionBox.put(
        DailyGpsSummary.dayKey(DateTime(2026, 1, 2)),
        DailyGpsSummary(date: DateTime(2026, 1, 2), totalKm: 2, maxSpeedKmh: 20)
            .toMap(),
      );
      await motionBox.put(
        DailyGpsSummary.dayKey(DateTime(2026, 1, 3)),
        DailyGpsSummary(date: DateTime(2026, 1, 3), totalKm: 3, maxSpeedKmh: 30)
            .toMap(),
      );
      await motionBox.put(
        DailyGpsSummary.dayKey(DateTime(2026, 1, 1)),
        DailyGpsSummary(date: DateTime(2026, 1, 1), totalKm: 1, maxSpeedKmh: 10)
            .toMap(),
      );
    });

    await pump(tester, _ScriptedMotion(_SilentStore(motionBox)));

    expect(find.text('Trip history'), findsOneWidget);
    expect(find.text('Jan 3, 2026'), findsOneWidget);
    expect(find.text('3.00 km'), findsOneWidget);
    expect(find.text('30.0 km/h'), findsOneWidget);
    expect(find.text('Jan 1, 2026'), findsOneWidget);

    // Newest-first: Jan 3 sits above Jan 2, which sits above Jan 1.
    final double y3 = tester.getTopLeft(find.text('Jan 3, 2026')).dy;
    final double y2 = tester.getTopLeft(find.text('Jan 2, 2026')).dy;
    final double y1 = tester.getTopLeft(find.text('Jan 1, 2026')).dy;
    expect(y3, lessThan(y2));
    expect(y2, lessThan(y1));
  });

  testWidgets('the history refreshes when the tracker records a fix',
      (WidgetTester tester) async {
    final _ScriptedMotion motion = _ScriptedMotion(_SilentStore(motionBox));
    await pump(tester, motion);
    expect(find.text('No motion recorded yet'), findsOneWidget);

    // A day written to the store lands in the list on the next tracker update.
    await tester.runAsync(() => motionBox.put(
          DailyGpsSummary.dayKey(DateTime(2026, 2, 4)),
          DailyGpsSummary(date: DateTime(2026, 2, 4), totalKm: 5, maxSpeedKmh: 40)
              .toMap(),
        ));
    motion.recordPosition(_fix(0, 0));
    await tester.pump();
    await tester.pump();

    expect(find.text('No motion recorded yet'), findsNothing);
    expect(find.text('Feb 4, 2026'), findsOneWidget);
    expect(find.text('5.00 km'), findsOneWidget);
  });

  testWidgets('an empty history shows the empty state',
      (WidgetTester tester) async {
    await pump(tester, _ScriptedMotion(_SilentStore(motionBox)));

    expect(find.text('No motion recorded yet'), findsOneWidget);
    expect(
      find.text('Days with recorded motion will appear here.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping the Home card opens the dashboard',
      (WidgetTester tester) async {
    await pump(
      tester,
      _ScriptedMotion(_SilentStore(motionBox)),
      home: const Scaffold(body: AutoMotionCard()),
    );
    expect(find.byType(AutoMotionScreen), findsNothing);

    await tester.tap(find.byType(AutoMotionCard));
    await tester.pumpAndSettle();

    expect(find.byType(AutoMotionScreen), findsOneWidget);
    expect(find.text('Driver mode'), findsOneWidget);
  });
}
