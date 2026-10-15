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
import 'package:routenote/src/widgets/qibla_indicator.dart';

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
    tempDir = await Directory.systemTemp.createTemp('routenote_compass_');
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

  /// The app-bar compass action renders [Icons.explore_outlined] while the
  /// Dynamic Island slot is collapsed and [Icons.explore] while it is open.
  /// Targeting the icon avoids the indicator's own "Compass"-tooltipped refresh
  /// button, which would make a tooltip finder ambiguous.
  Finder appBarCompass() => find.byIcon(Icons.explore_outlined);
  Finder appBarCompassExpanded() => find.byIcon(Icons.explore);

  testWidgets(
    'the Dynamic Island slot and the compass sheet never run two Qibla '
    'indicators at once',
    (WidgetTester tester) async {
      await pumpApp(tester);
      expect(find.byType(QiblaIndicator), findsNothing);

      // Long-press expands the Dynamic Island slot: exactly one live indicator.
      await tester.longPress(appBarCompass());
      await tester.pumpAndSettle();
      expect(find.byType(QiblaIndicator), findsOneWidget);
      expect(appBarCompassExpanded(), findsOneWidget);

      // A single tap opens the full sheet. The slot must collapse first, so the
      // two placements never hold live magnetometer/GPS subscriptions at the
      // same time — there is still only one QiblaIndicator in the tree.
      await tester.tap(appBarCompassExpanded());
      await tester.pumpAndSettle();
      expect(find.byType(QiblaIndicator), findsOneWidget);

      // Dismissing the sheet restores the expanded slot (one indicator again).
      Navigator.of(tester.element(find.byType(QiblaIndicator))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(QiblaIndicator), findsOneWidget);
      expect(appBarCompassExpanded(), findsOneWidget);
    },
  );
}
