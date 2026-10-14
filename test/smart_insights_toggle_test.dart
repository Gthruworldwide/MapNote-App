import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/app.dart';
import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/core/config/preferred_nav_app.dart';
import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/remote/auth_service.dart';
import 'package:routenote/src/features/home/widgets/smart_insights_card.dart';
import 'package:routenote/src/features/settings/settings_screen.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/app_health_logger.dart';

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
  late Box<dynamic> placesBox;
  late Box<dynamic> settingsBox;
  late HiveDatabase database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('routenote_insights_');
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

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hiveDatabaseProvider.overrideWithValue(database),
          authServiceProvider.overrideWithValue(_FakeAuthService()),
          // The agent health log must stay in-memory inside the FakeAsync zone.
          appHealthLoggerProvider.overrideWithValue(AppHealthLogger(null)),
        ],
        child: const MapNoteApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('home shows Smart Insights by default', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    expect(find.byType(SmartInsightsCard), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
  });

  testWidgets('home hides Smart Insights when disabled', (
    WidgetTester tester,
  ) async {
    // Seed through runAsync: real Hive writes cannot complete inside the
    // FakeAsync zone of a widget test.
    await tester.runAsync(
      () => settingsBox.put('smart_insights_enabled', false),
    );
    await pumpApp(tester);

    expect(find.byType(SmartInsightsCard), findsNothing);
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
  });

  testWidgets('settings shows the nav-app picker and insights toggle', (
    WidgetTester tester,
  ) async {
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
          home: const SettingsScreen(),
        ),
      ),
    );
    // No pumpAndSettle: the location status row shows an indeterminate spinner.
    await tester.pump(const Duration(milliseconds: 100));

    // Preferred navigation app picker (defaults to system).
    expect(find.text('Preferred navigation app'), findsOneWidget);
    expect(find.byType(DropdownButton<PreferredNavApp>), findsOneWidget);

    // Smart Insights master toggle (defaults to enabled).
    expect(find.text('Enable Smart Insights'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsWidgets);
  });
}
