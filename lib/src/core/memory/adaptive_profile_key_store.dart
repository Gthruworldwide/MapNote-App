import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_ce/hive.dart';

/// Owns the AES-256 key that encrypts the adaptive-profile box.
///
/// A **separate key from the saved-places vault**, deliberately: the two boxes
/// have completely different threat models. The vault holds user-authored
/// content and is gated behind biometrics; the adaptive profile holds only
/// anonymous numbers learned from the accelerometer (vibration baselines,
/// thresholds), and must be readable by the analytics pipeline with no user
/// prompt at all. Sharing one key would force one of those to bend.
///
/// The concrete store is injected as a function pair so core does not depend on
/// a feature's secret-storage implementation, and so tests can use memory.
class AdaptiveProfileKeyStore {
  const AdaptiveProfileKeyStore({
    required this.read,
    required this.write,
    this.keyName = 'mapnote.adaptive.aesKey',
  });

  /// AES-256 needs a 32-byte key.
  static const int keyLength = 32;

  /// Reads the stored (base64url) key, or `null`.
  final Future<String?> Function(String key) read;

  /// Writes the stored (base64url) key.
  final Future<void> Function(String key, String value) write;

  /// Keystore entry name. Changing it orphans the existing profile, so it is
  /// part of the on-device contract.
  final String keyName;

  /// Loads the existing key, or generates and persists a new one.
  ///
  /// A stored value that is not a valid 32-byte key is treated as absent and
  /// replaced: a corrupt profile is disposable (it is only numbers), so the
  /// right recovery is to start over rather than to fail.
  Future<Uint8List> loadOrCreateKey() async {
    final String? stored = await read(keyName);
    if (stored != null) {
      final Uint8List decoded = _decode(stored);
      if (decoded.length == keyLength) return decoded;
    }
    final Uint8List key = Uint8List.fromList(Hive.generateSecureKey());
    await write(keyName, base64UrlEncode(key));
    return key;
  }

  Uint8List _decode(String value) {
    try {
      return base64Url.decode(value);
    } catch (_) {
      return Uint8List(0);
    }
  }
}
