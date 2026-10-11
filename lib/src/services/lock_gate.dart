import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../providers/app_providers.dart';
import 'biometric_service.dart';

/// Outcome of a biometric/device-credential prompt.
enum UnlockOutcome {
  /// The user verified successfully.
  verified,

  /// The user cancelled or the verification failed.
  failed,

  /// This device cannot verify the user (no biometrics and no device lock).
  unavailable,
}

/// Prompts the user to verify their identity, without any UI feedback.
Future<UnlockOutcome> requestUnlock(
  WidgetRef ref, {
  required String reason,
}) async {
  final BiometricService biometrics = ref.read(biometricServiceProvider);
  if (!await biometrics.isAvailable()) return UnlockOutcome.unavailable;
  final bool verified = await biometrics.authenticate(reason: reason);
  return verified ? UnlockOutcome.verified : UnlockOutcome.failed;
}

/// Gates a sensitive action behind verification and reports the result via a
/// snackbar. Returns whether the caller may proceed.
///
/// When the device cannot verify the user at all (no biometrics *and* no
/// device credential), the action is denied unless [allowWhenUnavailable] is
/// set — which every locked-location action uses so users are never trapped
/// on devices without a screen lock (emulators, low-security devices). In
/// that fallback case a warning is shown instead of an error.
Future<bool> ensureUnlocked(
  WidgetRef ref, {
  required AppLocalizations l10n,
  required String reason,
  required ScaffoldMessengerState messenger,
  bool allowWhenUnavailable = false,
}) async {
  final UnlockOutcome outcome = await requestUnlock(ref, reason: reason);
  switch (outcome) {
    case UnlockOutcome.verified:
      return true;
    case UnlockOutcome.failed:
      messenger.showSnackBar(SnackBar(content: Text(l10n.authenticationFailed)));
      return false;
    case UnlockOutcome.unavailable:
      if (allowWhenUnavailable) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.noDeviceSecurityWarning)),
        );
        return true;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.biometricsUnavailable)),
      );
      return false;
  }
}
