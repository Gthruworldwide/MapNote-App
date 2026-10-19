import '../../../../data/models/place.dart';

/// Persistence port for the biometric-gated, AES-256 encrypted "saved places"
/// vault.
///
/// The vault is a **separate, additive** Hive box: the plain `places` box is
/// never touched, so existing data, Drive backups and the JSON schema stay
/// byte-compatible. While locked, the box is closed and its key is not held in
/// memory, so the ciphertext on disk cannot be read — by the app or by anyone
/// with the device.
///
/// The encrypted payload is the user-authored content (name, notes and
/// coordinates). Hive leaves frame *keys* in plaintext, which is exactly why
/// the vault keys entries by the opaque `Uuid.v4` [Place.id] — see
/// [SecurePlacesLocalDataSource] for the full breakdown.
abstract interface class VaultRepository {
  /// Whether the encrypted box is currently open in memory.
  bool get isUnlocked;

  /// Opens the encrypted box, generating and persisting the AES key on first
  /// use.
  ///
  /// Callers must verify the user through [VaultAuthenticator] first; this
  /// method deliberately does not prompt, so the gate lives in one place
  /// (the `UnlockVault` use case).
  Future<void> unlock();

  /// Closes the box and forgets the key, returning the vault to its locked
  /// state.
  Future<void> lock();

  /// All vaulted places, newest first. Throws while locked.
  Future<List<Place>> getAll();

  /// A single vaulted place, or `null`. Throws while locked.
  Future<Place?> getById(String id);

  /// Inserts or updates a vaulted place. Throws while locked.
  Future<void> save(Place place);

  /// Removes a vaulted place. Throws while locked.
  Future<void> delete(String id);
}
