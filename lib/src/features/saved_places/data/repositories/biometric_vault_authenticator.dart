import '../../../../services/biometric_service.dart';
import '../../domain/services/vault_authenticator.dart';

/// [VaultAuthenticator] on top of the app's [BiometricService] (`local_auth`).
///
/// Keeping this adapter in the data layer means the vault's business rules only
/// depend on a [VaultVerification], and the plugin stays swappable in tests.
/// [BiometricService] remains the only file that touches `local_auth`.
class BiometricVaultAuthenticator implements VaultAuthenticator {
  const BiometricVaultAuthenticator(this._biometrics);

  final BiometricService _biometrics;

  @override
  Future<VaultVerification> verify({required String reason}) async {
    // Mirrors `requestUnlockWith`: a device that cannot verify at all is
    // reported as *unavailable* rather than as a failure, so the caller can
    // apply MapNote's one documented escape hatch (AGENT_SKILLS §2.4).
    if (!await _biometrics.isAvailable()) return VaultVerification.unavailable;

    final bool verified = await _biometrics.authenticate(reason: reason);
    return verified ? VaultVerification.verified : VaultVerification.failed;
  }
}
