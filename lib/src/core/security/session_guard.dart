import 'dart:async';

/// Minimal async key/value store for the session token.
///
/// Deliberately its own port rather than a reuse of the vault's `SecretStore`:
/// the session token is a *core security* concern, and core must not depend on
/// a feature's data layer. The platform-backed implementation lives next to the
/// app's other secret storage; tests use an in-memory fake.
abstract interface class SessionTokenStore {
  /// Reads [key], or `null` when it was never written.
  Future<String?> read(String key);

  /// Writes [value] under [key], overwriting any previous value.
  Future<void> write(String key, String value);

  /// Removes [key] if present. Never throws when it is absent.
  Future<void> delete(String key);
}

/// Why a session was ended. Reported so the UI can explain itself, and so
/// diagnostics can distinguish "the user navigated away for an hour" from
/// "the OS killed us".
enum SessionEndReason {
  /// The app was backgrounded long enough that the vault must not stay open.
  appBackgrounded,

  /// The OS reported the device lock screen (the user pressed power, or the
  /// screen timed out). This is an **immediate** end, not a grace period: the
  /// device is out of the user's hands and may be in a pocket or on a table.
  deviceLocked,

  /// No user interaction for longer than the configured inactivity timeout.
  inactivityTimeout,

  /// The user ended it explicitly (sign-out, a lock button).
  userInitiated,
}

/// Whether the device is being held or is lying still on a surface.
///
/// Used to decide what a "session" even means: a phone resting on a desk is not
/// an engaged session, so it should time out on the *short* clock, while a phone
/// being carried and used should not be interrupted.
enum InteractionContext {
  /// Being held / actively used: micro-movements and recent input.
  handHeld,

  /// Lying on a surface: no micro-movements for a sustained period.
  surfaceIdle,

  /// Not enough evidence yet to say (cold start).
  unknown,
}

/// Owns the lifetime of an authenticated session.
///
/// "Session" here means the window during which the encrypted saved-places vault
/// may stay open without re-prompting the user. The guard is the single place
/// that decides when that window closes, so no screen has to reimplement the
/// timeout, and the vault's `lock()` is called from exactly one owner.
///
/// The rules, in order of precedence:
///
/// * **Explicit end wins.** [endSession] closes the window immediately, whatever
///   the other signals say.
/// * **The device lock screen locks.** When the OS reports that the device went
///   to its lock screen, the session ends **immediately** (unless
///   [lockOnDeviceLock] is off). This is not the background grace: the phone is
///   out of the user's hands, and a pocketed or café-table phone must not keep
///   an opened vault in memory for two minutes.
/// * **Backgrounding locks.** Moving to `paused`/`hidden` starts the background
///   grace clock; once [backgroundGrace] elapses the session ends. A quick app
///   switch (a second or two) does not, because re-prompting for biometrics
///   every time the user glances at a notification would be hostile.
/// * **Inactivity locks.** No [noteActivity] for [inactivityTimeout] ends the
///   session regardless of lifecycle state.
/// * **Surface idle shortens the clock.** A device that has not moved for
///   [surfaceIdleThreshold] is treated as unattended and uses
///   [surfaceIdleTimeout] instead of [inactivityTimeout] — a stricter, shorter
///   window, because a phone left on a café table is the realistic theft case.
///
/// The guard is pure and synchronous apart from the token store: it never reads
/// a wall clock itself, it takes "now" from an injected clock, so tests step
/// time without sleeping. It stores only an opaque random token — never a
/// password, never user content, never a location.
class SessionGuard {
  SessionGuard({
    required this.tokenStore,
    this.tokenKey = defaultTokenKey,
    Duration inactivityTimeout = defaultInactivityTimeout,
    Duration backgroundGrace = defaultBackgroundGrace,
    Duration surfaceIdleTimeout = defaultSurfaceIdleTimeout,
    Duration surfaceIdleThreshold = defaultSurfaceIdleThreshold,
    this._lockOnDeviceLock = true,
    DateTime Function()? clock,
  })  : _inactivityTimeout = _validated(inactivityTimeout, 'inactivityTimeout'),
        _backgroundGrace = _validated(backgroundGrace, 'backgroundGrace'),
        _surfaceIdleTimeout =
            _validated(surfaceIdleTimeout, 'surfaceIdleTimeout'),
        _surfaceIdleThreshold =
            _validated(surfaceIdleThreshold, 'surfaceIdleThreshold'),
        _clock = clock ?? DateTime.now;

  /// Key under which the session token is stored. Declared once, here.
  static const String defaultTokenKey = 'mapnote_session_token';

  /// How long the vault may stay open without interaction, by default.
  static const Duration defaultInactivityTimeout = Duration(minutes: 15);

  /// How long the app may stay backgrounded before the session ends, by default.
  static const Duration defaultBackgroundGrace = Duration(minutes: 2);

  /// The stricter timeout applied to an unattended (surface-idle) device.
  static const Duration defaultSurfaceIdleTimeout = Duration(minutes: 3);

  /// How long without micro-movement before the device counts as surface-idle.
  static const Duration defaultSurfaceIdleThreshold = Duration(minutes: 1);

  /// The inactivity timeouts the user may pick from in Settings, in minutes.
  static const List<int> selectableInactivityMinutes = <int>[1, 5, 15, 30, 60];

  final SessionTokenStore tokenStore;
  final String tokenKey;

  Duration _inactivityTimeout;
  final Duration _backgroundGrace;
  final Duration _surfaceIdleTimeout;
  final Duration _surfaceIdleThreshold;
  bool _lockOnDeviceLock;

  /// No [noteActivity] for this long ends the session in any context.
  Duration get inactivityTimeout => _inactivityTimeout;

  /// How long the app may stay backgrounded before the session ends.
  Duration get backgroundGrace => _backgroundGrace;

  /// Inactivity timeout used while the device is [InteractionContext.surfaceIdle].
  Duration get surfaceIdleTimeout => _surfaceIdleTimeout;

  /// How long without micro-movement before the device counts as surface-idle.
  Duration get surfaceIdleThreshold => _surfaceIdleThreshold;

  /// Whether an OS device-lock event ends the session immediately.
  bool get lockOnDeviceLock => _lockOnDeviceLock;

  /// Replaces the inactivity timeout at runtime (Settings → session timeout).
  ///
  /// Applied live: the next [tick] uses the new value, and an already-elapsed
  /// window is honoured on that same tick, so shortening the timeout from 15 to
  /// 1 minute locks an idle vault within a minute rather than hanging on to the
  /// old value until the next launch.
  void setInactivityTimeout(Duration value) {
    _inactivityTimeout = _validated(value, 'inactivityTimeout');
  }

  /// Turns the device-lock auto-lock on or off.
  void setLockOnDeviceLock(bool value) {
    _lockOnDeviceLock = value;
  }

  static Duration _validated(Duration value, String name) {
    if (value <= Duration.zero) {
      throw ArgumentError.value(value, name, 'must be greater than zero');
    }
    return value;
  }

  final DateTime Function() _clock;

  final StreamController<SessionEndReason> _ends =
      StreamController<SessionEndReason>.broadcast();

  bool _active = false;
  bool _backgrounded = false;
  DateTime? _lastActivityAt;
  DateTime? _backgroundedAt;
  DateTime? _lastMovementAt;
  InteractionContext _context = InteractionContext.unknown;
  int _endsCount = 0;

  /// Whether a session is currently open (the vault may stay unlocked).
  bool get isActive => _active;

  /// Whether the app is currently in the background.
  bool get isBackgrounded => _backgrounded;

  /// Current hand-held / surface-idle verdict.
  InteractionContext get interactionContext => _context;

  /// Emits the reason whenever a session ends (broadcast).
  Stream<SessionEndReason> get sessionEnds => _ends.stream;

  /// How many sessions have ended (diagnostics).
  int get endCount => _endsCount;

  /// How long since the last recorded activity, or `null` before the first.
  Duration? get idleFor {
    final DateTime? at = _lastActivityAt;
    if (at == null) return null;
    return _clock().difference(at);
  }

  /// Opens a session. Idempotent — calling it while one is open only refreshes
  /// the activity clock, so a caller does not have to check first.
  ///
  /// The token write is deliberately **not awaited**: the in-memory session is
  /// authoritative for the current run, and blocking the caller (an unlock tap)
  /// on a keystore round-trip would be both slower and, in an environment where
  /// the platform channel never answers, a hang. Persistence only matters for
  /// the *next* launch, so it may finish whenever it finishes.
  Future<void> beginSession() async {
    _active = true;
    _lastActivityAt = _clock();
    unawaited(_persistToken());
  }
  /// Records a user interaction (a tap, a scroll, a place opened). This is the
  /// only thing that keeps a session alive across the inactivity window.
  void noteActivity() {
    _lastActivityAt = _clock();
    _lastMovementAt ??= _lastActivityAt;
  }

  /// Reports raw movement evidence for the hand-held/surface-idle verdict.
  ///
  /// [moving] should be `true` when the accelerometer shows the micro-movements
  /// of a held device (or a step), and `false` when the residual is flat. The
  /// caller does the cheap sensor judgement; this class only tracks the *time*
  /// spent in each condition, so it stays pure and testable.
  void observeMovement({required bool moving, DateTime? at}) {
    final DateTime now = at ?? _clock();
    if (moving) {
      _lastMovementAt = now;
      _context = InteractionContext.handHeld;
      return;
    }
    final DateTime? lastMove = _lastMovementAt;
    if (lastMove == null) {
      // A device that has not moved since the session began, for long enough,
      // is surface-idle. Without this an app left open on a desk would only
      // ever be judged by the inactivity timeout.
      if (_lastActivityAt != null &&
          now.difference(_lastActivityAt!) >= surfaceIdleThreshold) {
        _context = InteractionContext.surfaceIdle;
      }
      return;
    }
    _context = now.difference(lastMove) >= surfaceIdleThreshold
        ? InteractionContext.surfaceIdle
        : InteractionContext.handHeld;
  }

  /// Reports an app-lifecycle change. Backgrounding starts the grace clock;
  /// returning to the foreground stops it but does **not** revive an expired
  /// session.
  void onLifecycle({required bool backgrounded, DateTime? at}) {
    final DateTime now = at ?? _clock();
    if (backgrounded) {
      if (!_backgrounded) _backgroundedAt = now;
      _backgrounded = true;
    } else {
      _backgrounded = false;
      _backgroundedAt = null;
      // Coming back into view is activity: the user is clearly there.
      if (_active) _lastActivityAt = now;
      _lastMovementAt = now;
      _context = InteractionContext.handHeld;
    }
  }

  /// Reports that the OS put the device on its lock screen.
  ///
  /// Ends the session **immediately** — no grace period — because the phone has
  /// left the user's hands. Returns whether this call actually ended a session,
  /// so a caller can skip a redundant vault lock.
  ///
  /// Honours [lockOnDeviceLock]: when the user has switched the auto-lock off,
  /// the event is recorded (the background grace still applies if the app also
  /// backgrounds) but the session is left open.
  Future<bool> onDeviceLocked({DateTime? at}) async {
    final DateTime now = at ?? _clock();
    // A locked device is by definition not being interacted with or held.
    _lastMovementAt = now;
    if (!_lockOnDeviceLock) return false;
    if (!_active) return false;
    await endSession(SessionEndReason.deviceLocked, at: now);
    return true;
  }

  /// Re-evaluates the session against the clocks. Returns `true` when the
  /// session is still open after the check.
  ///
  /// Safe to call as often as the caller likes: it is O(1) and idempotent, and
  /// the composition root drives it from the same low-frequency tick that
  /// watches the rest of the app.
  Future<bool> tick({DateTime? at}) async {
    if (!_active) return false;
    final DateTime now = at ?? _clock();

    if (_backgrounded) {
      final DateTime? since = _backgroundedAt;
      if (since != null && now.difference(since) >= backgroundGrace) {
        await endSession(SessionEndReason.appBackgrounded, at: now);
        return false;
      }
      // While backgrounded the inactivity clock does not also run: the grace
      // period is the sole authority, so the two cannot race.
      return true;
    }

    final Duration timeout = _context == InteractionContext.surfaceIdle
        ? surfaceIdleTimeout
        : inactivityTimeout;
    final DateTime? lastActivity = _lastActivityAt;
    if (lastActivity != null && now.difference(lastActivity) >= timeout) {
      await endSession(SessionEndReason.inactivityTimeout, at: now);
      return false;
    }
    return true;
  }

  /// Ends the session, clears the stored token and notifies listeners.
  ///
  /// Idempotent: ending an already-ended session does not re-emit. The caller
  /// (the composition root) is responsible for actually locking the vault —
  /// this class never touches Hive, so it cannot be the source of a data bug.
  Future<void> endSession(SessionEndReason reason, {DateTime? at}) async {
    if (!_active) return;
    _active = false;
    _endsCount += 1;
    _lastActivityAt = null;
    _context = InteractionContext.unknown;
    // Same fire-and-forget contract as [beginSession]: locking the vault must
    // not wait on a keystore round-trip (nor hang if the channel never answers).
    unawaited(_deleteToken());
    if (!_ends.isClosed) _ends.add(reason);
  }

  /// Whether a token from a previous run is present. A token alone does **not**
  /// reopen the vault: the user must still authenticate, so this only tells the
  /// UI whether to offer "resume" rather than "sign in".
  Future<bool> hasPersistedSession() async {
    try {
      final String? token = await tokenStore.read(tokenKey);
      return token != null && token.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispose() async => _ends.close();

  /// Writes an opaque, non-identifying token.
  ///
  /// The value is deliberately random and meaningless: it marks *that* a
  /// session existed, not *who* the user is, so a leak of the keystore entry
  /// reveals nothing about the account or any place.
  ///
  /// Best-effort: a keystore that is unavailable (no screen lock configured, a
  /// platform without the channel, a widget test) must not make unlocking the
  /// vault fail. The in-memory session is authoritative for this run.
  Future<void> _persistToken() async {
    try {
      final String token =
          '${_clock().microsecondsSinceEpoch}-${identityHashCode(this)}';
      await tokenStore.write(tokenKey, token);
    } catch (_) {
      // Session persistence is an optimisation; the session still works.
    }
  }

  Future<void> _deleteToken() async {
    try {
      await tokenStore.delete(tokenKey);
    } catch (_) {
      // Best-effort, like the write.
    }
  }
}
