import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// SHA-256's digest size in bytes.
const int _sha256Length = 32;

/// PBKDF2-HMAC-SHA256 key derivation for the optional vault PIN.
///
/// Pure and synchronous on purpose: it owns no I/O, no clock and no state, so
/// it can be exercised directly in a unit test and moved onto a background
/// isolate by the caller.
///
/// **Why PBKDF2 at all for a 4-6 digit PIN.** A PIN has only 10^4-10^6 possible
/// values, so a *stolen hash* is cheap to brute-force no matter how many
/// iterations are used: stretching slows an offline attacker by a constant
/// factor, not by orders of magnitude. The real protection for the vault PIN is
/// that its record lives in the platform keystore (Android Keystore / iOS
/// Keychain), which an attacker cannot read without the device's hardware key.
/// Stretching is defence in depth on top of that: it makes a record that did
/// leak (a misconfigured backup, a rooted device) meaningfully more expensive to
/// attack, and it costs one 32-byte record.
///
/// The implementation is checked against the published PBKDF2-HMAC-SHA256
/// test vectors in `test/encrypted_vault_test.dart`.
class VaultPinHasher {
  const VaultPinHasher();

  /// Stretching rounds used when a PIN is stored.
  ///
  /// 100k rounds of HMAC-SHA256 takes roughly 0.4 s on a desktop VM and
  /// 1-1.5 s on a mid-range phone, which is why the data layer runs the
  /// derivation on a background isolate: the UI thread must never block on it.
  static const int defaultIterations = 100000;

  /// Length of the random per-PIN salt, in bytes.
  static const int saltLength = 16;

  /// Length of the derived key, in bytes (SHA-256 digest size).
  static const int keyLength = 32;

  /// Derives the stored hash for [pin] under [salt].
  ///
  /// [iterations] is a parameter so tests can use a cheap value; production
  /// always uses [defaultIterations].
  Uint8List derive({
    required String pin,
    required Uint8List salt,
    int iterations = defaultIterations,
  }) {
    return pbkdf2HmacSha256(
      password: utf8.encode(pin),
      salt: salt,
      iterations: iterations,
      keyLength: keyLength,
    );
  }

  /// Whether [pin] reproduces [expected] under [salt].
  ///
  /// The comparison is constant-time: it never returns early on the first
  /// differing byte, so a timing side channel cannot leak the stored hash one
  /// byte at a time.
  bool matches({
    required String pin,
    required Uint8List salt,
    required Uint8List expected,
    int iterations = defaultIterations,
  }) {
    final Uint8List actual = derive(
      pin: pin,
      salt: salt,
      iterations: iterations,
    );
    return constantTimeEquals(actual, expected);
  }
}

/// Compares two byte lists without leaking *where* they differ.
///
/// Returns `false` immediately for a length mismatch (the lengths are not a
/// secret), and otherwise folds every byte difference into an accumulator.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  int diff = 0;
  for (int i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// PBKDF2 (RFC 8018) with HMAC-SHA256 as the pseudo-random function.
///
/// `package:crypto` ships the HMAC primitive but not PBKDF2 itself, so the
/// construction is spelled out here: for each block `i`, `U1 = PRF(P, S || i)`
/// and `Ui = PRF(P, Ui-1)`, and the block is the XOR of `U1..Uc`.
///
/// Public so the construction can be checked against the published RFC 7914
/// vectors, including the multi-block case that a 32-byte vault key never
/// reaches on its own.
Uint8List pbkdf2HmacSha256({
  required List<int> password,
  required List<int> salt,
  required int iterations,
  required int keyLength,
}) {
  if (iterations <= 0) {
    throw ArgumentError.value(
      iterations,
      'iterations',
      'must be greater than zero',
    );
  }
  final Hmac hmac = Hmac(sha256, password);
  final int blocks = (keyLength + _sha256Length - 1) ~/ _sha256Length;
  final Uint8List output = Uint8List(blocks * _sha256Length);
  final Uint8List block = Uint8List(salt.length + 4);
  block.setRange(0, salt.length, salt);

  for (int i = 1; i <= blocks; i++) {
    // The block index is a big-endian 32-bit counter appended to the salt.
    block[salt.length] = (i >> 24) & 0xff;
    block[salt.length + 1] = (i >> 16) & 0xff;
    block[salt.length + 2] = (i >> 8) & 0xff;
    block[salt.length + 3] = i & 0xff;

    Uint8List u = Uint8List.fromList(hmac.convert(block).bytes);
    final Uint8List accumulator = Uint8List.fromList(u);
    for (int c = 1; c < iterations; c++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (int j = 0; j < _sha256Length; j++) {
        accumulator[j] ^= u[j];
      }
    }
    output.setRange(
      (i - 1) * _sha256Length,
      i * _sha256Length,
      accumulator,
    );
  }

  return Uint8List.sublistView(output, 0, keyLength);
}
