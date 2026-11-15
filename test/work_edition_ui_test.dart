import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/remote/auth_service.dart';
import 'package:routenote/src/features/home/home_screen.dart';
import 'package:routenote/src/features/home/widgets/auto_motion_card.dart';
import 'package:routenote/src/features/home/widgets/smart_insights_card.dart';
import 'package:routenote/src/features/home/widgets/smart_insights_widget.dart';
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
  Future<Map<String, String>?> authorizationHeaders({bool prompt = false}) async =>
      null;
}

void main() {
  late Directory tempDir;
  late Box<dynamic> placesBox;
  late Box<dynamic> settingsBox;
  late HiveDatabase database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('routenote_work_ui_');
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

  Future<void> pumpHome(
    WidgetTester tester, {
    required AppEdition edition,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hiveDatabaseProvider.overrideWithValue(database),
          authServiceProvider.overrideWithValue(_FakeAuthService()),
          appHealthLoggerProvider.overrideWithValue(AppHealthLogger(null)),
          appEditionProvider.overrideWithValue(edition),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Work Edition hides AutoMotion and shows work insights', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester, edition: AppEdition.work);

    expect(find.byType(AutoMotionCard), findsNothing);
    expect(find.byType(SmartInsightsWidget), findsOneWidget);
    expect(find.byType(SmartInsightsCard), findsNothing);
    expect(find.text('Smart Insights'), findsOneWidget);
  });

  testWidgets('Personal edition keeps agent Smart Insights card', (
    WidgetTester tester,
  ) async {
    // AutoMotion is enabled by default; its presence is the personal-app
    // behaviour this gate must preserve.
    await pumpHome(tester, edition: AppEdition.personal);

    expect(find.byType(SmartInsightsCard), findsOneWidget);
    expect(find.byType(SmartInsightsWidget), findsNothing);
  });
}
