import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/security/session_guard.dart';
import '../../../../data/models/place.dart';
import '../../../../providers/app_providers.dart';
import '../../data/datasources/flutter_secure_secret_store.dart';
import '../../data/datasources/secret_store.dart';
import '../../data/datasources/trip_stop_detector.dart';
import '../../data/datasources/vault_key_store.dart';
import '../../data/datasources/vault_pin_store.dart';
import '../../data/repositories/biometric_vault_authenticator.dart';
import '../../data/repositories/hive_vault_repository.dart';
import '../../data/repositories/keystore_vault_pin_verifier.dart';
import '../../domain/entities/place_link_suggestion.dart';
import '../../domain/entities/trip_stop.dart';
import '../../domain/repositories/vault_repository.dart';
import '../../domain/services/place_link_suggester.dart';
import '../../domain/services/vault_authenticator.dart';
import '../../domain/services/vault_pin_verifier.dart';
import '../../domain/usecases/unlock_vault.dart';

// ---------------------------------------------------------------------------
// Wiring
// ---------------------------------------------------------------------------
//
// The conventions match `lib/src/providers/app_providers.dart`: small
// `Provider`s for dependencies, an `AsyncNotifierProvider` for mutable state,
// and every provider in this file is scoped to this feature so the vault can be
// deleted without touching the rest of the app.

/// Platform keystore/keychain store for the vault's AES key.
final Provider<SecretStore> vaultSecretStoreProvider =
    Provider<SecretStore>((Ref ref) => const FlutterSecureSecretStore());

/// Generates and holds the AES-256 key that encrypts the vault box.
final Provider<VaultKeyStore> vaultKeyStoreProvider = Provider<VaultKeyStore>(
  (Ref ref) => VaultKeyStore(ref.watch(vaultSecretStoreProvider)),
);

/// The encrypted vault: an additive Hive box, encrypted with the keystore key.
final Provider<VaultRepository> vaultRepositoryProvider =
    Provider<VaultRepository>(
      (Ref ref) => HiveVaultRepository(
        keyStore: ref.watch(vaultKeyStoreProvider),
        boxName: AppConfig.securePlacesBoxName,
      ),
    );

/// Adapts `local_auth` to the domain's [VaultAuthenticator] port.
final Provider<VaultAuthenticator> vaultAuthenticatorProvider =
    Provider<VaultAuthenticator>(
      (Ref ref) => BiometricVaultAuthenticator(
        ref.watch(biometricServiceProvider),
      ),
    );

/// Holds the optional vault PIN record in the platform keystore.
final Provider<VaultPinStore> vaultPinStoreProvider = Provider<VaultPinStore>(
  (Ref ref) => VaultPinStore(ref.watch(vaultSecretStoreProvider)),
);

/// Verifies the optional vault PIN.
final Provider<VaultPinVerifier> vaultPinVerifierProvider =
    Provider<VaultPinVerifier>(
      (Ref ref) => KeystoreVaultPinVerifier(
        store: ref.watch(vaultPinStoreProvider),
      ),
    );

/// Whether a vault PIN has been set.
///
/// A [FutureProvider] because the answer lives in the platform keystore. The
/// UI invalidates it after a PIN is set or removed, so the row never shows a
/// stale answer.
final FutureProvider<bool> vaultPinSetProvider = FutureProvider<bool>(
  (Ref ref) async => await ref.watch(vaultPinVerifierProvider).hasPin(),
);

/// Use case that verifies the user, then opens the encrypted box.
final Provider<UnlockVault> unlockVaultProvider = Provider<UnlockVault>(
  (Ref ref) => UnlockVault(
    ref.watch(vaultAuthenticatorProvider),
    ref.watch(vaultRepositoryProvider),
    ref.watch(vaultPinVerifierProvider),
  ),
);

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// The vaulted places.
///
/// `null` means the vault is **locked** — the box is closed and its key is not
/// in memory. An empty list means it is open and genuinely contains nothing.
final AsyncNotifierProvider<VaultPlacesNotifier, List<Place>?>
vaultPlacesProvider =
    AsyncNotifierProvider<VaultPlacesNotifier, List<Place>?>(
      VaultPlacesNotifier.new,
    );

class VaultPlacesNotifier extends AsyncNotifier<List<Place>?> {
  @override
  Future<List<Place>?> build() async {
    final VaultRepository vault = ref.watch(vaultRepositoryProvider);
    if (!vault.isUnlocked) return null;
    return vault.getAll();
  }

  /// Verifies the user, then opens the vault.
  ///
  /// The caller decides what to say: [VaultUnlockResult.denied] means "still
  /// locked" and [VaultUnlockResult.unlockedUnverified] means the device could
  /// not verify at all, so the UI must show `noDeviceSecurityWarning`.
  Future<VaultUnlockResult> unlock({required String reason}) async {
    final VaultUnlockResult result = await ref
        .read(unlockVaultProvider)
        .call(reason: reason);
    if (_isUnlocked(result)) await _openSession();
    return result;
  }

  /// Opens the vault with the PIN instead of the biometric prompt.
  ///
  /// A rejected or locked-out PIN leaves the vault locked and opens no
  /// session, exactly like a failed biometric check.
  Future<VaultUnlockResult> unlockWithPin(String pin) async {
    final VaultUnlockResult result = await ref
        .read(unlockVaultProvider)
        .unlockWithPin(pin);
    if (_isUnlocked(result)) await _openSession();
    return result;
  }

  /// Whether [result] means the vault is open.
  ///
  /// Explicit rather than `!= denied`, so a *rejected PIN* never counts as an
  /// unlock.
  static bool _isUnlocked(VaultUnlockResult result) =>
      result == VaultUnlockResult.unlocked ||
      result == VaultUnlockResult.unlockedUnverified;

  /// Opens the session window and refreshes the vault contents.
  ///
  /// The session guard is what later closes it (device lock, inactivity,
  /// backgrounding, or an explicit lock), so every unlock path gets an expiry
  /// without any screen having to set one.
  Future<void> _openSession() async {
    await ref.read(sessionGuardProvider).beginSession();
    // With a session open there is now something to protect, so watch the
    // accelerometer for the hand-held / surface-idle verdict that decides
    // whether the idle clock is the long one or the short one.
    unawaited(ref.read(deviceLockDetectorProvider).start());
    await _refresh();
  }

  /// Closes the vault and forgets the key.
  ///
  /// The state moves to locked *before* the (async) box close so the UI can
  /// never show stale content, and so a call from a widget's `dispose` never
  /// writes state after the container is gone.
  ///
  /// The session ends **before** the first `await`, deliberately: this method
  /// is called from a widget's `dispose`, and reading `ref` after an async gap
  /// would throw `UnmountedRefException` once the provider is disposed. Ending
  /// the session is also the semantically correct order — the user asked to
  /// lock, so the session is over the moment they do.
  Future<void> lock() async {
    final VaultRepository vault = ref.read(vaultRepositoryProvider);
    final SessionGuard guard = ref.read(sessionGuardProvider);
    state = const AsyncValue<List<Place>?>.data(null);
    unawaited(guard.endSession(SessionEndReason.userInitiated));
    await vault.lock();
  }

  /// Moves a saved place into the encrypted vault.
  ///
  /// Vault-first: the place is written to the encrypted box **before** it is
  /// removed from the plain store, so a crash between the two writes leaves a
  /// recoverable duplicate rather than a lost place.
  Future<void> moveIn(Place place) async {
    await ref.read(vaultRepositoryProvider).save(place);
    await ref.read(placesProvider.notifier).delete(place.id);
    await _refresh();
  }

  /// Restores a vaulted place to the plain store and removes it from the vault.
  Future<void> moveOut(Place place) async {
    await ref.read(placesProvider.notifier).save(place);
    await ref.read(vaultRepositoryProvider).delete(place.id);
    await _refresh();
  }

  Future<void> delete(String id) async {
    await ref.read(vaultRepositoryProvider).delete(id);
    await _refresh();
  }

  Future<void> _refresh() async {
    final VaultRepository vault = ref.read(vaultRepositoryProvider);
    state = AsyncValue<List<Place>?>.data(
      vault.isUnlocked ? await vault.getAll() : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Auto-geofencing suggestions (derived, never stored)
// ---------------------------------------------------------------------------

/// Detects the day's trip stops (dwell >= 5 min) from the AutoMotion path.
///
/// Watching [autoMotionFixesProvider] re-runs the detection on every accepted
/// fix and on the midnight rollover, exactly like the milestone timeline.
final Provider<List<TripStop>> tripStopsProvider = Provider<List<TripStop>>((
  Ref ref,
) {
  ref.watch(autoMotionFixesProvider);
  return const TripStopDetector().detect(
    ref.read(autoMotionServiceProvider).smoothedPath,
  );
});

/// Advisory links between today's stops and the saved places, newest stop
/// first. Pure derivation: no persistence, no network, and no place name,
/// note or coordinate ever leaves the device.
final Provider<List<PlaceLinkSuggestion>> placeLinkSuggestionsProvider =
    Provider<List<PlaceLinkSuggestion>>((Ref ref) {
      final List<TripStop> stops = ref.watch(tripStopsProvider);
      if (stops.isEmpty) return const <PlaceLinkSuggestion>[];
      final List<Place> places =
          ref.watch(placesProvider).value ?? const <Place>[];
      return const PlaceLinkSuggester().suggest(stops: stops, places: places);
    });
