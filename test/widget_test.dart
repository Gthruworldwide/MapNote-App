import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/app.dart';
import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/remote/auth_service.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/app_health_logger.dart';

/// Stand-in for [GoogleAuthService] so widget tests never touch the
/// `google_sign_in` platform channel.
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
  Future<AuthUser> signIn() {
    throw UnimplementedError('signIn is not used in widget tests');
  }

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
    tempDir = await Directory.systemTemp.createTemp('routenote_test_');
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
          // The widget tree runs inside a FakeAsync zone, where a real Hive
          // write can never complete (and would deadlock `box.close()` in
          // tearDown). Keep the health log in memory for these tests.
          appHealthLoggerProvider.overrideWithValue(AppHealthLogger(null)),
        ],
        child: const MapNoteApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('MapNoteApp renders the empty home screen', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    // App shell is visible.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    // A saved place was never added, so the empty state is shown.
    expect(find.byIcon(Icons.place_outlined), findsWidgets);

    // The Smart Insights agent surfaces its onboarding suggestion.
    expect(find.text('Smart Insights'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
  });

  testWidgets('a saved place appears in the list', (WidgetTester tester) async {
    // Seed through runAsync: real file I/O cannot complete inside the
    // FakeAsync zone of a widget test.
    await tester.runAsync(
      () => placesBox.put('place-1', <String, dynamic>{
        'id': 'place-1',
        'name': 'Cairo Tower',
        'notes': 'Near the Nile',
        'latitude': 30.0444,
        'longitude': 31.2357,
        'timestamp': DateTime(2026, 1, 1).millisecondsSinceEpoch,
      }),
    );

    await pumpApp(tester);

    expect(find.text('Cairo Tower'), findsOneWidget);
    expect(find.text('Near the Nile'), findsOneWidget);
  });
}
