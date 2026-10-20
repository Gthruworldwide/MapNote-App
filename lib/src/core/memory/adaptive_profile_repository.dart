import 'package:hive_ce/hive.dart';

import '../config/app_config.dart';
import 'adaptive_profile.dart';
import 'adaptive_profile_key_store.dart';

/// Persistence for the learned [AdaptiveProfile], in its own AES-256 encrypted
/// Hive box (`AppConfig.adaptiveProfileBoxName`).
///
/// **Fail-safe by design.** Unlike the saved-places vault, a broken profile is
/// not a data-loss event — it is a cache of numbers that can be relearned in a
/// few drives. So every failure mode here (no keystore, a corrupt box, a
/// malformed record, an unavailable encryption cipher) degrades to
/// [AdaptiveProfile.defaults] rather than throwing into the analytics path. A
/// classifier must never stop working because its tuning file is unreadable.
///
/// The box is **separate from both** `placesBox` and the vault: no existing
/// schema is touched, and no adapter is registered, because the value is a plain
/// `Map<String, Object?>` — identical in shape to how the rest of the app stores
/// records, so nothing about Hive CE's migration story changes.
class AdaptiveProfileRepository {
  AdaptiveProfileRepository({
    required this.keyStore,
    this.boxName = AppConfig.adaptiveProfileBoxName,
  });

  /// Supplies the AES-256 key that opens the profile box.
  final AdaptiveProfileKeyStore keyStore;

  /// Overrides the box name (tests use a throwaway name).
  final String boxName;

  /// Key of the single stored profile record, declared once.
  static const String profileKey = 'profile';

  AdaptiveProfile _cached = AdaptiveProfile.defaults;
  bool _loaded = false;

  /// The profile currently in memory. [load] must have run first for this to
  /// reflect disk; it starts at the defaults, which are always valid.
  AdaptiveProfile get profile => _cached;

  /// Whether [load] has completed at least once.
  bool get isLoaded => _loaded;

  /// Loads the stored profile, falling back to the defaults on any failure.
  ///
  /// Safe to call repeatedly: the second call re-reads disk, which is what makes
  /// a profile written by another isolate (or a previous run) visible.
  Future<AdaptiveProfile> load() async {
    try {
      final Box<dynamic> box = await _open();
      final Object? raw = box.get(profileKey);
      if (raw is Map) {
        _cached = AdaptiveProfile.fromMap(Map<String, dynamic>.from(raw));
      } else {
        _cached = AdaptiveProfile.defaults;
      }
    } catch (_) {
      _cached = AdaptiveProfile.defaults;
    }
    _loaded = true;
    return _cached;
  }

  /// Persists [profile] and makes it the in-memory value.
  ///
  /// Returns `true` on success. A write failure is reported, not thrown: the
  /// in-memory profile still applies for the current run, so a full disk costs
  /// only the *learning*, never the classification.
  Future<bool> save(AdaptiveProfile profile) async {
    _cached = profile;
    try {
      final Box<dynamic> box = await _open();
      await box.put(profileKey, profile.toMap());
      await box.flush();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Discards the learned profile, returning to the documented defaults.
  Future<void> clear() async {
    _cached = AdaptiveProfile.defaults;
    try {
      final Box<dynamic> box = await _open();
      await box.delete(profileKey);
      await box.flush();
    } catch (_) {
      // A profile that cannot be deleted still reverts in memory, and the next
      // successful save overwrites it.
    }
  }

  /// Closes the box so the cipher and its key leave memory.
  Future<void> close() async {
    try {
      final Box<dynamic>? box = _box;
      _box = null;
      await box?.close();
    } catch (_) {
      _box = null;
    }
  }

  Box<dynamic>? _box;

  Future<Box<dynamic>> _open() async {
    final Box<dynamic>? existing = _box;
    if (existing != null && existing.isOpen) return existing;
    final List<int> key = await keyStore.loadOrCreateKey();
    return _box = await Hive.openBox<dynamic>(
      boxName,
      encryptionCipher: HiveAesCipher(key),
    );
  }
}
