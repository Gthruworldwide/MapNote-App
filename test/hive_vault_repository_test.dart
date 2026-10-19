import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/features/saved_places/data/datasources/secret_store.dart';
import 'package:routenote/src/features/saved_places/data/datasources/vault_key_store.dart';
import 'package:routenote/src/features/saved_places/data/repositories/hive_vault_repository.dart';

/// In-memory [SecretStore] standing in for the platform keystore.
class _MemorySecretStore implements SecretStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Verifies the vault against a real encrypted Hive box on disk (the same
/// pattern as `place_persistence_test.dart`), so the AES wiring, the lock
/// enforcement and the on-disk encryption are all exercised for real.
void main() {
  const String boxName = 'secure_places';

  late Directory tempDir;
  late _MemorySecretStore store;
  late HiveVaultRepository vault;

  Place place({String id = 'vault-1', String name = 'Vaulted Spot'}) => Place(
    id: id,
    name: name,
    notes: 'vault-notes',
    latitude: 30.0444,
    longitude: 31.2357,
    timestamp: DateTime.utc(2026, 10, 19, 9),
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('routenote_vault_');
    Hive.init(tempDir.path);
    store = _MemorySecretStore();
    vault = HiveVaultRepository(
      keyStore: VaultKeyStore(store),
      boxName: boxName,
    );
  });

  tearDown(() async {
    await Hive.close();
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('starts locked and refuses every read and write', () async {
    expect(vault.isUnlocked, isFalse);
    await expectLater(vault.getAll(), throwsStateError);
    await expectLater(vault.getById('vault-1'), throwsStateError);
    await expectLater(vault.save(place()), throwsStateError);
    await expectLater(vault.delete('vault-1'), throwsStateError);
  });

  test('round-trips a place once unlocked', () async {
    await vault.unlock();
    expect(vault.isUnlocked, isTrue);

    await vault.save(place());

    expect(await vault.getAll(), hasLength(1));
    expect((await vault.getById('vault-1'))?.name, 'Vaulted Spot');
    final Place stored = (await vault.getAll()).single;
    expect(stored.notes, 'vault-notes');
    expect(stored.latitude, 30.0444);
  });

  test('re-locks: the key is dropped and reads fail again', () async {
    await vault.unlock();
    await vault.save(place());
    await vault.lock();

    expect(vault.isUnlocked, isFalse);
    await expectLater(vault.getAll(), throwsStateError);
  });

  test('vaulted places survive a lock/unlock cycle', () async {
    await vault.unlock();
    await vault.save(place());
    await vault.lock();

    await vault.unlock();

    expect((await vault.getAll()).single.name, 'Vaulted Spot');
  });

  test('deletes a vaulted place', () async {
    await vault.unlock();
    await vault.save(place());

    await vault.delete('vault-1');

    expect(await vault.getAll(), isEmpty);
  });

  test('writes the AES key to the key store only, never into the box', () async {
    await vault.unlock();
    await vault.save(place());
    await vault.lock();

    expect(await VaultKeyStore(store).hasKey(), isTrue);

    final String raw = _boxBytes(tempDir);
    expect(raw.contains('routenote.vault.aesKey'), isFalse);
  });

  test('holds no plaintext place data on disk', () async {
    await vault.unlock();
    await vault.save(place());
    await vault.lock();

    final String raw = _boxBytes(tempDir);

    // The whole place value sits inside the AES-256 encrypted frame, so the
    // name and notes the user typed cannot be read off the file.
    expect(raw.contains('Vaulted Spot'), isFalse);
    expect(raw.contains('vault-notes'), isFalse);
    expect(raw.contains('30.0444'), isFalse);
  });

  test('documents Hive\'s plaintext *box keys*', () async {
    await vault.unlock();
    await vault.save(place());
    await vault.lock();

    // Hive writes a frame's key unencrypted and only encrypts its value
    // (BinaryWriterImpl.writeFrame → writeKey(...), then writeEncrypted(...)).
    // That is a Hive property, not something the vault can switch off, so the
    // vault keys entries by an opaque Uuid.v4 id: what leaks is a random id and
    // the entry count — never a name, note or coordinate. Asserted explicitly
    // so a future Hive upgrade that changes this behaviour is noticed.
    expect(_boxBytes(tempDir).contains('vault-1'), isTrue);
  });
}

/// Concatenates every Hive file in [dir] so the assertions do not depend on the
/// exact file name Hive chose for the box.
String _boxBytes(Directory dir) {
  final List<File> files = dir
      .listSync()
      .whereType<File>()
      .where((File file) => file.path.endsWith('.hive'))
      .toList();
  expect(files, isNotEmpty);
  return files
      .map((File file) => String.fromCharCodes(file.readAsBytesSync()))
      .join();
}
