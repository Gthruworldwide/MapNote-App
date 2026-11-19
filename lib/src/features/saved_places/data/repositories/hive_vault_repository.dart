import 'dart:async';
import 'dart:typed_data';

import '../../../../data/models/place.dart';
import '../../domain/repositories/vault_repository.dart';
import '../datasources/secure_places_local_data_source.dart';
import '../datasources/vault_key_store.dart';

/// [VaultRepository] backed by an AES-256 encrypted Hive box.
///
/// The datasource (and therefore the key) is created on [unlock] and dropped
/// on [lock], so the locked state is the *absence* of the key rather than a
/// flag that could be flipped back by a bug.
class HiveVaultRepository implements VaultRepository {
  HiveVaultRepository({
    required this.keyStore,
    required this.boxName,
  });

  /// Supplies the AES-256 key that opens the encrypted box.
  final VaultKeyStore keyStore;

  final String boxName;

  SecurePlacesLocalDataSource? _dataSource;

  /// Bumped synchronously by [lock] so an in-flight [unlock] can recognise that
  /// its result is stale even though the box close is queued behind it.
  int _epoch = 0;

  /// Box operations are serialized so two unlocks cannot both hold the same
  /// Hive box name open with different cipher instances.
  Future<void> _operationChain = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final Completer<T> completer = Completer<T>();
    _operationChain = _operationChain.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  bool get isUnlocked => _dataSource?.isOpen ?? false;

  /// A stale open must not leave a second datasource holding the box handle.
  Future<void> _closeQuietly(SecurePlacesLocalDataSource source) async {
    try {
      await source.close();
    } catch (_) {
      // Best effort: the box was never published, so nothing can read it.
    }
  }

  /// The open datasource, or a [StateError] while the vault is locked.
  ///
  /// Locked is enforced here — not just by the UI — so no code path can read
  /// the vault's contents without going through [unlock] first.
  Future<SecurePlacesLocalDataSource> _active() async {
    final SecurePlacesLocalDataSource? source = _dataSource;
    if (source == null || !source.isOpen) {
      throw StateError('The encrypted vault is locked.');
    }
    return source;
  }

  @override
  Future<void> unlock() {
    // Captured at call time: a `lock()` that arrives while this is waiting on
    // the keystore increments the epoch and makes this attempt stale.
    final int expectedEpoch = _epoch;
    return _serialize(() async {
      if (_dataSource?.isOpen ?? false) return;

      final Uint8List key = await keyStore.loadOrCreateKey();
      if (expectedEpoch != _epoch) return;

      final SecurePlacesLocalDataSource source = SecurePlacesLocalDataSource(
        boxName: boxName,
        key: key,
      );
      try {
        // Reading forces the box open, so a wrong/corrupt key surfaces here
        // rather than on the first user action.
        await source.getAll();
      } catch (_) {
        await _closeQuietly(source);
        rethrow;
      }

      // The box was opened without publishing it. If a lock landed while we
      // waited, close it again and leave the repository locked.
      if (expectedEpoch != _epoch || (_dataSource?.isOpen ?? false)) {
        await _closeQuietly(source);
        return;
      }
      _dataSource = source;
    });
  }

  @override
  Future<void> lock() {
    // Order is load-bearing: invalidate first (synchronously), then clear the
    // published handle, then queue the actual close behind any open in flight.
    _epoch++;
    final SecurePlacesLocalDataSource? current = _dataSource;
    _dataSource = null;
    return _serialize(() async => current?.close());
  }

  @override
  Future<List<Place>> getAll() async => (await _active()).getAll();

  @override
  Future<Place?> getById(String id) async => (await _active()).getById(id);

  @override
  Future<void> save(Place place) async => (await _active()).put(place);

  @override
  Future<void> delete(String id) async => (await _active()).delete(id);
}
