import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/features/saved_places/data/datasources/secret_store.dart';
import 'package:routenote/src/features/saved_places/data/datasources/vault_pin_store.dart';
import 'package:routenote/src/features/saved_places/data/repositories/keystore_vault_pin_verifier.dart';
import 'package:routenote/src/features/saved_places/domain/repositories/vault_repository.dart';
import 'package:routenote/src/features/saved_places/domain/services/vault_authenticator.dart';
import 'package:routenote/src/features/saved_places/domain/services/vault_pin_hasher.dart';
import 'package:routenote/src/features/saved_places/domain/services/vault_pin_verifier.dart';
import 'package:routenote/src/features/saved_places/domain/usecases/unlock_vault.dart';

/// Parses a hex string (spaces allowed) into bytes.
Uint8List _hex(String hex) {
  final String clean = hex.replaceAll(' ', '').replaceAll('\n', '').trim();
  final Uint8List out = Uint8List(clean.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Renders bytes as lowercase hex.
String _hexOf(List<int> bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

/// In-memory [SecretStore] so the PIN record can be exercised without the
/// platform keystore channel.
class _MemorySecretStore implements SecretStore {
  final Map<String, String> values = <String, String>{};

  /// When set, every call throws — used to pin the fail-closed behaviour.
  Object? failure;

  @override
  Future<String?> read(String key) async {
    final Object? error = failure;
    if (error != null) throw error;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    final Object? error = failure;
    if (error != null) throw error;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    final Object? error = failure;
    if (error != null) throw error;
    values.remove(key);
  }
}

/// Minimal vault repository: the PIN path only cares whether the box opened.
class _FakeVaultRepository implements VaultRepository {
  bool unlocked = false;
  int unlocks = 0;

  @override
  bool get isUnlocked => unlocked;

  @override
  Future<void> unlock() async {
    unlocked = true;
    unlocks++;
  }

  @override
  Future<void> lock() async => unlocked = false;

  @override
  Future<List<Place>> getAll() async => <Place>[];

  @override
  Future<Place?> getById(String id) async => null;

  @override
  Future<void> save(Place place) async {}

  @override
  Future<void> delete(String id) async {}
}

class _FakeVaultAuthenticator implements VaultAuthenticator {
  _FakeVaultAuthenticator(this.verification);

  final VaultVerification verification;
  int prompts = 0;

  @override
  Future<VaultVerification> verify({required String reason}) async {
    prompts++;
    return verification;
  }
}

void main() {
  // ---------------------------------------------------------------------------
  // PBKDF2-HMAC-SHA256 (RFC 8018), checked against the published vectors.
  // ---------------------------------------------------------------------------

  group('PBKDF2-HMAC-SHA256 matches the RFC 7914 section 11 vectors', () {
    test('P="passwd", S="salt", c=1, dkLen=64', () {
      final Uint8List dk = pbkdf2HmacSha256(
        password: utf8.encode('passwd'),
        salt: utf8.encode('salt'),
        iterations: 1,
        keyLength: 64,
      );

      expect(
        _hexOf(dk),
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc'
        '49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783',
      );
    });

    test('P="Password", S="NaCl", c=80000, dkLen=64', () {
      final Uint8List dk = pbkdf2HmacSha256(
        password: utf8.encode('Password'),
        salt: utf8.encode('NaCl'),
        iterations: 80000,
        keyLength: 64,
      );

      expect(
        _hexOf(dk),
        '4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56'
        'a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d',
      );
    });
  });

  group('PBKDF2 edge cases', () {
    test('a one-byte key is the first byte of the block', () {
      final Uint8List dk = pbkdf2HmacSha256(
        password: utf8.encode('passwd'),
        salt: utf8.encode('salt'),
        iterations: 1,
        keyLength: 1,
      );

      expect(dk, hasLength(1));
      expect(_hexOf(dk), '55');
    });

    test('a 32-byte key is the first block of the 64-byte vector', () {
      final Uint8List dk = pbkdf2HmacSha256(
        password: utf8.encode('passwd'),
        salt: utf8.encode('salt'),
        iterations: 1,
        keyLength: 32,
      );

      expect(
        _hexOf(dk),
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc',
      );
    });

    test('a key longer than one block concatenates the blocks', () {
      // 100 bytes is four blocks: the loop must not stop at the first one.
      final Uint8List dk = pbkdf2HmacSha256(
        password: utf8.encode('passwd'),
        salt: utf8.encode('salt'),
        iterations: 1,
        keyLength: 100,
      );

      expect(dk, hasLength(100));
      expect(
        _hexOf(dk),
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc'
        '49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783'
        'c294e850150390e1160c34d62e9665d659ae49d314510fc98274cc7968196810'
        '4b8f8923',
      );
    });

    test('an empty password is still derived', () {
      final Uint8List dk = pbkdf2HmacSha256(
        password: const <int>[],
        salt: utf8.encode('salt'),
        iterations: 1,
        keyLength: 32,
      );

      expect(
        _hexOf(dk),
        'f135c27993baf98773c5cdb40a5706ce6a345cde61b000a67858650cd6a324d7',
      );
    });

    test('a non-ASCII password is hashed as its UTF-8 bytes', () {
      final Uint8List dk = pbkdf2HmacSha256(
        password: utf8.encode('١٢٣٤'),
        salt: _hex('01020304'),
        iterations: 1000,
        keyLength: 32,
      );

      expect(
        _hexOf(dk),
        'e5dca56405eb09b8c52f15ccbaadf251406c4f151a8cd18a8a8362bc5c2126d8',
      );
    });

    test('the salt is actually used', () {
      final Uint8List a = pbkdf2HmacSha256(
        password: utf8.encode('passwd'),
        salt: utf8.encode('salt'),
        iterations: 2,
        keyLength: 32,
      );
      final Uint8List b = pbkdf2HmacSha256(
        password: utf8.encode('passwd'),
        salt: utf8.encode('pepper'),
        iterations: 2,
        keyLength: 32,
      );

      expect(a, isNot(b));
    });

    test('a non-positive round count is rejected', () {
      expect(
        () => pbkdf2HmacSha256(
          password: utf8.encode('passwd'),
          salt: utf8.encode('salt'),
          iterations: 0,
          keyLength: 32,
        ),
        throwsArgumentError,
      );
      expect(
        () => pbkdf2HmacSha256(
          password: utf8.encode('passwd'),
          salt: utf8.encode('salt'),
          iterations: -1,
          keyLength: 32,
        ),
        throwsArgumentError,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // The production hasher.
  // ---------------------------------------------------------------------------

  group('VaultPinHasher', () {
    const VaultPinHasher hasher = VaultPinHasher();

    test('derives the first block of the published vector', () {
      final Uint8List hash = hasher.derive(
        pin: 'passwd',
        salt: utf8.encode('salt'),
        iterations: 1,
      );

      expect(hash, hasLength(VaultPinHasher.keyLength));
      expect(
        _hexOf(hash),
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc',
      );
    });

    test('the same PIN and salt always derive the same hash', () {
      final Uint8List salt = _hex('000102030405060708090a0b0c0d0e0f');
      final Uint8List first = hasher.derive(pin: '1234', salt: salt, iterations: 2);
      final Uint8List second = hasher.derive(
        pin: '1234',
        salt: salt,
        iterations: 2,
      );

      expect(second, first);
    });

    test('a different PIN derives a different hash', () {
      final Uint8List salt = _hex('000102030405060708090a0b0c0d0e0f');
      final Uint8List a = hasher.derive(pin: '1234', salt: salt, iterations: 2);
      final Uint8List b = hasher.derive(pin: '1235', salt: salt, iterations: 2);

      expect(a, isNot(b));
    });

    test('matches accepts the right PIN and rejects a wrong one', () {
      final Uint8List salt = _hex('000102030405060708090a0b0c0d0e0f');
      final Uint8List hash = hasher.derive(pin: '1234', salt: salt, iterations: 2);

      expect(
        hasher.matches(pin: '1234', salt: salt, expected: hash, iterations: 2),
        isTrue,
      );
      expect(
        hasher.matches(pin: '9999', salt: salt, expected: hash, iterations: 2),
        isFalse,
      );
    });

    test('matches rejects a hash of a different length', () {
      final Uint8List salt = _hex('000102030405060708090a0b0c0d0e0f');
      final Uint8List hash = hasher.derive(pin: '1234', salt: salt, iterations: 2);

      expect(
        hasher.matches(
          pin: '1234',
          salt: salt,
          expected: hash.sublist(0, 16),
          iterations: 2,
        ),
        isFalse,
      );
    });
  });

  group('constantTimeEquals', () {
    test('equal byte lists match', () {
      expect(constantTimeEquals(<int>[1, 2, 3], <int>[1, 2, 3]), isTrue);
      expect(constantTimeEquals(const <int>[], const <int>[]), isTrue);
    });

    test('a differing byte fails the comparison', () {
      expect(constantTimeEquals(<int>[1, 2, 3], <int>[1, 2, 4]), isFalse);
      expect(constantTimeEquals(<int>[1, 2, 3], <int>[9, 2, 3]), isFalse);
    });

    test('a length mismatch fails the comparison', () {
      expect(constantTimeEquals(<int>[1, 2, 3], <int>[1, 2]), isFalse);
      expect(constantTimeEquals(const <int>[], <int>[1]), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // The PIN policy.
  // ---------------------------------------------------------------------------

  group('VaultPinPolicy', () {
    test('accepts a PIN of 4 to 12 digits', () {
      expect(VaultPinPolicy.isValid('1234'), isTrue);
      expect(VaultPinPolicy.isValid('123456789012'), isTrue);
    });

    test('rejects a PIN that is too short or too long', () {
      expect(VaultPinPolicy.isValid(''), isFalse);
      expect(VaultPinPolicy.isValid('123'), isFalse);
      expect(VaultPinPolicy.isValid('1234567890123'), isFalse);
    });

    test('rejects anything that is not a digit', () {
      expect(VaultPinPolicy.isValid('12a4'), isFalse);
      expect(VaultPinPolicy.isValid('12 4'), isFalse);
      expect(VaultPinPolicy.isValid('12-4'), isFalse);
      expect(VaultPinPolicy.isValid('abcd'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // The stored record.
  // ---------------------------------------------------------------------------

  group('VaultPinRecord', () {
    test('survives a round trip through its stored form', () {
      final VaultPinRecord record = VaultPinRecord(
        salt: _hex('000102030405060708090a0b0c0d0e0f'),
        hash: _hex('101112131415161718191a1b1c1d1e1f'),
        iterations: 100000,
        failedAttempts: 2,
        lockedUntil: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      final VaultPinRecord? restored = VaultPinRecord.fromMap(record.toMap());

      expect(restored, isNotNull);
      expect(restored!.salt, record.salt);
      expect(restored.hash, record.hash);
      expect(restored.iterations, record.iterations);
      expect(restored.failedAttempts, 2);
      expect(restored.lockedUntil, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('a record without a lockout round-trips as unlocked', () {
      final VaultPinRecord record = VaultPinRecord(
        salt: _hex('00ff'),
        hash: _hex('aa'),
        iterations: 10,
      );

      final VaultPinRecord? restored = VaultPinRecord.fromMap(record.toMap());

      expect(restored!.lockedUntil, isNull);
      expect(restored.failedAttempts, 0);
    });

    test('a malformed record is treated as absent, not as a failure', () {
      expect(VaultPinRecord.fromMap(null), isNull);
      expect(VaultPinRecord.fromMap('not a map'), isNull);
      expect(VaultPinRecord.fromMap(<String, dynamic>{}), isNull);
      expect(
        VaultPinRecord.fromMap(<String, dynamic>{
          'salt': 'not base64!',
          'hash': 'AA',
          'iterations': 10,
        }),
        isNull,
      );
      expect(
        VaultPinRecord.fromMap(<String, dynamic>{
          'salt': 'AA',
          'hash': 'AA',
          'iterations': 'ten',
        }),
        isNull,
      );
    });

    test('an empty salt or hash is rejected', () {
      expect(
        VaultPinRecord.fromMap(<String, dynamic>{
          'salt': '',
          'hash': 'AA',
          'iterations': 10,
        }),
        isNull,
      );
      expect(
        VaultPinRecord.fromMap(<String, dynamic>{
          'salt': 'AA',
          'hash': '',
          'iterations': 10,
        }),
        isNull,
      );
    });

    test('a non-positive round count is rejected', () {
      // A hash was never produced with zero rounds, and deriving with it
      // throws, so such a record must not reach the deriver.
      expect(
        VaultPinRecord.fromMap(<String, dynamic>{
          'salt': 'AA',
          'hash': 'AA',
          'iterations': 0,
        }),
        isNull,
      );
      expect(
        VaultPinRecord.fromMap(<String, dynamic>{
          'salt': 'AA',
          'hash': 'AA',
          'iterations': -5,
        }),
        isNull,
      );
    });

    test('copyWith can set and clear the lockout', () {
      final DateTime deadline = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final VaultPinRecord base = VaultPinRecord(
        salt: _hex('00ff'),
        hash: _hex('aa'),
        iterations: 10,
      );

      final VaultPinRecord locked = base.copyWith(
        failedAttempts: 3,
        lockedUntil: deadline,
      );
      expect(locked.lockedUntil, deadline);
      expect(locked.failedAttempts, 3);

      final VaultPinRecord cleared = locked.copyWith(clearLockout: true);
      expect(cleared.lockedUntil, isNull);
      expect(cleared.failedAttempts, 3, reason: 'the counter is left alone');
    });

    test('the stored form never contains the PIN itself', () {
      final VaultPinRecord record = VaultPinRecord(
        salt: _hex('000102030405060708090a0b0c0d0e0f'),
        hash: _hex('101112131415161718191a1b1c1d1e1f'),
        iterations: 100000,
      );

      final String encoded = jsonEncode(record.toMap());

      expect(encoded, isNot(contains('1234')));
      expect(record.toMap().containsKey('pin'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // The keystore-backed store.
  // ---------------------------------------------------------------------------

  group('VaultPinStore', () {
    const String keyName = 'routenote.vault.pin';
    late _MemorySecretStore secrets;
    late VaultPinStore store;

    setUp(() {
      secrets = _MemorySecretStore();
      store = VaultPinStore(secrets);
    });

    test('reads nothing before a PIN is stored', () async {
      expect(await store.read(), isNull);
    });

    test('writes and reads a record back', () async {
      final VaultPinRecord record = VaultPinRecord(
        salt: _hex('000102030405060708090a0b0c0d0e0f'),
        hash: _hex('101112131415161718191a1b1c1d1e1f'),
        iterations: 100000,
      );

      await store.write(record);

      expect(secrets.values.containsKey(keyName), isTrue);
      final VaultPinRecord? restored = await store.read();
      expect(restored!.salt, record.salt);
      expect(restored.hash, record.hash);
      expect(restored.iterations, record.iterations);
    });

    test('deletes the record', () async {
      await store.write(
        VaultPinRecord(salt: _hex('00'), hash: _hex('aa'), iterations: 10),
      );

      await store.delete();

      expect(await store.read(), isNull);
    });

    test('a corrupt stored value reads as absent, not as a failure', () async {
      secrets.values[keyName] = 'this is not json';

      expect(await store.read(), isNull);
    });

    test('a stored value that is not a record reads as absent', () async {
      secrets.values[keyName] = jsonEncode(<String, dynamic>{'nope': true});

      expect(await store.read(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // The verifier and its anti-guessing policy.
  // ---------------------------------------------------------------------------

  group('KeystoreVaultPinVerifier', () {
    late _MemorySecretStore secrets;
    late VaultPinStore store;
    late DateTime now;
    late KeystoreVaultPinVerifier verifier;

    setUp(() {
      secrets = _MemorySecretStore();
      store = VaultPinStore(secrets);
      now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      verifier = KeystoreVaultPinVerifier(
        store: store,
        deriver: inlineVaultPinDeriver,
        clock: () => now,
        iterations: 2,
      );
    });

    test('reports no PIN before one is set', () async {
      expect(await verifier.hasPin(), isFalse);
      expect(await verifier.check('1234'), VaultPinCheck.notSet);
    });

    test('a correct PIN matches', () async {
      await verifier.setPin('1234');

      expect(await verifier.hasPin(), isTrue);
      expect(await verifier.check('1234'), VaultPinCheck.matched);
    });

    test('a wrong PIN does not match', () async {
      await verifier.setPin('1234');

      expect(await verifier.check('9999'), VaultPinCheck.notMatched);
    });

    test('the PIN is never stored in the clear', () async {
      await verifier.setPin('1234');

      final String raw = secrets.values['routenote.vault.pin']!;
      expect(raw, isNot(contains('1234')));
    });

    test('each PIN gets a fresh random salt', () async {
      await verifier.setPin('1234');
      final VaultPinRecord first = (await store.read())!;

      await verifier.setPin('1234');
      final VaultPinRecord second = (await store.read())!;

      expect(second.salt, isNot(first.salt));
      expect(second.hash, isNot(first.hash));
      expect(second.salt, hasLength(VaultPinHasher.saltLength));
    });

    test('a correct PIN clears the failed-attempt counter', () async {
      await verifier.setPin('1234');
      await verifier.check('0000');
      await verifier.check('0001');
      expect((await store.read())!.failedAttempts, 2);

      expect(await verifier.check('1234'), VaultPinCheck.matched);
      expect((await store.read())!.failedAttempts, 0);
    });

    test('the PIN locks out after the maximum number of wrong attempts', () async {
      await verifier.setPin('1234');

      for (int i = 0; i < 4; i++) {
        expect(await verifier.check('0000'), VaultPinCheck.notMatched);
      }
      expect(await verifier.check('0000'), VaultPinCheck.lockedOut);
    });

    test('a lockout rejects even the correct PIN', () async {
      await verifier.setPin('1234');
      for (int i = 0; i < 5; i++) {
        await verifier.check('0000');
      }

      expect(await verifier.check('1234'), VaultPinCheck.lockedOut);
    });

    test('the lockout expires', () async {
      await verifier.setPin('1234');
      for (int i = 0; i < 5; i++) {
        await verifier.check('0000');
      }
      expect(await verifier.lockoutRemaining(), greaterThan(Duration.zero));

      now = now.add(const Duration(minutes: 6));

      expect(await verifier.lockoutRemaining(), Duration.zero);
      expect(await verifier.check('1234'), VaultPinCheck.matched);
    });

    test('the lockout survives a restart', () async {
      await verifier.setPin('1234');
      for (int i = 0; i < 5; i++) {
        await verifier.check('0000');
      }

      // A fresh verifier reads the same persisted record, so restarting the
      // app does not hand an attacker a fresh set of guesses.
      final KeystoreVaultPinVerifier restarted = KeystoreVaultPinVerifier(
        store: store,
        deriver: inlineVaultPinDeriver,
        clock: () => now,
        iterations: 2,
      );

      expect(await restarted.check('1234'), VaultPinCheck.lockedOut);
    });

    test('setting a new PIN clears the lockout', () async {
      await verifier.setPin('1234');
      for (int i = 0; i < 5; i++) {
        await verifier.check('0000');
      }
      expect(await verifier.check('1234'), VaultPinCheck.lockedOut);

      await verifier.setPin('5678');

      expect(await verifier.check('5678'), VaultPinCheck.matched);
      expect((await store.read())!.lockedUntil, isNull);
    });

    test('clearing the PIN removes it entirely', () async {
      await verifier.setPin('1234');

      await verifier.clearPin();

      expect(await verifier.hasPin(), isFalse);
      expect(await verifier.check('1234'), VaultPinCheck.notSet);
    });

    test('a keystore that cannot be read reports no PIN and unlocks nothing', () async {
      await verifier.setPin('1234');
      secrets.failure = StateError('keystore unavailable');

      expect(await verifier.hasPin(), isFalse);
      expect(await verifier.check('1234'), VaultPinCheck.notSet);
    });

    test('a derivation that fails is reported as "no PIN", never as a match', () async {
      await verifier.setPin('1234');

      final KeystoreVaultPinVerifier broken = KeystoreVaultPinVerifier(
        store: store,
        deriver: ({
          required String pin,
          required Uint8List salt,
          required int iterations,
        }) async => throw StateError('isolate died'),
        clock: () => now,
        iterations: 2,
      );

      expect(await broken.check('1234'), VaultPinCheck.notSet);
    });

    test('the isolated deriver agrees with the inline one', () async {
      final Uint8List salt = _hex('000102030405060708090a0b0c0d0e0f');

      final Uint8List inline = await inlineVaultPinDeriver(
        pin: '1234',
        salt: salt,
        iterations: 2,
      );
      final Uint8List isolated = await isolatedVaultPinDeriver(
        pin: '1234',
        salt: salt,
        iterations: 2,
      );

      expect(isolated, inline);
    });
  });

  // ---------------------------------------------------------------------------
  // The unlock flow.
  // ---------------------------------------------------------------------------

  group('UnlockVault.unlockWithPin', () {
    late _MemorySecretStore secrets;
    late VaultPinStore store;
    late _FakeVaultRepository repository;
    late KeystoreVaultPinVerifier verifier;

    setUp(() {
      secrets = _MemorySecretStore();
      store = VaultPinStore(secrets);
      repository = _FakeVaultRepository();
      verifier = KeystoreVaultPinVerifier(
        store: store,
        deriver: inlineVaultPinDeriver,
        iterations: 2,
      );
    });

    test('a correct PIN opens the vault', () async {
      await verifier.setPin('1234');
      final UnlockVault unlock = UnlockVault(
        _FakeVaultAuthenticator(VaultVerification.verified),
        repository,
        verifier,
      );

      expect(await unlock.unlockWithPin('1234'), VaultUnlockResult.unlocked);
      expect(repository.isUnlocked, isTrue);
    });

    test('a wrong PIN leaves the vault locked', () async {
      await verifier.setPin('1234');
      final UnlockVault unlock = UnlockVault(
        _FakeVaultAuthenticator(VaultVerification.verified),
        repository,
        verifier,
      );

      expect(await unlock.unlockWithPin('9999'), VaultUnlockResult.pinRejected);
      expect(repository.isUnlocked, isFalse);
    });

    test('a locked-out PIN reports the lockout', () async {
      await verifier.setPin('1234');
      final UnlockVault unlock = UnlockVault(
        _FakeVaultAuthenticator(VaultVerification.verified),
        repository,
        verifier,
      );
      for (int i = 0; i < 5; i++) {
        await unlock.unlockWithPin('0000');
      }

      expect(await unlock.unlockWithPin('1234'), VaultUnlockResult.pinLockedOut);
      expect(repository.isUnlocked, isFalse);
    });

    test('a missing PIN leaves the vault locked', () async {
      final UnlockVault unlock = UnlockVault(
        _FakeVaultAuthenticator(VaultVerification.verified),
        repository,
        verifier,
      );

      expect(await unlock.unlockWithPin('1234'), VaultUnlockResult.pinRejected);
      expect(repository.isUnlocked, isFalse);
    });

    test('without a verifier the PIN path is closed, not open', () async {
      final UnlockVault unlock = UnlockVault(
        _FakeVaultAuthenticator(VaultVerification.verified),
        repository,
      );

      expect(await unlock.unlockWithPin('1234'), VaultUnlockResult.pinRejected);
      expect(repository.isUnlocked, isFalse);
    });

    test('the PIN path never prompts for biometrics', () async {
      await verifier.setPin('1234');
      final _FakeVaultAuthenticator authenticator = _FakeVaultAuthenticator(
        VaultVerification.verified,
      );
      final UnlockVault unlock = UnlockVault(
        authenticator,
        repository,
        verifier,
      );

      await unlock.unlockWithPin('1234');

      expect(authenticator.prompts, 0);
    });

    test('an already-open vault stays open', () async {
      await verifier.setPin('1234');
      final UnlockVault unlock = UnlockVault(
        _FakeVaultAuthenticator(VaultVerification.verified),
        repository,
        verifier,
      );
      await unlock.unlockWithPin('1234');

      expect(await unlock.unlockWithPin('9999'), VaultUnlockResult.unlocked);
      expect(repository.unlocks, 1);
    });
  });
}
