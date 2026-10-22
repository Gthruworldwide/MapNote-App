/// The result of checking a candidate vault PIN.
enum VaultPinCheck {
  /// The PIN is correct and the vault may be unlocked.
  matched,

  /// The PIN is wrong. The attempt was counted towards the lockout.
  notMatched,

  /// Too many wrong attempts: the PIN is temporarily unusable.
  lockedOut,

  /// No PIN has been set, so there is nothing to check against.
  notSet,
}

/// Verifies the optional vault PIN.
///
/// The PIN is a *second* way into the encrypted vault, offered to users whose
/// device cannot do biometrics (or who prefer a code they can type). It never
/// replaces the biometric check: the biometric path stays primary, and the PIN
/// is an explicit alternative the user picks.
///
/// Implemented in the data layer on top of the platform keystore, so the domain
/// only learns the [VaultPinCheck] and never sees a hash, a salt or a counter.
abstract interface class VaultPinVerifier {
  /// Whether a PIN has been set at all.
  Future<bool> hasPin();

  /// Checks [pin] against the stored record.
  ///
  /// Never throws: a missing record reports [VaultPinCheck.notSet], a lockout
  /// reports [VaultPinCheck.lockedOut], and a wrong PIN reports
  /// [VaultPinCheck.notMatched].
  Future<VaultPinCheck> check(String pin);

  /// Sets (or replaces) the PIN.
  ///
  /// Replaces the salt and the hash, and clears any lockout, so a new PIN
  /// always starts from a clean slate.
  Future<void> setPin(String pin);

  /// Removes the PIN entirely. The vault then falls back to biometrics only.
  Future<void> clearPin();

  /// How long the PIN is still locked out, or [Duration.zero] when it is usable.
  Future<Duration> lockoutRemaining();
}

/// The rules a vault PIN must satisfy.
///
/// A PIN is a convenience credential for a user who wants to type something
/// rather than press a finger, so it is deliberately short. It is never a
/// replacement for the device credential, and the record it produces lives in
/// the platform keystore, so the short length does not expose the vault key
/// itself.
class VaultPinPolicy {
  const VaultPinPolicy._();

  /// The shortest accepted PIN.
  static const int minLength = 4;

  /// The longest accepted PIN. Long enough for a memorable passcode, short
  /// enough to type on the unlock screen.
  static const int maxLength = 12;

  /// Whether [pin] satisfies the policy.
  ///
  /// Digits only: the PIN is typed on the unlock screen, and a numeric pad is
  /// both faster and less error-prone than a full keyboard.
  static bool isValid(String pin) {
    if (pin.length < minLength || pin.length > maxLength) return false;
    for (final int unit in pin.codeUnits) {
      if (unit < 0x30 || unit > 0x39) return false;
    }
    return true;
  }
}
