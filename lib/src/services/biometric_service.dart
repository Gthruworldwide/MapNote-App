import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Wraps `local_auth` so the rest of the app never touches the plugin channel
/// directly. All failures degrade to `false` instead of throwing.
class BiometricService {
  const BiometricService();

  static bool get _isSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Whether this device can verify the user (biometrics or device credential).
  Future<bool> isAvailable() async {
    if (!_isSupported) return false;
    try {
      final LocalAuthentication auth = LocalAuthentication();
      if (await auth.isDeviceSupported()) return true;
      if (await auth.canCheckBiometrics) return true;
      final List<BiometricType> types = await auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Prompts for biometric/device-credential verification. Returns `true` only
  /// when the user authenticated successfully.
  ///
  /// Uses adaptive device authentication: `biometricOnly` is false, so when
  /// biometrics are missing (or the user fails them at least once on Android)
  /// the system automatically offers the device credential (PIN / pattern /
  /// password) as a fallback. `persistAcrossBackgrounding` keeps the auth
  /// session alive across a background/foreground cycle. (local_auth 3.x maps
  /// these to `AuthenticationOptions(biometricOnly: false, stickyAuth: true)`
  /// internally — the options class itself is not exported to consumers.)
  Future<bool> authenticate({required String reason}) async {
    if (!_isSupported) return false;
    try {
      final LocalAuthentication auth = LocalAuthentication();
      return await auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
