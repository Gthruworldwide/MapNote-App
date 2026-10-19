/// Minimal async key/value store for secrets.
///
/// Abstracted so [VaultKeyStore] can be unit-tested with an in-memory fake
/// instead of the platform channel the real implementation uses. Values are
/// opaque strings; the concrete store decides where they actually live.
abstract interface class SecretStore {
  /// Reads [key], or `null` when it was never written.
  Future<String?> read(String key);

  /// Writes [value] under [key], overwriting any previous value.
  Future<void> write(String key, String value);

  /// Removes [key] if present. Never throws when it is absent.
  Future<void> delete(String key);
}
