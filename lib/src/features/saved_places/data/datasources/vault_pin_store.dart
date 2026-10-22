import 'dart:convert';
import 'dart:typed_data';

import 'secret_store.dart';

/// The stored record for the optional vault PIN.
///
/// Holds a random [salt], the PBKDF2 [hash] of the PIN, the stretching
/// [iterations] used, and the anti-guessing state ([failedAttempts] and
/// [lockedUntil]).
///
/// The PIN itself is never stored, and neither is anything about the user's
/// places: this record only ever describes the PIN.
class VaultPinRecord {
  const VaultPinRecord({
    required this.salt,
    required this.hash,
    required this.iterations,
    this.failedAttempts = 0,
    this.lockedUntil,
  });

  /// The random per-PIN salt.
  final Uint8List salt;

  /// The derived key.
  final Uint8List hash;

  /// How many PBKDF2 rounds produced [hash].
  final int iterations;

  /// How many wrong attempts have been made since the last success.
  final int failedAttempts;

  /// When the PIN becomes usable again, or `null` when it is not locked out.
  final DateTime? lockedUntil;

  /// A copy of this record with the anti-guessing state replaced.
  ///
  /// [clearLockout] exists because a `null` [lockedUntil] cannot be told apart
  /// from "leave it alone" in a plain nullable parameter: clearing the lockout
  /// (a correct PIN) and setting one (a wrong PIN) must both be expressible.
  VaultPinRecord copyWith({
    int? failedAttempts,
    DateTime? lockedUntil,
    bool clearLockout = false,
  }) {
    return VaultPinRecord(
      salt: salt,
      hash: hash,
      iterations: iterations,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockedUntil: clearLockout ? null : (lockedUntil ?? this.lockedUntil),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'salt': base64UrlEncode(salt),
      'hash': base64UrlEncode(hash),
      'iterations': iterations,
      'failedAttempts': failedAttempts,
      'lockedUntil': lockedUntil?.millisecondsSinceEpoch,
    };
  }

  /// Rebuilds a record from its stored form, or `null` when the stored value is
  /// missing or malformed.
  ///
  /// A corrupt record is treated as *absent* rather than as a failure: the
  /// worst outcome would be a vault the user can never unlock again.
  static VaultPinRecord? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final Object? salt = raw['salt'];
    final Object? hash = raw['hash'];
    final Object? iterations = raw['iterations'];
    if (salt is! String || hash is! String || iterations is! num) return null;
    // A non-positive round count cannot describe a hash that was ever
    // produced, and deriving with it throws. Reject the record outright so a
    // corrupt value degrades to "no PIN" instead of breaking the unlock path.
    if (iterations.toInt() <= 0) return null;

    final Uint8List saltBytes;
    final Uint8List hashBytes;
    try {
      saltBytes = base64Url.decode(salt);
      hashBytes = base64Url.decode(hash);
    } on FormatException {
      return null;
    }
    if (saltBytes.isEmpty || hashBytes.isEmpty) return null;

    final Object? attempts = raw['failedAttempts'];
    final Object? lockedUntil = raw['lockedUntil'];
    return VaultPinRecord(
      salt: saltBytes,
      hash: hashBytes,
      iterations: iterations.toInt(),
      failedAttempts: attempts is num ? attempts.toInt() : 0,
      lockedUntil: lockedUntil is num
          ? DateTime.fromMillisecondsSinceEpoch(lockedUntil.toInt())
          : null,
    );
  }
}

/// Persists the vault PIN record in the platform keystore.
///
/// This is the *only* place the PIN record touches persistent storage, and it
/// writes through the [SecretStore] port, so the platform channel never leaks
/// into the vault's rules and a test can run against an in-memory store.
class VaultPinStore {
  const VaultPinStore(this._store, {this.keyName = 'routenote.vault.pin'});

  /// The keystore-backed secret store (Android Keystore / iOS Keychain).
  final SecretStore _store;

  /// Keystore entry name. Changing it orphans the existing PIN, so it is part
  /// of the on-device contract.
  final String keyName;

  /// Reads the stored record, or `null` when there is none (or it is corrupt).
  Future<VaultPinRecord?> read() async {
    final String? raw = await _store.read(keyName);
    if (raw == null) return null;
    try {
      return VaultPinRecord.fromMap(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  /// Writes [record], replacing whatever was stored.
  Future<void> write(VaultPinRecord record) =>
      _store.write(keyName, jsonEncode(record.toMap()));

  /// Removes the record entirely.
  Future<void> delete() => _store.delete(keyName);
}
