import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/app.dart';
import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/remote/auth_service.dart';
import 'package:routenote/src/features/add_place/add_place_screen.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/app_health_logger.dart';
import 'package:routenote/src/services/share_intent_service.dart';

/// Sign-in is irrelevant for the share flow; never touch the platform channel.
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
    throw UnimplementedError('signIn is not used in share tests');
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

/// Emits a fixed cold-start share instead of reading the platform channel.
class _FakeShareIntentService extends ShareIntentService {
  _FakeShareIntentService(this.initial);

  final List<String> initial;

  @override
  Stream<String> textStream() => const Stream<String>.empty();

  @override
  Future<List<String>> initialText() async => initial;
}

void main() {
  late Directory tempDir;
  late Box<dynamic> placesBox;
  late Box<dynamic> settingsBox;
  late HiveDatabase database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('routenote_share_');
    Hive.init(tempDir.path);
    placesBox = await Hive.openBox<dynamic>('test_share_places');
    settingsBox = await Hive.openBox<dynamic>('test_share_settings');
    database = HiveDatabase(placesBox: placesBox, settingsBox: settingsBox);
  });

  tearDown(() async {
    await placesBox.close();
    await settingsBox.close();
    await tempDir.delete(recursive: true);
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    required ShareIntentService shareIntentService,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hiveDatabaseProvider.overrideWithValue(database),
          authServiceProvider.overrideWithValue(_FakeAuthService()),
          shareIntentServiceProvider.overrideWithValue(shareIntentService),
          // See widget_test.dart: avoid real Hive writes inside FakeAsync.
          appHealthLoggerProvider.overrideWithValue(AppHealthLogger(null)),
        ],
        child: const MapNoteApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a shared Google Maps link opens the save screen pre-filled', (
    WidgetTester tester,
  ) async {
    await pumpApp(
      tester,
      shareIntentService: _FakeShareIntentService(<String>[
        'https://www.google.com/maps/place/Cairo+Tower/@30.0459,31.2243,17z',
      ]),
    );

    expect(find.byType(AddPlaceScreen), findsOneWidget);
    expect(find.text('Cairo Tower'), findsOneWidget);
    expect(find.text('30.0459'), findsOneWidget);
    expect(find.text('31.2243'), findsOneWidget);
  });

  testWidgets('shared text without coordinates shows a message', (
    WidgetTester tester,
  ) async {
    await pumpApp(
      tester,
      shareIntentService: _FakeShareIntentService(<String>[
        'just a plain note with no location',
      ]),
    );

    expect(find.byType(AddPlaceScreen), findsNothing);
    expect(find.text('No location found in the shared text'), findsOneWidget);
  });
}
