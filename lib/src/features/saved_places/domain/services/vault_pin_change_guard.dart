import 'vault_authenticator.dart';
import 'vault_pin_verifier.dart';

/// What a PIN mutation did.
enum VaultPinChangeResult {
  /// The new PIN was stored after a successful device step-up.
  updated,

  /// The PIN was removed after a successful device step-up.
  removed,

  /// Stored, but the device could not verify identity at all. The caller must
  /// show `noDeviceSecurityWarning` (MapNote's single documented escape hatch).
  updatedWithoutVerification,

  /// Removed with the same no-security escape hatch.
  removedWithoutVerification,

  /// Verification failed or was cancelled: nothing was mutated.
  denied,

  /// The candidate PIN did not satisfy [VaultPinPolicy].
  invalid,
}

/// The only sanctioned way to create, replace or remove a vault PIN.
///
/// PIN mutation is a credential change, so entering the settings screen is not
/// proof of identity. The guard requires a fresh biometric / device-credential
/// check before it touches the keystore record. A device with no security at
/// all uses the same escape hatch as every other locked-location gate: the
/// mutation proceeds and the UI reports the warning.
class VaultPinChangeGuard {
  const VaultPinChangeGuard(this._authenticator, this._verifier);

  final VaultAuthenticator _authenticator;
  final VaultPinVerifier _verifier;

  Future<VaultPinChangeResult> setPin(
    String pin, {
    required String reason,
  }) async {
    if (!VaultPinPolicy.isValid(pin)) return VaultPinChangeResult.invalid;

    final VaultVerification verification = await _authenticator.verify(
      reason: reason,
    );
    if (verification == VaultVerification.failed) {
      return VaultPinChangeResult.denied;
    }

    await _verifier.setPin(pin);
    return verification == VaultVerification.verified
        ? VaultPinChangeResult.updated
        : VaultPinChangeResult.updatedWithoutVerification;
  }

  Future<VaultPinChangeResult> clearPin({required String reason}) async {
    final VaultVerification verification = await _authenticator.verify(
      reason: reason,
    );
    if (verification == VaultVerification.failed) {
      return VaultPinChangeResult.denied;
    }

    await _verifier.clearPin();
    return verification == VaultVerification.verified
        ? VaultPinChangeResult.removed
        : VaultPinChangeResult.removedWithoutVerification;
  }
}
