import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/local/settings_repository.dart';
import 'package:routenote/src/data/remote/auth_service.dart';
import 'package:routenote/src/data/remote/drive_service.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/app_health_logger.dart';

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

/// Waits until [condition] holds, yielding to the event loop between checks.
///
/// `pumpEventQueue()` only yields a fixed number of times, so it can return
/// before a real Hive write has landed. The silent restore persists the
/// refreshed session to disk, so asserting on it after a fixed number of
/// yields was flaky under a fully parallel test run. Bounding the wait by real
/// time instead makes the assertion deterministic.
Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Drive stand-in that records uploads without touching the network.
class _FakeDriveService implements DriveService {
  int uploads = 0;
  bool hasBackup = false;

  @override
  Future<bool> backupExists() async => hasBackup;

  @override
  Future<DateTime?> remoteModifiedTime() async => null;

  @override
  Future<String?> downloadBackup() async => null;

  @override
  Future<void> uploadBackup(String jsonContent) async {
    uploads++;
    hasBackup = true;
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

  /// A container wired for the sync controller: a fake Drive and an in-memory
  /// health logger (a real box write never completes inside the test's
  /// FakeAsync and deadlocks the runner).
  ProviderContainer syncContainerWith(
    AuthService auth,
    _FakeDriveService drive,
  ) {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        hiveDatabaseProvider.overrideWithValue(database),
        authServiceProvider.overrideWithValue(auth),
        driveServiceProvider.overrideWithValue(drive),
        appHealthLoggerProvider.overrideWithValue(AppHealthLogger(null)),
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
    await waitFor(
      () => container.read(authProvider).value?.email == 'silent@example.com',
    );
    expect(auth.silentCalls, greaterThanOrEqualTo(1));

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

  test(
    'a freshly synced session skips the platform restore entirely '
    '(no Credential Manager chooser on a multi-account device)',
    () async {
      // Regression for the device audit: on a phone with several Google
      // accounts, Play Services answers `attemptLightweightAuthentication`
      // with `ui invocation is needed`, so the chooser took focus on every cold
      // launch. A `last_synced` inside the trust window is proof the stored
      // credentials still work, so the platform must not be asked at all.
      AuthNotifier.resetRestoreGuard();
      await settingsBox.put('is_logged_in', true);
      await settingsBox.put('auth_user', <String, dynamic>{
        'id': 'user-6',
        'email': 'fresh@example.com',
        'displayName': null,
        'photoUrl': null,
      });
      await settingsBox.put(
        'last_synced',
        DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String(),
      );

      final _FakeAuthService auth = _FakeAuthService(
        silentUser: const AuthUser(id: 'user-6', email: 'fresh@example.com'),
      );
      final ProviderContainer container = containerWith(auth);

      // The cached session still renders immediately...
      expect(container.read(authProvider).value?.email, 'fresh@example.com');
      await pumpEventQueue();

      // ...but the platform was never asked, so no chooser can appear.
      expect(
        auth.silentCalls,
        0,
        reason: 'a session that synced recently is already known to work',
      );
      expect(container.read(authProvider).value?.email, 'fresh@example.com');
    },
  );

  test('a stale session still performs the restore', () async {
    AuthNotifier.resetRestoreGuard();
    await settingsBox.put('is_logged_in', true);
    await settingsBox.put('auth_user', <String, dynamic>{
      'id': 'user-7',
      'email': 'stale7@example.com',
      'displayName': null,
      'photoUrl': null,
    });
    // Older than AppConfig.sessionTrustWindow.
    await settingsBox.put(
      'last_synced',
      DateTime.now().toUtc().subtract(const Duration(days: 3)).toIso8601String(),
    );

    final _FakeAuthService auth = _FakeAuthService(
      silentUser: const AuthUser(id: 'user-7', email: 'refreshed@example.com'),
    );
    final ProviderContainer container = containerWith(auth);

    expect(container.read(authProvider).value?.email, 'stale7@example.com');
    await waitFor(
      () => container.read(authProvider).value?.email == 'refreshed@example.com',
    );

    expect(auth.silentCalls, 1);
  });

  test('a session that never synced still performs the restore', () async {
    AuthNotifier.resetRestoreGuard();
    await settingsBox.put('is_logged_in', true);
    await settingsBox.put('auth_user', <String, dynamic>{
      'id': 'user-8',
      'email': 'never8@example.com',
      'displayName': null,
      'photoUrl': null,
    });
    // No `last_synced` at all: absent evidence must not be read as trust.

    final _FakeAuthService auth = _FakeAuthService(
      silentUser: const AuthUser(id: 'user-8', email: 'never8@example.com'),
    );
    final ProviderContainer container = containerWith(auth);

    container.read(authProvider);
    await pumpEventQueue();

    expect(auth.silentCalls, 1);
  });

  test(
    'an automatic sync does not re-establish the session '
    '(the launch sync must not raise the credential chooser)',
    () async {
      // Regression for the device audit: the Home screen fires an automatic
      // "sync on open" and the app resumes fire a silent sync. Both used to
      // route into `_ensureSessionForDrive()`, which re-asked the platform and
      // put the Credential Manager chooser straight back on the cold-launch
      // path the trust window exists to protect.
      await settingsBox.put('is_logged_in', true);
      await settingsBox.put('auth_user', <String, dynamic>{
        'id': 'user-9',
        'email': 'auto9@example.com',
        'displayName': null,
        'photoUrl': null,
      });
      await settingsBox.put(
        'last_synced',
        DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String(),
      );

      final _FakeAuthService auth = _FakeAuthService(
        silentUser: const AuthUser(id: 'user-9', email: 'auto9@example.com'),
      );
      final _FakeDriveService drive = _FakeDriveService();
      final ProviderContainer container = syncContainerWith(auth, drive);

      // The automatic path: no user gesture behind it.
      await container.read(syncControllerProvider.notifier).syncNow();

      expect(
        auth.silentCalls,
        0,
        reason: 'an automatic sync must never ask the platform to re-authenticate',
      );
    },
  );

  test(
    'an explicit sync re-establishes the session before touching Drive',
    () async {
      // The other half of the contract: suppression must not break Drive sync.
      // A user-initiated sync restores the account first, so the backup
      // actually happens instead of reporting `skippedNotSignedIn`.
      await settingsBox.put('is_logged_in', true);
      await settingsBox.put('auth_user', <String, dynamic>{
        'id': 'user-10',
        'email': 'explicit10@example.com',
        'displayName': null,
        'photoUrl': null,
      });
      await settingsBox.put(
        'last_synced',
        DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String(),
      );

      final _FakeAuthService auth = _FakeAuthService(
        silentUser: const AuthUser(id: 'user-10', email: 'explicit10@example.com'),
      );
      final _FakeDriveService drive = _FakeDriveService();
      final ProviderContainer container = syncContainerWith(auth, drive);

      await container
          .read(syncControllerProvider.notifier)
          .syncNow(userInitiated: true);

      expect(auth.silentCalls, 1, reason: 'an explicit sync restores the account');
      expect(
        drive.uploads,
        1,
        reason: 'the backup must actually run, not report skippedNotSignedIn',
      );
    },
  );
}
