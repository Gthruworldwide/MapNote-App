import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/features/saved_places/domain/repositories/vault_repository.dart';
import 'package:routenote/src/features/saved_places/domain/services/vault_authenticator.dart';
import 'package:routenote/src/features/saved_places/domain/usecases/unlock_vault.dart';

class _FakeAuthenticator implements VaultAuthenticator {
  VaultVerification verification = VaultVerification.verified;
  int verifyCalls = 0;

  @override
  Future<VaultVerification> verify({required String reason}) async {
    verifyCalls++;
    return verification;
  }
}

class _FakeVault implements VaultRepository {
  bool unlocked = false;
  int unlockCalls = 0;
  final List<Place> places = <Place>[];

  @override
  bool get isUnlocked => unlocked;

  @override
  Future<void> unlock() async {
    unlockCalls++;
    unlocked = true;
  }

  @override
  Future<void> lock() async => unlocked = false;

  @override
  Future<List<Place>> getAll() async {
    if (!unlocked) throw StateError('locked');
    return List<Place>.of(places);
  }

  @override
  Future<Place?> getById(String id) async {
    if (!unlocked) throw StateError('locked');
    for (final Place place in places) {
      if (place.id == id) return place;
    }
    return null;
  }

  @override
  Future<void> save(Place place) async => places.add(place);

  @override
  Future<void> delete(String id) async =>
      places.removeWhere((Place place) => place.id == id);
}

/// The gate that releases the vault's decryption key.
void main() {
  late _FakeAuthenticator authenticator;
  late _FakeVault vault;
  late UnlockVault unlockVault;

  setUp(() {
    authenticator = _FakeAuthenticator();
    vault = _FakeVault();
    unlockVault = UnlockVault(authenticator, vault);
  });

  test('verifies the user, then opens the vault', () async {
    expect(
      await unlockVault(reason: 'open the vault'),
      VaultUnlockResult.unlocked,
    );

    expect(authenticator.verifyCalls, 1);
    expect(vault.unlockCalls, 1);
    expect(vault.isUnlocked, isTrue);
  });

  test('keeps the vault locked when verification fails', () async {
    authenticator.verification = VaultVerification.failed;

    expect(
      await unlockVault(reason: 'open the vault'),
      VaultUnlockResult.denied,
    );
    expect(vault.unlockCalls, 0);
    expect(vault.isUnlocked, isFalse);
  });

  test('opens unverified on a device that cannot verify at all', () async {
    authenticator.verification = VaultVerification.unavailable;

    expect(
      await unlockVault(reason: 'open the vault'),
      VaultUnlockResult.unlockedUnverified,
    );
    expect(vault.isUnlocked, isTrue);
  });

  test('skips the prompt when the vault is already open', () async {
    vault.unlocked = true;

    expect(
      await unlockVault(reason: 'open the vault'),
      VaultUnlockResult.unlocked,
    );
    expect(authenticator.verifyCalls, 0);
    expect(vault.unlockCalls, 0);
  });
}
