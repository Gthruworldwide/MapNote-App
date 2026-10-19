import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/features/saved_places/data/datasources/secret_store.dart';
import 'package:routenote/src/features/saved_places/data/datasources/vault_key_store.dart';

/// In-memory [SecretStore] so the key store can be exercised without the
/// platform keystore channel.
class _MemorySecretStore implements SecretStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  const String keyName = 'routenote.vault.aesKey';
  late _MemorySecretStore store;
  late VaultKeyStore keyStore;

  setUp(() {
    store = _MemorySecretStore();
    keyStore = VaultKeyStore(store);
  });

  test('generates a 32-byte AES key and persists it', () async {
    final Uint8List key = await keyStore.loadOrCreateKey();

    expect(key, hasLength(VaultKeyStore.keyLength));
    expect(await keyStore.hasKey(), isTrue);
    expect(base64Url.decode(store.values[keyName]!), key);
  });

  test('returns the same key on every call', () async {
    final Uint8List first = await keyStore.loadOrCreateKey();
    final Uint8List second = await keyStore.loadOrCreateKey();

    expect(second, first);
  });

  test('separate key names get independent keys', () async {
    final Uint8List a = await VaultKeyStore(
      store,
      keyName: 'vault-a',
    ).loadOrCreateKey();
    final Uint8List b = await VaultKeyStore(
      store,
      keyName: 'vault-b',
    ).loadOrCreateKey();

    expect(a, isNot(b));
  });

  test('replaces a corrupt stored key instead of locking the user out', () async {
    store.values[keyName] = 'not-a-valid-key';

    final Uint8List key = await keyStore.loadOrCreateKey();

    expect(key, hasLength(VaultKeyStore.keyLength));
    expect(base64Url.decode(store.values[keyName]!), key);
  });

  test('replaces a truncated stored key', () async {
    store.values[keyName] = base64Url.encode(<int>[1, 2, 3]);

    final Uint8List key = await keyStore.loadOrCreateKey();

    expect(key, hasLength(VaultKeyStore.keyLength));
    expect(key, isNot(<int>[1, 2, 3]));
  });

  test('reports no key before first use and after deleteKey', () async {
    expect(await keyStore.hasKey(), isFalse);

    await keyStore.loadOrCreateKey();
    expect(await keyStore.hasKey(), isTrue);

    await keyStore.deleteKey();
    expect(await keyStore.hasKey(), isFalse);
  });
}
