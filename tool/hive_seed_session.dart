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

import 'dart:io';

import 'package:hive_ce/hive.dart';

const String _isLoggedInKey = 'is_logged_in';
const String _authUserKey = 'auth_user';
const String _lastSyncedKey = 'last_synced';

/// Mirrors `AppConfig.sessionTrustWindow`.
const Duration _trustWindow = Duration(hours: 12);

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/hive_seed_session.dart <dir> [--stale]');
    exit(2);
  }
  final bool stale = args.contains('--stale');
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

  final DateTime now = DateTime.now().toUtc();
  final DateTime lastSynced = stale
      ? now.subtract(_trustWindow + const Duration(days: 1))
      : now.subtract(const Duration(minutes: 5));

  await box.put(_isLoggedInKey, true);
  await box.put(_authUserKey, <String, dynamic>{
    'id': 'audit-device-user',
    'email': 'audit-device@example.com',
    'displayName': null,
    'photoUrl': null,
  });
  await box.put(_lastSyncedKey, lastSynced.toIso8601String());

  stdout.writeln('seeded session (${stale ? 'STALE' : 'TRUSTED'}):');
  stdout.writeln('  $_isLoggedInKey = true');
  stdout.writeln('  $_authUserKey = audit-device@example.com');
  stdout.writeln('  $_lastSyncedKey = ${lastSynced.toIso8601String()}');
  stdout.writeln(
    '  age = ${now.difference(lastSynced).inMinutes} min '
    '(trust window = ${_trustWindow.inHours} h)',
  );

  await box.close();
}
