import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/app.dart';
import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/data/local/auto_motion_data_source.dart';
import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/models/daily_gps_summary.dart';
import 'package:routenote/src/data/remote/auth_service.dart';
import 'package:routenote/src/features/home/widgets/auto_motion_badge.dart';
import 'package:routenote/src/features/home/widgets/auto_motion_card.dart';
import 'package:routenote/src/features/settings/location_settings_screen.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/app_health_logger.dart';
import 'package:routenote/src/services/auto_motion_service.dart';
import 'package:routenote/src/services/location_service.dart';

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

/// A tracker whose stream starts instantly, so the Home card test can observe
/// a deterministic "Active" status without touching the geolocator channels
/// (which never resolve inside the FakeAsync zone of a widget test).
class _InstantMotion extends AutoMotionService {
  _InstantMotion(AutoMotionDataSource store) : super(dailyStore: store);

  @override
  Future<bool> start({
    LocationService? locations,
    Stream<Position>? positions,
  }) async {
    return true;
  }

  @override
  Future<void> stop() async {}
}

/// A tracker that never writes to Hive, used by the "paused with today's
/// totals" test. `_idle` re-seeds today's totals from the store to drive the
/// card, but `stop()` must not persist anything: the dispose-time save would
/// hand a real Hive write to the FakeAsync teardown zone, which hangs.
class _IdleMotion extends AutoMotionService {
  _IdleMotion(AutoMotionDataSource store) : super(dailyStore: store);

  @override
  Future<bool> start({
    LocationService? locations,
    Stream<Position>? positions,
  }) async {
    return false;
  }

  @override
  Future<void> stop() async {}
}

void main() {
  late Directory tempDir;
  late Box<dynamic> placesBox;
  late Box<dynamic> settingsBox;
  late HiveDatabase database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('routenote_automotion_ui_');
    Hive.init(tempDir.path);
    placesBox = await Hive.openBox<dynamic>('test_places');
    settingsBox = await Hive.openBox<dynamic>('test_settings');
    database = HiveDatabase(placesBox: placesBox, settingsBox: settingsBox);
  });

  tearDown(() async {
    await placesBox.close();
    await settingsBox.close();
    await tempDir.delete(recursive: true);
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    Locale? locale,
  }) async {
    // Taller viewport so every settings section is mounted (ListView only
    // builds visible children at 800x600).
    tester.view.physicalSize = const Size(800, 1900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hiveDatabaseProvider.overrideWithValue(database),
          authServiceProvider.overrideWithValue(_FakeAuthService()),
          appHealthLoggerProvider.overrideWithValue(AppHealthLogger(null)),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: const LocationSettingsScreen(),
        ),
      ),
    );
    // No pumpAndSettle: the location status row shows an indeterminate spinner.
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    AutoMotionService? motion,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hiveDatabaseProvider.overrideWithValue(database),
          authServiceProvider.overrideWithValue(_FakeAuthService()),
          appHealthLoggerProvider.overrideWithValue(AppHealthLogger(null)),
          if (motion != null)
            autoMotionServiceProvider.overrideWithValue(motion),
        ],
        child: const MapNoteApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder switchFinder(String label) => find.descendant(
        of: find.widgetWithText(SwitchListTile, label),
        matching: find.byType(Switch),
      );

  testWidgets('settings shows the AutoMotion toggle (off by default)',
      (WidgetTester tester) async {
    await pumpSettings(tester);

    expect(find.text('Enable Smart AutoMotion'), findsOneWidget);
    expect(
      find.text(
        'Fuses GPS and motion sensors to track distance & speed while saving battery',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<Switch>(switchFinder('Enable Smart AutoMotion')).value,
      isFalse,
    );
  });

  testWidgets('settings shows the AutoMotion toggle in Arabic',
      (WidgetTester tester) async {
    await pumpSettings(tester, locale: const Locale('ar'));

    expect(find.text('تفعيل تتبع AutoMotion الذكي'), findsOneWidget);
    expect(find.text('أوتوموشن'), findsOneWidget);
  });

  testWidgets('flipping the AutoMotion toggle persists enable_auto_motion',
      (WidgetTester tester) async {
    await pumpSettings(tester);
    expect(find.text('Enable Smart AutoMotion'), findsOneWidget);

    // The onChanged handler writes to real Hive: drive the tap through the
    // real event loop with runAsync so the write (and the follow-up provider
    // update) completes before we return to the FakeAsync zone.
    await tester.runAsync(() async {
      await tester.tap(switchFinder('Enable Smart AutoMotion'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    await tester.pump();

    expect(
      tester.widget<Switch>(switchFinder('Enable Smart AutoMotion')).value,
      isTrue,
    );

    bool? persisted;
    await tester.runAsync(() async {
      persisted = settingsBox.get('enable_auto_motion') as bool?;
    });
    expect(persisted, isTrue);
  });

  testWidgets('home shows the AutoMotion dashboard card when enabled',
      (WidgetTester tester) async {
    // Seed through runAsync: real Hive writes cannot complete inside the
    // FakeAsync zone of a widget test.
    await tester.runAsync(() => settingsBox.put('enable_auto_motion', true));
    // Use an instant-start tracker so the status badge settles on "Active"
    // deterministically (the real geolocator channels never resolve inside
    // the FakeAsync zone).
    await pumpApp(
      tester,
      motion: _InstantMotion(AutoMotionDataSource(settingsBox)),
    );

    expect(find.byType(AutoMotionCard), findsOneWidget);
    expect(find.text('AutoMotion'), findsOneWidget);
    // Today's distance (0.00 km) and max speed (0.0 km/h) with the active
    // status badge.
    expect(find.text('0.00 km'), findsOneWidget);
    expect(find.text('0.0 km/h'), findsOneWidget);
    // The status badge is now a custom painter, not a text label: assert its
    // active state directly.
    final AutoMotionBadge badge =
        tester.widget<AutoMotionBadge>(find.byType(AutoMotionBadge));
    expect(badge.isActive, isTrue);
    expect(badge.isUnavailable, isFalse);
  });

  testWidgets(
      'home keeps the AutoMotion card visible with today\'s totals while the '
      'toggle is off (Paused badge)', (WidgetTester tester) async {
    // AutoMotion is off, but today already has recorded motion from an earlier
    // session — stored directly in the auto_motion box under its YYYY-MM-DD key.
    final DateTime today = DailyGpsSummary.dayOf(DateTime.now());
    await tester.runAsync(() => settingsBox.put(
          DailyGpsSummary.dayKey(today),
          <String, dynamic>{
            'date': DailyGpsSummary.dayKey(today),
            'total_km': 3.5,
            'max_speed': 40,
          },
        ));

    // Idle tracker that re-seeds today's totals from storage but never writes
    // (a real stop() persist would hand a Hive write to the FakeAsync teardown
    // zone and hang). The toggle is off, so no geolocator call is made.
    await pumpApp(tester, motion: _IdleMotion(AutoMotionDataSource(settingsBox)));

    expect(find.byType(AutoMotionCard), findsOneWidget);
    expect(find.text('3.50 km'), findsOneWidget);
    expect(find.text('40.0 km/h'), findsOneWidget);
    // Paused: the badge is neither active nor unavailable.
    final AutoMotionBadge badge =
        tester.widget<AutoMotionBadge>(find.byType(AutoMotionBadge));
    expect(badge.isActive, isFalse);
    expect(badge.isUnavailable, isFalse);
  });

  testWidgets('home hides the AutoMotion card when disabled and no motion yet',
      (WidgetTester tester) async {
    await pumpApp(tester);
    expect(find.byType(AutoMotionCard), findsNothing);
  });
}