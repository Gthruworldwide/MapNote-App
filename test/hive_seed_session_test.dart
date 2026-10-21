// Regression tests for the device-audit session seeder
// (`tool/hive_seed_session.dart`).
//
// The `--only-age` mode exists so the cold-launch auth audit can be run on a
// device that holds a *real* Google session: it must age only the trust
// evidence (`last_synced`) and leave the signed-in identity exactly where it
// was. If it ever started overwriting `auth_user`, the audit would leave the
// device showing a placeholder account -- so that promise is pinned here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

// Relative import: `tool/` sits outside `lib/`, so it is not reachable
// through a `package:routenote/...` URI.
import '../tool/hive_seed_session.dart';

void main() {
  late Directory tempDir;
  late Box<dynamic> box;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('routenote_seed_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<dynamic>('settings');
  });

  tearDown(() async {
    await box.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// A box that looks like a device which has really signed in.
  Future<void> seedRealSession() async {
    await box.put('is_logged_in', true);
    await box.put('auth_user', <String, dynamic>{
      'id': 'real-user-id',
      'email': 'real.user@example.com',
      'displayName': 'Real User',
      'photoUrl': null,
    });
    await box.put(
      'last_synced',
      DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String(),
    );
  }

  group('seedSession', () {
    test('only-age preserves the real identity and ages only last_synced',
        () async {
      await seedRealSession();

      final SeedOutcome outcome = await seedSession(box, stale: true, onlyAge: true);

      expect(outcome.onlyAge, isTrue);
      expect(outcome.authUserPreserved, isTrue);

      // The identity is untouched...
      expect(box.get('is_logged_in'), isTrue);
      final Map<dynamic, dynamic> user = box.get('auth_user') as Map<dynamic, dynamic>;
      expect(user['id'], 'real-user-id');
      expect(user['email'], 'real.user@example.com');

      // ...and only the trust evidence moved.
      final DateTime lastSynced =
          DateTime.parse(box.get('last_synced') as String).toUtc();
      expect(lastSynced.isBefore(DateTime.now().toUtc()), isTrue);
      expect(lastSynced.difference(DateTime.now().toUtc()).inHours.abs(),
          greaterThan(12));
    });

    test('only-age refuses a box that has no session to preserve', () async {
      // Nothing to preserve means the request is a mistake -- seeding a
      // placeholder instead would silently change what the audit measures.
      await expectLater(
        seedSession(box, stale: true, onlyAge: true),
        throwsA(isA<StateError>()),
      );
      expect(box.containsKey('auth_user'), isFalse);
      expect(box.containsKey('last_synced'), isFalse);
    });

    test('the default mode seeds a placeholder session', () async {
      final SeedOutcome outcome = await seedSession(box);

      expect(outcome.onlyAge, isFalse);
      expect(outcome.authUserPreserved, isFalse);
      expect(box.get('is_logged_in'), isTrue);
      final Map<dynamic, dynamic> user = box.get('auth_user') as Map<dynamic, dynamic>;
      expect(user['email'], 'audit-device@example.com');
    });

    test('the trusted branch writes a timestamp inside the trust window',
        () async {
      final DateTime now = DateTime.utc(2026, 10, 21, 12);
      final SeedOutcome outcome = await seedSession(box, now: now);

      expect(outcome.stale, isFalse);
      expect(
        now.difference(outcome.lastSynced).inMinutes,
        lessThan(12 * 60),
        reason: 'a trusted session must be inside AppConfig.sessionTrustWindow',
      );
    });

    test('the stale branch writes a timestamp outside the trust window',
        () async {
      final DateTime now = DateTime.utc(2026, 10, 21, 12);
      final SeedOutcome outcome = await seedSession(box, stale: true, now: now);

      expect(outcome.stale, isTrue);
      expect(
        now.difference(outcome.lastSynced).inHours,
        greaterThan(12),
        reason: 'a stale session must be outside AppConfig.sessionTrustWindow',
      );
    });
  });
}
