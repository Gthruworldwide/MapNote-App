import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_ce/hive.dart';

import 'secret_store.dart';

/// Owns the AES-256 key that encrypts the saved-places vault box.
///
/// The key is generated once with [Hive.generateSecureKey] and kept in the
/// platform keystore via [SecretStore] — never in Hive, never in a Drive
/// backup, never in a log. It is only read from the store after the biometric
/// gate has been passed, which is what makes the encrypted box unreadable
/// without the user's consent.
class VaultKeyStore {
  const VaultKeyStore(
    this._store, {
    this.keyName = 'routenote.vault.aesKey',
  });

  /// AES-256 needs a 32-byte key.
  static const int keyLength = 32;

  final SecretStore _store;

  /// Keystore entry name. Changing it orphans the existing vault, so it is
  /// part of the on-device contract.
  final String keyName;

  /// Loads the existing key, or generates and persists a new one.
  ///
  /// A stored value that is not a valid 32-byte key (truncated keystore entry,
  /// a hand-edited value) is treated as absent and replaced, so a corrupt key
  /// can never leave the user permanently locked out.
  Future<Uint8List> loadOrCreateKey() async {
    final String? stored = await _store.read(keyName);
    if (stored != null) {
      final Uint8List decoded = _decode(stored);
      if (decoded.length == keyLength) return decoded;
    }

    final Uint8List key = Uint8List.fromList(Hive.generateSecureKey());
    await _store.write(keyName, base64UrlEncode(key));
    return key;
  }

  /// Whether a key already exists (i.e. the vault has been used before).
  Future<bool> hasKey() async => await _store.read(keyName) != null;

  /// Destroys the key, making the encrypted box permanently unreadable.
  Future<void> deleteKey() => _store.delete(keyName);

  Uint8List _decode(String value) {
    try {
      return base64Url.decode(value);
    } catch (_) {
      return Uint8List(0);
    }
  }
}
