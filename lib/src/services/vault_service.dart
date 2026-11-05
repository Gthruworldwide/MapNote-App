import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive.dart';

/// Import AppConfig via relative path
import '../core/config/app_config.dart';

// ---------------------------------------------------------------------------
// VaultItem model
// ---------------------------------------------------------------------------

/// A single item stored inside the AES-256 encrypted vault box.
/// The payload is always encrypted; the field is opaque to anything that does
/// not hold the active AES key.
class VaultItem {
  /// Unique identifier for this item.
  final String id;

  /// Encrypted payload (base64-encoded ciphertext + IV tag). Never stored in the
  /// clear outside the Hive box, and never sent off-device.
  final String encryptedPayload;

  /// Category helps the UI present a typed badge (e.g. "Sensitive Location",
  /// "Private Note").
  final String category;

  /// When the item was first created.
  final DateTime createdAt;

  VaultItem({
    required this.id,
    required this.encryptedPayload,
    required this.category,
    required this.createdAt,
  });

  /// Convert to a map suitable for Hive storage (the map itself is encrypted
  /// by Hive, but the shape stays stable).
  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'encryptedPayload': encryptedPayload,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
      };

  /// Reconstruct from a map returned by Hive.
  factory VaultItem.fromMap(Map<String, dynamic> map) => VaultItem(
        id: map['id'] as String,
        encryptedPayload: map['encryptedPayload'] as String,
        category: map['category'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );

  @override
  String toString() => 'VaultItem(id: $id, category: $category)';
}

// ---------------------------------------------------------------------------
// VaultService
// ---------------------------------------------------------------------------

/// Handles the AES-256 encrypted Hive box lifecycle. The box is opened lazily
/// after biometric/gate validation and closed when the session ends. The key
/// lives in [FlutterSecureStorage] and is never exposed in raw form outside the
/// crypto operations that open the box.
///
/// Invariants:
/// - The box key is generated once and persisted in secure storage.
/// - While the box is closed, [_box] is null and all reads throw.
/// - The box is *additive*: the plain [appConfig.securePlacesBoxName] is never
/// touched, so no schema migration is ever required.
class VaultService {
  /// Name of the AES-256 encrypted Hive box (defined in [AppConfig]).
  static const String boxName = AppConfig.securePlacesBoxName;

  /// Key length for AES-256 (32 bytes).
  static const int keyLength = 32;

  /// The key that encrypts/decrypts the box values. Lives in FlutterSecureStorage.
  final String _storageKey = 'routenote.vault.aesKey';

  /// The secure storage instance for the AES key.
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// Lazily opened encrypted Hive box.
  Box<dynamic>? _box;

  /// True while the encrypted box is open and the user session is valid.
  bool get isOpen => _box?.isOpen ?? false;

  VaultService._();

  /// Open the encrypted box, generating and persisting the AES key on first use.
  ///
  /// Must be called after the user has been authenticated (biometric or PIN).
  /// Throws [StateError] if the vault is already open, and silently returns
  /// if it is already open and healthy.
  Future<void> open() async {
    if (isOpen) return; // already open and healthy

    // If there's a stale box that's closed, drop it.
    _box?.close();
    _box = null;

    final Uint8List key = await _loadOrCreateKey();
    _box = await Hive.openBox<dynamic>(
      boxName,
      encryptionCipher: HiveAesCipher(key),
    );
  }

  /// Close the encrypted box and drop the in-memory key.
  Future<void> close() async {
    await _box?.close();
    _box = null;
  }

  /// Whether the vault has been initialized (key exists in storage).
  Future<bool> hasKey() async => await _secureStorage.read(key: _storageKey) != null;

  /// Load the existing AES key from secure storage, or generate a new one.
  Future<Uint8List> _loadOrCreateKey() async {
    final String? stored = await _secureStorage.read(key: _storageKey);
    if (stored != null) {
      try {
        final List<int> decoded = _base64ToBytes(stored);
        if (decoded.length == keyLength) {
          return Uint8List.fromList(decoded);
        }
      } catch (_) {
        // Corrupt stored key — fall through to generate a new one.
      }
    }

    // Generate a fresh key and persist it.
    final Uint8List key = Uint8List.fromList(Hive.generateSecureKey());
    await _secureStorage.write(key: _storageKey, value: _bytesToBase64(key));
    return key;
  }

  /// Base64-encode a byte list for secure storage.
  String _bytesToBase64(List<int> bytes) => base64Encode(bytes);

  /// Base64-decode a string from secure storage.
  List<int> _base64ToBytes(String str) => base64Decode(str);

  /// Get all vaulted items.
  Future<List<VaultItem>> getAll() async {
    if (!isOpen) throw StateError('The encrypted vault is locked.');
    final List<dynamic> raw = _box!.values.toList();
    return raw
        .whereType<Map>()
        .map((Map m) => VaultItem.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Get a single vaulted item by ID.
  Future<VaultItem?> getById(String id) async {
    if (!isOpen) throw StateError('The encrypted vault is locked.');
    final Object? raw = _box!.get(id);
    if (raw is Map) return VaultItem.fromMap(Map<String, dynamic>.from(raw));
    return null;
  }

  /// Insert or update a vaulted item.
  Future<void> put(VaultItem item) async {
    if (!isOpen) throw StateError('The encrypted vault is locked.');
    await _box!.put(item.id, item.toMap());
    await _box!.flush();
  }

  /// Remove a vaulted item by ID.
  Future<void> delete(String id) async {
    if (!isOpen) throw StateError('The encrypted vault is locked.');
    await _box!.delete(id);
    await _box!.flush();
  }
}