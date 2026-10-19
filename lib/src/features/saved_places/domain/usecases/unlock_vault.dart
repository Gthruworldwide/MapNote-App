import '../repositories/vault_repository.dart';
import '../services/vault_authenticator.dart';

/// What an unlock attempt did.
enum VaultUnlockResult {
  /// The vault is open: it was already open, or the user verified successfully.
  unlocked,

  /// The user cancelled or failed verification. The vault stays locked, and no
  /// content may be revealed.
  denied,

  /// The device cannot verify identity *at all*, so the vault opened without a
  /// prompt. Callers **must** surface `noDeviceSecurityWarning` (see below).
  unlockedUnverified,
}

/// Releases the encrypted vault: verify the user, then open the box.
///
/// Mirrors the rest of MapNote's "never trap the user's data" rule: when the
/// device cannot verify the user *at all* (no biometrics and no device
/// credential — an emulator or a low-security device), the vault still opens
/// and reports [VaultUnlockResult.unlockedUnverified] so the UI shows the same
/// `noDeviceSecurityWarning` every other locked-location gate shows. A device
/// with a lock always requires a successful check; a failure stays locked.
class UnlockVault {
  const UnlockVault(this._authenticator, this._repository);

  final VaultAuthenticator _authenticator;
  final VaultRepository _repository;

  Future<VaultUnlockResult> call({required String reason}) async {
    if (_repository.isUnlocked) return VaultUnlockResult.unlocked;

    final VaultVerification verification = await _authenticator.verify(
      reason: reason,
    );
    if (verification == VaultVerification.failed) {
      return VaultUnlockResult.denied;
    }

    await _repository.unlock();
    return verification == VaultVerification.verified
        ? VaultUnlockResult.unlocked
        : VaultUnlockResult.unlockedUnverified;
  }
}
