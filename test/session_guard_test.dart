import 'package:flutter_test/flutter_test.dart';
import 'package:routenote/src/core/security/session_guard.dart';

/// In-memory [SessionTokenStore] — no platform keystore needed.
class _MemoryTokenStore implements SessionTokenStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  late _MemoryTokenStore store;
  late DateTime now;
  late SessionGuard guard;

  SessionGuard build({
    Duration inactivity = const Duration(minutes: 15),
    Duration backgroundGrace = const Duration(minutes: 2),
    Duration surfaceIdle = const Duration(minutes: 3),
    Duration surfaceThreshold = const Duration(minutes: 1),
  }) =>
      SessionGuard(
        tokenStore: store,
        inactivityTimeout: inactivity,
        backgroundGrace: backgroundGrace,
        surfaceIdleTimeout: surfaceIdle,
        surfaceIdleThreshold: surfaceThreshold,
        clock: () => now,
      );

  setUp(() {
    store = _MemoryTokenStore();
    now = DateTime.utc(2026, 1, 1);
    guard = build();
  });

  group('session lifecycle', () {
    test('starts with no session', () {
      expect(guard.isActive, isFalse);
      expect(guard.idleFor, isNull);
      expect(guard.endCount, 0);
    });

    test('beginSession opens one and persists an opaque token', () async {
      await guard.beginSession();

      expect(guard.isActive, isTrue);
      expect(guard.idleFor, Duration.zero);
      expect(await guard.hasPersistedSession(), isTrue);
      // The token must not identify anything: it is not a user id or an email.
      final String token = store.values[SessionGuard.defaultTokenKey]!;
      expect(token.contains('@'), isFalse);
      expect(token.contains('mapnote'), isFalse);
    });

    test('beginSession is idempotent and refreshes the clock', () async {
      await guard.beginSession();
      now = now.add(const Duration(minutes: 5));
      await guard.beginSession();

      expect(guard.isActive, isTrue);
      expect(guard.idleFor, Duration.zero);
    });

    test('endSession clears the token and notifies listeners', () async {
      await guard.beginSession();
      final List<SessionEndReason> reasons = <SessionEndReason>[];
      final subscription = guard.sessionEnds.listen(reasons.add);

      await guard.endSession(SessionEndReason.userInitiated);
      await Future<void>.delayed(Duration.zero);

      expect(guard.isActive, isFalse);
      expect(await guard.hasPersistedSession(), isFalse);
      expect(reasons, <SessionEndReason>[SessionEndReason.userInitiated]);
      expect(guard.endCount, 1);
      await subscription.cancel();
    });

    test('ending twice does not re-emit', () async {
      await guard.beginSession();
      await guard.endSession(SessionEndReason.userInitiated);

      await guard.endSession(SessionEndReason.inactivityTimeout);

      expect(guard.endCount, 1);
    });
  });

  group('inactivity timeout', () {
    test('a session survives inside the window and ends outside it', () async {
      await guard.beginSession();

      now = now.add(const Duration(minutes: 14));
      expect(await guard.tick(), isTrue);

      now = now.add(const Duration(minutes: 2));
      expect(await guard.tick(), isFalse);
      expect(guard.isActive, isFalse);
      expect(guard.endCount, 1);
    });

    test('activity resets the inactivity clock', () async {
      await guard.beginSession();

      for (int minute = 0; minute < 60; minute++) {
        now = now.add(const Duration(minutes: 1));
        guard.noteActivity();
      }
      expect(await guard.tick(), isTrue);
      expect(guard.isActive, isTrue);
    });

    test('tick on an inactive session is a no-op', () async {
      expect(await guard.tick(), isFalse);
      expect(guard.endCount, 0);
    });
  });

  group('background grace', () {
    test('a short app switch does not end the session', () async {
      await guard.beginSession();

      guard.onLifecycle(backgrounded: true);
      now = now.add(const Duration(seconds: 30));
      expect(await guard.tick(), isTrue);

      guard.onLifecycle(backgrounded: false);
      expect(guard.isActive, isTrue);
    });

    test('exceeding the grace period ends the session', () async {
      await guard.beginSession();

      guard.onLifecycle(backgrounded: true);
      now = now.add(const Duration(minutes: 3));

      expect(await guard.tick(), isFalse);
      expect(guard.isActive, isFalse);
      expect(guard.endCount, 1);
    });

    test('while backgrounded the inactivity clock does not also run', () async {
      // Long inactivity timeout, short grace: only the grace may fire.
      guard = build(
        inactivity: const Duration(hours: 1),
        backgroundGrace: const Duration(minutes: 1),
      );
      await guard.beginSession();

      guard.onLifecycle(backgrounded: true);
      now = now.add(const Duration(minutes: 2));

      expect(await guard.tick(), isFalse);
      expect(guard.endCount, 1);
    });

    test('returning to the foreground counts as activity', () async {
      await guard.beginSession();

      guard.onLifecycle(backgrounded: true);
      now = now.add(const Duration(seconds: 90));
      guard.onLifecycle(backgrounded: false);
      expect(guard.isActive, isTrue);

      // A further 10 min pass, but resume refreshed the clock at the 90 s mark,
      // so the session is still well inside the 15 min inactivity window.
      now = now.add(const Duration(minutes: 10));
      expect(await guard.tick(), isTrue);
    });

    test('an already-expired session is not revived by resuming', () async {
      await guard.beginSession();

      guard.onLifecycle(backgrounded: true);
      now = now.add(const Duration(minutes: 5));
      await guard.tick();
      expect(guard.isActive, isFalse);

      guard.onLifecycle(backgrounded: false);
      expect(guard.isActive, isFalse);
      expect(await guard.tick(), isFalse);
    });
  });

  group('hand-held vs surface-idle', () {
    test('micro-movement reports hand-held', () {
      guard.observeMovement(moving: true);
      expect(guard.interactionContext, InteractionContext.handHeld);
    });

    test('no movement for a sustained period reports surface-idle', () {
      guard.observeMovement(moving: true);
      now = now.add(const Duration(minutes: 2));
      guard.observeMovement(moving: false);

      expect(guard.interactionContext, InteractionContext.surfaceIdle);
    });

    test('movement immediately returns to hand-held', () {
      guard.observeMovement(moving: true);
      now = now.add(const Duration(minutes: 2));
      guard.observeMovement(moving: false);
      expect(guard.interactionContext, InteractionContext.surfaceIdle);

      guard.observeMovement(moving: true);
      expect(guard.interactionContext, InteractionContext.handHeld);
    });

    test('surface-idle uses the shorter timeout', () async {
      guard = build(
        inactivity: const Duration(minutes: 15),
        surfaceIdle: const Duration(minutes: 3),
        surfaceThreshold: const Duration(minutes: 1),
      );
      await guard.beginSession();
      guard.observeMovement(moving: true);

      // The device stops moving; the context flips to surface-idle.
      now = now.add(const Duration(minutes: 2));
      guard.observeMovement(moving: false);
      expect(guard.interactionContext, InteractionContext.surfaceIdle);

      // 4 min idle: past the 3 min surface timeout, well inside the 15 min one.
      now = now.add(const Duration(minutes: 4));
      expect(await guard.tick(), isFalse);
      expect(guard.isActive, isFalse);
    });

    test('an unmoved session from the start becomes surface-idle', () async {
      await guard.beginSession();

      // Never any movement reported, and enough time passes: a phone left open
      // on a desk must not sit unlocked on the long timeout.
      now = now.add(const Duration(minutes: 2));
      guard.observeMovement(moving: false);

      expect(guard.interactionContext, InteractionContext.surfaceIdle);
    });

    test('hand-held keeps the long timeout', () async {
      guard = build(
        inactivity: const Duration(minutes: 15),
        surfaceIdle: const Duration(minutes: 3),
      );
      await guard.beginSession();

      for (int i = 0; i < 4; i++) {
        guard.observeMovement(moving: true);
        guard.noteActivity();
        now = now.add(const Duration(minutes: 2));
      }

      expect(guard.interactionContext, InteractionContext.handHeld);
      expect(await guard.tick(), isTrue);
    });
  });

  group('no timers, no polling', () {
    test('tick is O(1) and safe to call in a loop', () async {
      await guard.beginSession();

      for (int i = 0; i < 1000; i++) {
        now = now.add(const Duration(seconds: 1));
        guard.noteActivity();
        expect(await guard.tick(), isTrue);
      }
      expect(guard.isActive, isTrue);
    });
  });

  group('device lock', () {
    test('ends the session immediately, with no grace period', () async {
      await guard.beginSession();
      final Future<SessionEndReason> ended = guard.sessionEnds.first;

      final bool didEnd = await guard.onDeviceLocked();

      expect(didEnd, isTrue);
      expect(guard.isActive, isFalse);
      expect(await ended, SessionEndReason.deviceLocked);
    });

    test('is a no-op when no session is open', () async {
      expect(await guard.onDeviceLocked(), isFalse);
      expect(guard.endCount, 0);
    });

    test('honours the lockOnDeviceLock preference when it is off', () async {
      guard = SessionGuard(
        tokenStore: store,
        lockOnDeviceLock: false,
        clock: () => now,
      );
      await guard.beginSession();

      expect(await guard.onDeviceLocked(), isFalse);
      // Still open: the softer background grace is what protects it instead.
      expect(guard.isActive, isTrue);
    });

    test('setLockOnDeviceLock toggles the behaviour at runtime', () async {
      await guard.beginSession();

      guard.setLockOnDeviceLock(false);
      expect(await guard.onDeviceLocked(), isFalse);
      expect(guard.isActive, isTrue);

      guard.setLockOnDeviceLock(true);
      expect(await guard.onDeviceLocked(), isTrue);
      expect(guard.isActive, isFalse);
    });
  });

  group('configurable inactivity timeout', () {
    test('setInactivityTimeout applies to the next tick', () async {
      await guard.beginSession();
      guard.setInactivityTimeout(const Duration(minutes: 2));

      now = now.add(const Duration(minutes: 3));
      expect(await guard.tick(), isFalse);
      expect(guard.isActive, isFalse);
    });

    test('shortening the window locks an already-idle session', () async {
      await guard.beginSession();
      now = now.add(const Duration(minutes: 2));

      // The old 15-minute window had not elapsed, but the new one has.
      guard.setInactivityTimeout(const Duration(minutes: 1));
      expect(await guard.tick(), isFalse);
    });

    test('rejects a non-positive timeout', () {
      expect(
        () => guard.setInactivityTimeout(Duration.zero),
        throwsArgumentError,
      );
    });
  });
}
