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
/// is unusable for a progressive lockout period. Both the counter and the
/// lockout deadline are persisted, so restarting the app does not hand an
/// attacker a fresh set of guesses. Each consecutive failure increases the
/// lockout delay exponentially.
class KeystoreVaultPinVerifier implements VaultPinVerifier {
  static const int defaultMaxAttempts = 5;
  static const Duration defaultBaseLockoutDelay = Duration(seconds: 30);
  static const double defaultLockoutMultiplier = 2.0;
  static const Duration maximumLockout = Duration(minutes: 15);

  KeystoreVaultPinVerifier({
    required this.store,
    this.deriver = isolatedVaultPinDeriver,
    DateTime Function()? clock,
    this.iterations = VaultPinHasher.defaultIterations,
    this.maxAttempts = defaultMaxAttempts,
    this.baseLockoutDelay = defaultBaseLockoutDelay,
    this.lockoutMultiplier = defaultLockoutMultiplier,
  }) : clock = clock ?? DateTime.now;

  /// Where the PIN record is persisted.
  final VaultPinStore store;

  /// How the hash is derived. Off the UI thread in production.
  final VaultPinDeriver deriver;

  /// The clock, injected so a test can step time without sleeping.
  final DateTime Function() clock;

  /// How many PBKDF2 rounds a stored PIN uses.
  final int iterations;

  /// Counter and deadline are persisted, and every read-modify-write runs
  /// through a single per-instance queue so overlapping checks cannot both
  /// read the same pre-failure record and collapse two guesses into one.
  Future<void> _tail = Future<void>.value();

  /// How many wrong guesses trigger the maximum lockout. Earlier failures use
  /// the progressive ladder and the counter is only reset by a correct PIN or
  /// by replacing/removing the PIN.
  final int maxAttempts;

  /// The base lockout delay. Each consecutive failure multiplies this by
  /// [lockoutMultiplier], so the delay grows progressively.
  final Duration baseLockoutDelay;

  /// The multiplier applied to the lockout delay after each consecutive failure.
  final double lockoutMultiplier;

  @override
  Future<bool> hasPin() => _serialized(() async {
        try {
          return await store.read() != null;
        } catch (_) {
          // A keystore that cannot answer means "no PIN is known". It must never
          // crash the unlock path.
          return false;
        }
      });

  @override
  Future<VaultPinCheck> check(String pin) => _serialized(() async {
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
      // A correct PIN is the only thing (besides replacing the PIN) that
      // clears both the counter and any stale deadline.
      await store.write(
        record.copyWith(failedAttempts: 0, clearLockout: true),
      );
      return VaultPinCheck.matched;
    }

    // Wrong PIN: every failure increments the persisted counter. The ladder is
    // 0, 30 s, 1 m, 2 m, then a 15-minute cap from the fifth failure onward.
    // Expiring a deadline never resets the counter.
    final int attempts = record.failedAttempts + 1;
    final Duration delay = _lockoutDelayFor(attempts);
    await store.write(
      record.copyWith(
        failedAttempts: attempts,
        lockedUntil: delay > Duration.zero ? now.add(delay) : null,
        clearLockout: delay <= Duration.zero,
      ),
    );
    return attempts >= maxAttempts
        ? VaultPinCheck.lockedOut
        : VaultPinCheck.notMatched;
  });

  @override
  Future<void> setPin(String pin) => _serialized(() async {
        final Uint8List salt = _randomSalt();
        final Uint8List hash = await deriver(
          pin: pin,
          salt: salt,
          iterations: iterations,
        );
        await store.write(
          VaultPinRecord(salt: salt, hash: hash, iterations: iterations),
        );
      });

  @override
  Future<void> clearPin() => _serialized(store.delete);

  @override
  Future<Duration> lockoutRemaining() => _serialized(() async {
        final VaultPinRecord? record = await store.read();
        final DateTime? lockedUntil = record?.lockedUntil;
        if (record == null || lockedUntil == null) return Duration.zero;
        final Duration remaining = lockedUntil.difference(clock());
        return remaining.isNegative ? Duration.zero : remaining;
      });

  /// Serializes read-modify-write sequences on this verifier. The app uses a
  /// singleton provider, so overlapping calls cannot bypass the failure limit.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final Future<T> result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Duration _lockoutDelayFor(int attempts) {
    if (attempts < 2) return Duration.zero;
    if (attempts >= maxAttempts) return maximumLockout;

    final double factor = pow(lockoutMultiplier, attempts - 2).toDouble();
    final Duration progressive = Duration(
      milliseconds: (baseLockoutDelay.inMilliseconds * factor).round(),
    );
    return progressive > maximumLockout ? maximumLockout : progressive;
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
