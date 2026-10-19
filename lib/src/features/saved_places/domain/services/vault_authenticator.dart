/// What an identity check produced.
enum VaultVerification {
  /// The user verified successfully (biometrics or device credential).
  verified,

  /// The user cancelled, or the check failed: nothing may be revealed.
  failed,

  /// This device cannot verify the user *at all* (no biometrics and no device
  /// credential), so the prompt cannot even be shown.
  unavailable,
}

/// Verifies the user's identity before the encrypted vault key is released.
///
/// Implemented in the data layer on top of `local_auth`; the domain only learns
/// the [VaultVerification], so the plugin channel never leaks into the vault's
/// business rules. Availability and the prompt are one call, exactly like
/// `requestUnlockWith` in `lib/src/services/lock_gate.dart`, so there is a
/// single way for the vault to ask "who is this?".
abstract interface class VaultAuthenticator {
  /// Prompts for biometric/device-credential verification.
  ///
  /// Uses adaptive device authentication (`biometricOnly: false`), so the
  /// system may fall back to the device PIN / pattern / password. Never throws:
  /// plugin failures degrade to [VaultVerification.failed].
  Future<VaultVerification> verify({required String reason});
}
