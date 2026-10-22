import '../repositories/vault_repository.dart';
import '../services/vault_authenticator.dart';
import '../services/vault_pin_verifier.dart';

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

  /// The entered PIN was wrong. The vault stays locked.
  pinRejected,

  /// Too many wrong PIN attempts: the PIN is temporarily unusable and the
  /// vault stays locked.
  pinLockedOut,
}

/// Releases the encrypted vault: verify the user, then open the box.
///
/// Mirrors the rest of MapNote's "never trap the user's data" rule: when the
/// device cannot verify the user *at all* (no biometrics and no device
/// credential — an emulator or a low-security device), the vault still opens
/// and reports [VaultUnlockResult.unlockedUnverified] so the UI shows the same
/// `noDeviceSecurityWarning` every other locked-location gate shows. A device
/// with a lock always requires a successful check; a failure stays locked.
///
/// The optional PIN is a **second** way in, never a replacement: [call] is the
/// biometric path and stays primary, and [unlockWithPin] is only reached when
/// the user explicitly asks to type their PIN.
class UnlockVault {
  const UnlockVault(this._authenticator, this._repository, [this._pinVerifier]);

  final VaultAuthenticator _authenticator;
  final VaultRepository _repository;

  /// The optional PIN verifier. `null` disables the PIN path entirely, which
  /// is what a container without a keystore gets.
  final VaultPinVerifier? _pinVerifier;

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

  /// Unlocks with the PIN instead of the biometric prompt.
  ///
  /// Only a correct PIN opens the box: a wrong PIN, a locked-out PIN and a
  /// missing PIN all leave the vault locked.
  Future<VaultUnlockResult> unlockWithPin(String pin) async {
    if (_repository.isUnlocked) return VaultUnlockResult.unlocked;

    final VaultPinVerifier? verifier = _pinVerifier;
    if (verifier == null) return VaultUnlockResult.pinRejected;

    final VaultPinCheck check = await verifier.check(pin);
    switch (check) {
      case VaultPinCheck.matched:
        await _repository.unlock();
        return VaultUnlockResult.unlocked;
      case VaultPinCheck.lockedOut:
        return VaultUnlockResult.pinLockedOut;
      case VaultPinCheck.notMatched:
      case VaultPinCheck.notSet:
        return VaultUnlockResult.pinRejected;
    }
  }
}
