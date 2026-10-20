import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/local/settings_repository.dart';
import 'package:routenote/src/data/remote/auth_service.dart';
import 'package:routenote/src/providers/app_providers.dart';

/// Auth service stand-in that reports a fixed result for the silent attempt.
class _FakeAuthService implements AuthService {
  _FakeAuthService({this.silentUser});

  final AuthUser? silentUser;
  int silentCalls = 0;
  AuthUser? _user;

  @override
  AuthUser? get currentUser => _user;

  @override
  bool get isSignedIn => _user != null;

  @override
  Future<void> initialize() async {}

  @override
  Future<AuthUser?> signInSilently() async {
    silentCalls++;
    _user = silentUser;
    return silentUser;
  }

  @override
  Future<AuthUser> signIn() {
    throw UnimplementedError('signIn is not used in these tests');
  }

  @override
  Future<void> signOut() async {
    _user = null;
  }

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
    // The restore guard is process-wide by design; re-arm it per test so the
    // tests do not observe each other's one-shot attempt.
    AuthNotifier.resetRestoreGuard();
    tempDir = await Directory.systemTemp.createTemp('routenote_auth_');
    Hive.init(tempDir.path);
    placesBox = await Hive.openBox<dynamic>('auth_places');
    settingsBox = await Hive.openBox<dynamic>('auth_settings');
    database = HiveDatabase(placesBox: placesBox, settingsBox: settingsBox);
  });

  tearDown(() async {
    await placesBox.close();
    await settingsBox.close();
    await tempDir.delete(recursive: true);
  });

  ProviderContainer containerWith(AuthService auth) {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        hiveDatabaseProvider.overrideWithValue(database),
        authServiceProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('cached session renders immediately without a loading state', () async {
    await settingsBox.put('is_logged_in', true);
    await settingsBox.put('auth_user', <String, dynamic>{
      'id': 'user-1',
      'email': 'cached@example.com',
      'displayName': 'Cached User',
      'photoUrl': null,
    });

    final _FakeAuthService auth = _FakeAuthService();
    final ProviderContainer container = containerWith(auth);

    final AsyncValue<AuthUser?> first = container.read(authProvider);

    // No "Signing in..." loader: the cached user is available synchronously.
    expect(first.isLoading, isFalse);
    expect(first.value?.email, 'cached@example.com');
  });

  test('silent sign-in runs in the background and updates the state', () async {
    // A *cached* session is what authorises a silent restore.
    await settingsBox.put('is_logged_in', true);
    await settingsBox.put('auth_user', <String, dynamic>{
      'id': 'stale',
      'email': 'stale@example.com',
      'displayName': null,
      'photoUrl': null,
    });

    final _FakeAuthService auth = _FakeAuthService(
      silentUser: const AuthUser(id: 'user-2', email: 'silent@example.com'),
    );
    final ProviderContainer container = containerWith(auth);

    // The cached session is on screen immediately, so the first frame is signed
    // in rather than a "Signing in..." loader...
    expect(container.read(authProvider).value?.email, 'stale@example.com');

    // ...then the background silent sign-in resolves and persists the session.
    await pumpEventQueue();
    expect(auth.silentCalls, greaterThanOrEqualTo(1));
    expect(container.read(authProvider).value?.email, 'silent@example.com');

    final SettingsRepository settings = SettingsRepository(settingsBox);
    expect(settings.isLoggedIn, isTrue);
    expect(settings.authUser?['email'], 'silent@example.com');
  });

  test(
    'a signed-out launch never attempts a silent restore '
    '(no Credential Manager UI on launch)',
    () async {
      // Regression: `attemptLightweightAuthentication()` on Android is allowed
      // to launch the Credential Manager chooser. That chooser is an Activity
      // in MapNote's own task, so it backgrounds the app and dismissing it
      // foregrounds it again -> the provider rebuilds -> another chooser. The
      // loop is broken at the source: with no cached session there is nothing
      // to restore, so the attempt must not be made at all.
      final _FakeAuthService auth = _FakeAuthService(
        silentUser: const AuthUser(id: 'user-3', email: 'never@example.com'),
      );
      final ProviderContainer container = containerWith(auth);

      expect(container.read(authProvider).value, isNull);

      await pumpEventQueue();

      expect(
        auth.silentCalls,
        0,
        reason: 'signed-out launch must not summon the credential chooser',
      );
      expect(container.read(authProvider).value, isNull);
    },
  );

  test('a rebuild re-enters the silent restore at most zero times', () async {
    AuthNotifier.resetRestoreGuard();
    await settingsBox.put('is_logged_in', true);
    await settingsBox.put('auth_user', <String, dynamic>{
      'id': 'user-4',
      'email': 'cached4@example.com',
      'displayName': null,
      'photoUrl': null,
    });

    final _FakeAuthService auth = _FakeAuthService();
    final ProviderContainer container = containerWith(auth);

    container.read(authProvider);
    await pumpEventQueue();
    expect(auth.silentCalls, 1);

    // Simulate the chooser having bounced the app to the foreground: the
    // provider rebuilds, which would re-run `build()`.
    container.invalidate(authProvider);
    container.read(authProvider);
    await pumpEventQueue();
    container.invalidate(authProvider);
    container.read(authProvider);
    await pumpEventQueue();

    expect(
      auth.silentCalls,
      1,
      reason: 'the restore is single-flight for the whole process',
    );
  });

  test('a null silent result keeps the cached session (no silent sign-out)', () async {
    AuthNotifier.resetRestoreGuard();
    await settingsBox.put('is_logged_in', true);
    await settingsBox.put('auth_user', <String, dynamic>{
      'id': 'user-5',
      'email': 'keep@example.com',
      'displayName': 'Keep Me',
      'photoUrl': null,
    });

    // The platform reports "no restorable session" (transient refusal).
    final _FakeAuthService auth = _FakeAuthService();
    final ProviderContainer container = containerWith(auth);

    expect(container.read(authProvider).value?.email, 'keep@example.com');
    await pumpEventQueue();

    // The user stays signed in; a transient refusal must never clear the vault
    // of a locally cached session.
    expect(container.read(authProvider).value?.email, 'keep@example.com');
    expect(SettingsRepository(settingsBox).isLoggedIn, isTrue);
  });
}
