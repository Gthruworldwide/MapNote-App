import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../domain/services/vault_pin_hasher.dart';
import '../../domain/services/vault_pin_verifier.dart';
import '../datasources/vault_pin_store.dart';

/// Derives the stored hash for a PIN.
///
/// Injectable so a test can run the derivation inline, while production moves
/// it off the UI thread (see [isolatedVaultPinDeriver]).
typedef VaultPinDeriver =
    Future<Uint8List> Function({
      required String pin,
      required Uint8List salt,
      required int iterations,
    });

/// The request handed to the background isolate.
class _PinDeriveRequest {
  const _PinDeriveRequest(this.pin, this.salt, this.iterations);

  final String pin;
  final Uint8List salt;
  final int iterations;
}

/// The isolate entry point. Must be a top-level function so it can be sent to
/// another isolate.
Uint8List _deriveHash(_PinDeriveRequest request) {
  return const VaultPinHasher().derive(
    pin: request.pin,
    salt: request.salt,
    iterations: request.iterations,
  );
}

/// Derives the hash on a background isolate.
///
/// PBKDF2 at [VaultPinHasher.defaultIterations] rounds takes the better part
/// of a second on a phone. Running it on the UI isolate would freeze the
/// unlock screen mid-animation, so the work is pushed to a worker isolate and
/// awaited.
Future<Uint8List> isolatedVaultPinDeriver({
  required String pin,
  required Uint8List salt,
  required int iterations,
}) {
  return compute(
    _deriveHash,
    _PinDeriveRequest(pin, salt, iterations),
    debugLabel: 'vault-pin-derive',
  );
}

/// Derives the hash inline, on the calling isolate.
///
/// Used by tests, where the round trip through an isolate would only add
/// latency.
Future<Uint8List> inlineVaultPinDeriver({
  required String pin,
  required Uint8List salt,
  required int iterations,
}) async {
  return const VaultPinHasher().derive(
    pin: pin,
    salt: salt,
    iterations: iterations,
  );
}

/// [VaultPinVerifier] backed by the platform keystore.
///
/// Holds the anti-guessing policy: after [maxAttempts] wrong guesses the PIN
/// is unusable for [lockoutDuration]. Both the counter and the lockout
/// deadline are persisted, so restarting the app does not hand an attacker a
/// fresh set of guesses.
class KeystoreVaultPinVerifier implements VaultPinVerifier {
  KeystoreVaultPinVerifier({
    required this.store,
    this.deriver = isolatedVaultPinDeriver,
    DateTime Function()? clock,
    this.iterations = VaultPinHasher.defaultIterations,
    this.maxAttempts = 5,
    this.lockoutDuration = const Duration(minutes: 5),
  }) : clock = clock ?? DateTime.now;

  /// Where the PIN record is persisted.
  final VaultPinStore store;

  /// How the hash is derived. Off the UI thread in production.
  final VaultPinDeriver deriver;

  /// The clock, injected so a test can step time without sleeping.
  final DateTime Function() clock;

  /// How many PBKDF2 rounds a stored PIN uses.
  final int iterations;

  /// How many wrong guesses are allowed before the PIN locks out.
  final int maxAttempts;

  /// How long the PIN stays locked out.
  final Duration lockoutDuration;

  @override
  Future<bool> hasPin() async {
    try {
      return await store.read() != null;
    } catch (_) {
      // A keystore that cannot answer means "no PIN is known". It must never
      // crash the unlock path.
      return false;
    }
  }

  @override
  Future<VaultPinCheck> check(String pin) async {
    VaultPinRecord? record;
    try {
      record = await store.read();
    } catch (_) {
      // Fail closed: a keystore that cannot be read must not unlock anything.
      return VaultPinCheck.notSet;
    }
    if (record == null) return VaultPinCheck.notSet;

    final DateTime now = clock();
    final DateTime? lockedUntil = record.lockedUntil;
    if (lockedUntil != null && now.isBefore(lockedUntil)) {
      return VaultPinCheck.lockedOut;
    }

    final Uint8List derived;
    try {
      derived = await deriver(
        pin: pin,
        salt: record.salt,
        iterations: record.iterations,
      );
    } catch (_) {
      // A derivation that cannot run (a worker isolate that failed to spawn,
      // a record the hasher rejects) is not a wrong PIN: it is "no PIN is
      // known". Fail closed so the vault stays locked and the contract that
      // `check` never throws holds.
      return VaultPinCheck.notSet;
    }

    if (constantTimeEquals(derived, record.hash)) {
      // A correct PIN clears the counter: the user is back on the good path.
      await store.write(record.copyWith(failedAttempts: 0, clearLockout: true));
      return VaultPinCheck.matched;
    }

    final int attempts = record.failedAttempts + 1;
    final bool locks = attempts >= maxAttempts;
    await store.write(
      record.copyWith(
        failedAttempts: locks ? 0 : attempts,
        lockedUntil: locks ? now.add(lockoutDuration) : null,
        clearLockout: !locks,
      ),
    );
    return locks ? VaultPinCheck.lockedOut : VaultPinCheck.notMatched;
  }

  @override
  Future<void> setPin(String pin) async {
    final Uint8List salt = _randomSalt();
    final Uint8List hash = await deriver(
      pin: pin,
      salt: salt,
      iterations: iterations,
    );
    await store.write(
      VaultPinRecord(salt: salt, hash: hash, iterations: iterations),
    );
  }

  @override
  Future<void> clearPin() => store.delete();

  @override
  Future<Duration> lockoutRemaining() async {
    final VaultPinRecord? record = await store.read();
    final DateTime? lockedUntil = record?.lockedUntil;
    if (record == null || lockedUntil == null) return Duration.zero;
    final Duration remaining = lockedUntil.difference(clock());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// A cryptographically random salt.
  ///
  /// [Random.secure] is the platform CSPRNG; the salt does not need to be
  /// secret, only unpredictable, but a predictable salt would let an attacker
  /// pre-compute the whole PIN space.
  Uint8List _randomSalt() {
    final Random random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(VaultPinHasher.saltLength, (_) => random.nextInt(256)),
    );
  }
}
