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

  @override
  bool get isUnlocked => _dataSource?.isOpen ?? false;

  /// Opens the encrypted box with the keystore key, creating the key on first
  /// use.
  Future<SecurePlacesLocalDataSource> _openBox() async {
    final Uint8List key = await keyStore.loadOrCreateKey();
    final SecurePlacesLocalDataSource source = SecurePlacesLocalDataSource(
      boxName: boxName,
      key: key,
    );
    _dataSource = source;
    // Reading forces the box open, so a wrong/corrupt key surfaces here rather
    // than on the first user action.
    await source.getAll();
    return source;
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
  Future<void> unlock() async {
    await _openBox();
  }

  @override
  Future<void> lock() async {
    final SecurePlacesLocalDataSource? current = _dataSource;
    _dataSource = null;
    await current?.close();
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
