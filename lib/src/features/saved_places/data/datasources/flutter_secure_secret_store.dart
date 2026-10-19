import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secret_store.dart';

/// [SecretStore] backed by the platform keystore / keychain.
///
/// On Android this is the Keystore-encrypted shared preferences store; on iOS
/// the Keychain. Neither is included in a Drive backup or in the app's Hive
/// files, which is exactly what the vault key needs.
class FlutterSecureSecretStore implements SecretStore {
  const FlutterSecureSecretStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
