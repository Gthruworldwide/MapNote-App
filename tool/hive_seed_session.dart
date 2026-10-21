// Seeds a *trusted* Google session into a pulled MapNote `settings` Hive box.
//
// This is a **device-audit helper**, not app code. It reproduces the on-device
// state that the cold-launch auth check needs: a persisted session
// (`is_logged_in` + `auth_user`) whose `last_synced` is inside
// `AppConfig.sessionTrustWindow`, i.e. the branch where the launch skips
// `attemptLightweightAuthentication()` and the Credential Manager chooser must
// never appear.
//
// The keys and value shapes are exactly the ones `SettingsRepository` writes
// (`lib/src/data/local/settings_repository.dart`), so the app reads the seeded
// box as a normal, previously-signed-in device.
//
// Run with:
//   dart run tool/hive_seed_session.dart <dir-containing-settings.hive> [--stale]
//
// `--stale` writes a `last_synced` older than the trust window, which is the
// opposite branch: the app must then perform the full restore (and may raise
// the chooser). Use it to confirm the check can still *detect* a prompt.
//
// `--only-age` keeps the box's existing `auth_user` and `is_logged_in` and
// ages *only* `last_synced`. Use it when auditing a device that holds a real
// Google session: the default mode replaces the signed-in identity with the
// placeholder below, which leaves the device showing a fake account.

import 'dart:io';

import 'package:hive_ce/hive.dart';

const String _isLoggedInKey = 'is_logged_in';
const String _authUserKey = 'auth_user';
const String _lastSyncedKey = 'last_synced';

/// Mirrors `AppConfig.sessionTrustWindow`.
const Duration _trustWindow = Duration(hours: 12);

/// What a seeding run did, so the caller (and the tests) can assert on it.
class SeedOutcome {
  const SeedOutcome({
    required this.stale,
    required this.onlyAge,
    required this.lastSynced,
    required this.authUserPreserved,
  });

  /// Whether the session was aged past the trust window.
  final bool stale;

  /// Whether the box's own identity was kept instead of being replaced.
  final bool onlyAge;

  /// The timestamp that was written to `last_synced`.
  final DateTime lastSynced;

  /// Whether an existing `auth_user` survived the run untouched.
  final bool authUserPreserved;
}

/// Seeds (or re-ages) the session markers in a pulled `settings` box.
///
/// Exposed as a function so the "non-destructive" promise of [onlyAge] can be
/// pinned by a unit test instead of being a claim in a comment.
///
/// * [onlyAge] keeps the box's existing `is_logged_in` / `auth_user` and
///   touches **only** `last_synced`. It is the safe mode for auditing a device
///   that holds a real Google account.
/// * Without [onlyAge] the box is seeded with the placeholder identity, which
///   is what a fresh audit device needs.
Future<SeedOutcome> seedSession(
  Box<dynamic> box, {
  bool stale = false,
  bool onlyAge = false,
  DateTime? now,
}) async {
  final DateTime reference = (now ?? DateTime.now()).toUtc();
  final DateTime lastSynced = stale
      ? reference.subtract(_trustWindow + const Duration(days: 1))
      : reference.subtract(const Duration(minutes: 5));

  if (onlyAge) {
    if (!box.containsKey(_authUserKey)) {
      throw StateError(
        'box has no $_authUserKey; nothing to preserve -- run without '
        '--only-age to seed a placeholder session instead',
      );
    }
    await box.put(_lastSyncedKey, lastSynced.toIso8601String());
    return SeedOutcome(
      stale: stale,
      onlyAge: true,
      lastSynced: lastSynced,
      authUserPreserved: true,
    );
  }

  await box.put(_isLoggedInKey, true);
  await box.put(_authUserKey, <String, dynamic>{
    'id': 'audit-device-user',
    'email': 'audit-device@example.com',
    'displayName': null,
    'photoUrl': null,
  });
  await box.put(_lastSyncedKey, lastSynced.toIso8601String());
  return SeedOutcome(
    stale: stale,
    onlyAge: false,
    lastSynced: lastSynced,
    authUserPreserved: false,
  );
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/hive_seed_session.dart <dir> [--stale]');
    exit(2);
  }
  final bool stale = args.contains('--stale');
  final bool onlyAge = args.contains('--only-age');
  final String dir = args.firstWhere(
    (String a) => !a.startsWith('--'),
    orElse: () => '',
  );
  if (dir.isEmpty) {
    stderr.writeln('no directory given');
    exit(2);
  }

  Hive.init(dir);
  final Box<dynamic> box = await Hive.openBox<dynamic>('settings');

  final SeedOutcome outcome;
  try {
    outcome = await seedSession(box, stale: stale, onlyAge: onlyAge);
  } on StateError catch (error) {
    stderr.writeln(error.message);
    await box.close();
    exit(2);
  }

  stdout.writeln('seeded session (${outcome.stale ? 'STALE' : 'TRUSTED'}):');
  if (outcome.onlyAge) {
    stdout.writeln('  $_authUserKey = <preserved from the pulled box>');
  } else {
    stdout.writeln('  $_isLoggedInKey = true');
    stdout.writeln('  $_authUserKey = audit-device@example.com');
  }
  stdout.writeln('  $_lastSyncedKey = ${outcome.lastSynced.toIso8601String()}');
  stdout.writeln(
    '  age = ${DateTime.now().toUtc().difference(outcome.lastSynced).inMinutes}'
    ' min (trust window = ${_trustWindow.inHours} h)',
  );

  await box.close();
}
