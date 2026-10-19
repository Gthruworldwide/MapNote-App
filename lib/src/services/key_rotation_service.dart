/// Rotates through a pool of build-time API keys so a single exhausted, revoked
/// or rate-limited key cannot take a cloud feature offline.
///
/// The pool is supplied at build time (`--dart-define=GEMINI_API_KEY=...`, or a
/// CI secret) and is **never** persisted, logged, or sent anywhere except the
/// provider that owns it. The class is dependency-free and accepts an injectable
/// [clock], so rotation can be unit-tested deterministically.
///
/// Rotation model:
/// * The cursor starts on the first key.
/// * [markSuccess] clears a key's failure state and pins the cursor to it.
/// * [markFailure] puts the key in [cooldown] and advances the cursor.
/// * [currentKey] prefers the cursor's key while healthy, then the next healthy
///   key, and finally the key that recovers soonest — so a request is still
///   attempted rather than the client going dark.
class KeyRotationService {
  KeyRotationService({
    required List<String> keys,
    DateTime Function()? clock,
    this.cooldown = const Duration(minutes: 10),
  })  : _keys = _sanitize(keys),
        _clock = clock ?? DateTime.now;

  final List<String> _keys;
  final DateTime Function() _clock;

  /// How long a key stays out of rotation after a failure.
  final Duration cooldown;

  final Map<String, int> _failures = <String, int>{};
  final Map<String, DateTime> _coolingDownUntil = <String, DateTime>{};
  int _cursor = 0;

  /// The configured keys, in priority order (trimmed, non-empty, de-duplicated).
  ///
  /// Returned as an unmodifiable list so a caller can never mutate the pool.
  List<String> get keys => List<String>.unmodifiable(_keys);

  /// Whether any key is configured at all.
  bool get hasKeys => _keys.isNotEmpty;

  /// How many keys are in the pool.
  int get length => _keys.length;

  /// Whether at least one key is currently eligible for use.
  bool get hasHealthyKey => _keys.any(_isHealthy);

  /// The number of consecutive failures recorded for [key].
  int failuresFor(String key) => _failures[key] ?? 0;

  /// The key to use for the next request, or `null` when none is configured.
  ///
  /// Side-effecting by design: it advances the cursor when the current key is
  /// cooling down, so repeated calls during an outage walk the whole pool.
  String? get currentKey {
    if (_keys.isEmpty) return null;
    if (_isHealthy(_keys[_cursor])) return _keys[_cursor];

    for (int offset = 1; offset < _keys.length; offset++) {
      final int index = (_cursor + offset) % _keys.length;
      if (_isHealthy(_keys[index])) {
        _cursor = index;
        return _keys[index];
      }
    }

    // Everything is cooling down: retry the key that recovers first so the
    // client keeps trying instead of failing fast on a transient quota error.
    int soonest = 0;
    for (int i = 1; i < _keys.length; i++) {
      if (_recoveryAt(_keys[i]).isBefore(_recoveryAt(_keys[soonest]))) {
        soonest = i;
      }
    }
    _cursor = soonest;
    return _keys[soonest];
  }

  /// Clears [key]'s failure state and makes it the active key.
  void markSuccess(String key) {
    _failures.remove(key);
    _coolingDownUntil.remove(key);
    final int index = _keys.indexOf(key);
    if (index != -1) _cursor = index;
  }

  /// Records a failure for [key], starts its cooldown, and advances the cursor
  /// so the next [currentKey] prefers a different key when one is available.
  void markFailure(String key, {int? statusCode}) {
    if (!_keys.contains(key)) return;
    _failures[key] = (_failures[key] ?? 0) + 1;
    _coolingDownUntil[key] = _clock().add(cooldown);
    final int index = _keys.indexOf(key);
    if (index != -1 && _keys.length > 1) _cursor = (index + 1) % _keys.length;
  }

  /// Forgets every failure and starts again from the first key.
  void reset() {
    _failures.clear();
    _coolingDownUntil.clear();
    _cursor = 0;
  }

  /// Whether an HTTP failure means *the key itself* is the problem (so rotating
  /// to another key may help), as opposed to a transient server or network
  /// error.
  ///
  /// Gemini signals an invalid/expired key either with `400` +
  /// `API_KEY_INVALID` or with `401`/`403`; quota exhaustion arrives as `429`.
  static bool looksLikeKeyError(int statusCode, String body) {
    if (statusCode == 401 || statusCode == 403 || statusCode == 429) {
      return true;
    }
    if (statusCode != 400) return false;
    final String lower = body.toLowerCase();
    return lower.contains('api_key_invalid') ||
        lower.contains('api key not valid') ||
        lower.contains('api key expired');
  }

  bool _isHealthy(String key) => !_recoveryAt(key).isAfter(_clock());

  DateTime _recoveryAt(String key) =>
      _coolingDownUntil[key] ?? DateTime.fromMillisecondsSinceEpoch(0);

  static List<String> _sanitize(Iterable<String> keys) {
    final List<String> result = <String>[];
    for (final String key in keys) {
      final String trimmed = key.trim();
      if (trimmed.isEmpty || result.contains(trimmed)) continue;
      result.add(trimmed);
    }
    return result;
  }

  /// Deliberately opaque: never let a key leak through string interpolation.
  @override
  String toString() =>
      'KeyRotationService(keys: ${_keys.length}, cooldown: ${cooldown.inMinutes}m)';
}
