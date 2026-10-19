import 'package:hive_ce/hive.dart';

import '../../../../data/models/place.dart';

/// Persistent, AES-256 encrypted storage for vaulted places.
///
/// A dedicated box ([boxName]) is opened lazily with the [HiveAesCipher] built
/// from the keystore-held key, then closed by [close] so the key is dropped:
/// while locked, nothing in memory can decrypt the ciphertext on disk. The
/// stored value shape is identical to the plain `places` box (`Place.toMap`),
/// so a vaulted place round-trips without any new schema.
///
/// **What is and is not encrypted.** Hive encrypts a frame's *value* and leaves
/// its *key* in plaintext (`BinaryWriterImpl.writeFrame`). The vault therefore
/// only ever stores user-authored content — name, notes and coordinates — as an
/// encrypted value, and keys entries by [Place.id], which is an opaque
/// `Uuid.v4` string. What an attacker with the raw file can recover is a random
/// id per entry (and the entry count), never anything the user typed.
class SecurePlacesLocalDataSource {
  SecurePlacesLocalDataSource({
    required this.boxName,
    required List<int> key,
  }) : _cipher = HiveAesCipher(key);

  final String boxName;
  final HiveAesCipher _cipher;

  Box<dynamic>? _box;

  /// Whether the encrypted box is currently open.
  bool get isOpen => _box?.isOpen ?? false;

  Future<Box<dynamic>> _open() async {
    final Box<dynamic>? existing = _box;
    if (existing != null && existing.isOpen) return existing;
    return _box = await Hive.openBox<dynamic>(
      boxName,
      encryptionCipher: _cipher,
    );
  }

  /// All vaulted places, newest first.
  Future<List<Place>> getAll() async {
    final Box<dynamic> box = await _open();
    final List<Place> places = box.values
        .whereType<Map>()
        .map((Map raw) => Place.fromMap(Map<String, dynamic>.from(raw)))
        .toList();
    places.sort((Place a, Place b) => b.timestamp.compareTo(a.timestamp));
    return places;
  }

  Future<Place?> getById(String id) async {
    final Box<dynamic> box = await _open();
    final Object? raw = box.get(id);
    if (raw is Map) return Place.fromMap(Map<String, dynamic>.from(raw));
    return null;
  }

  /// Inserts or updates a place (keyed by its id), flushing to disk so a crash
  /// right after a move cannot silently revert it.
  Future<void> put(Place place) async {
    final Box<dynamic> box = await _open();
    await box.put(place.id, place.toMap());
    await box.flush();
  }

  Future<void> delete(String id) async {
    final Box<dynamic> box = await _open();
    await box.delete(id);
    await box.flush();
  }

  /// Closes the encrypted box, dropping the open handle (and with it the last
  /// in-memory reference to the cipher).
  Future<void> close() async {
    await _box?.close();
    _box = null;
  }
}
