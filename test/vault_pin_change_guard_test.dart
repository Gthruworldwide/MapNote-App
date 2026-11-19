import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/features/saved_places/domain/services/vault_authenticator.dart';
import 'package:routenote/src/features/saved_places/domain/services/vault_pin_change_guard.dart';
import 'package:routenote/src/features/saved_places/domain/services/vault_pin_verifier.dart';

class _FakeAuthenticator implements VaultAuthenticator {
  VaultVerification verification = VaultVerification.verified;
  int calls = 0;

  @override
  Future<VaultVerification> verify({required String reason}) async {
    calls++;
    return verification;
  }
}

class _FakeVerifier implements VaultPinVerifier {
  int sets = 0;
  int clears = 0;

  @override
  Future<bool> hasPin() async => sets > 0;

  @override
  Future<VaultPinCheck> check(String pin) async => VaultPinCheck.notSet;

  @override
  Future<void> setPin(String pin) async => sets++;

  @override
  Future<void> clearPin() async => clears++;

  @override
  Future<Duration> lockoutRemaining() async => Duration.zero;
}

void main() {
  late _FakeAuthenticator authenticator;
  late _FakeVerifier verifier;
  late VaultPinChangeGuard guard;

  setUp(() {
    authenticator = _FakeAuthenticator();
    verifier = _FakeVerifier();
    guard = VaultPinChangeGuard(authenticator, verifier);
  });

  group('vault PIN step-up', () {
    test('a failed check mutates nothing', () async {
      authenticator.verification = VaultVerification.failed;

      expect(
        await guard.setPin('1234', reason: 'change PIN'),
        VaultPinChangeResult.denied,
      );
      expect(
        await guard.clearPin(reason: 'change PIN'),
        VaultPinChangeResult.denied,
      );
      expect(verifier.sets, 0);
      expect(verifier.clears, 0);
    });

    test('a verified check permits set and clear', () async {
      expect(
        await guard.setPin('1234', reason: 'change PIN'),
        VaultPinChangeResult.updated,
      );
      expect(
        await guard.clearPin(reason: 'change PIN'),
        VaultPinChangeResult.removed,
      );
      expect(verifier.sets, 1);
      expect(verifier.clears, 1);
      expect(authenticator.calls, 2);
    });

    test('no-device-security still mutates but reports the escape hatch',
        () async {
      authenticator.verification = VaultVerification.unavailable;

      expect(
        await guard.setPin('1234', reason: 'change PIN'),
        VaultPinChangeResult.updatedWithoutVerification,
      );
      expect(
        await guard.clearPin(reason: 'change PIN'),
        VaultPinChangeResult.removedWithoutVerification,
      );
      expect(verifier.sets, 1);
      expect(verifier.clears, 1);
    });

    test('an invalid candidate never reaches the keystore', () async {
      expect(
        await guard.setPin('12', reason: 'change PIN'),
        VaultPinChangeResult.invalid,
      );
      expect(authenticator.calls, 0);
      expect(verifier.sets, 0);
    });
  });

  group('settings screen wiring', () {
    test('PIN mutation is routed through the guard only', () {
      final String screen = File(
        'lib/src/features/settings/security_vault_settings_screen.dart',
      ).readAsStringSync();

      expect(screen, contains('vaultPinChangeGuardProvider'));
      expect(screen, isNot(contains('verifier.setPin')));
      expect(screen, isNot(contains('verifier.clearPin')));
      expect(screen, isNot(contains('.setPin(pin)')));
      expect(screen, isNot(contains('.clearPin()')));
    });
  });
}
