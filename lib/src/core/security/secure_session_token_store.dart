import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'session_guard.dart';

/// [SessionTokenStore] backed by the platform keystore / keychain.
///
/// On Android this is the Keystore-encrypted preference store, on iOS the
/// Keychain. The token written here is deliberately opaque (see
/// [SessionGuard]): it records *that* a session existed, never who the user is,
/// so a leak of this entry reveals nothing.
class SecureSessionTokenStore implements SessionTokenStore {
  const SecureSessionTokenStore([
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
