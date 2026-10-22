import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/config/app_config.dart';
import 'auth_service.dart';

/// [AuthService] backed by the official `google_sign_in` plugin (v7 API).
class GoogleAuthService implements AuthService {
  GoogleAuthService();

  bool _initialized = false;
  GoogleSignInAccount? _account;
  AuthUser? _user;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await GoogleSignIn.instance.initialize(
        clientId: AppConfig.googleIosClientId.isEmpty
            ? null
            : AppConfig.googleIosClientId,
        serverClientId: AppConfig.googleServerClientId.isEmpty
            ? null
            : AppConfig.googleServerClientId,
      );
      _initialized = true;
    } on GoogleSignInException catch (e) {
      debugPrint(
        'MapNote GoogleSignIn.initialize failed: '
        'code=${e.code.name} description=${e.description}',
      );
      rethrow;
    }
  }

  @override
  AuthUser? get currentUser => _user;

  @override
  bool get isSignedIn => _account != null;

  @override
  Future<AuthUser?> signInSilently() async {
    await initialize();
    try {
      // google_sign_in v7: `signInSilently()` doesn't exist. Use lightweight
      // authentication first (non-interactive). If unavailable, try authenticate
      // with `signIn`? No, that would prompt. We'll fall back to lightweight
      // attempt; if it returns null, there is no stored session to reuse.
      final Future<GoogleSignInAccount?>? attempt = GoogleSignIn.instance
          .attemptLightweightAuthentication();
      if (attempt == null) return null;
      final GoogleSignInAccount? account = await attempt;
      if (account == null) {
        _account = null;
        _user = null;
        return null;
      }
      _account = account;
      final GoogleSignInAccount a = account;
      _user = _toUser(a);

      // Validate (and, when possible, refresh) the Drive token in the
      // background. The user is already on the Home screen, so this must never
      // prompt: only a non-interactive check is attempted.
      await _validateDriveAccess(a);
      return _user;
    } on GoogleSignInException catch (e) {
      debugPrint(
        'MapNote GoogleSignIn.signInSilently failed: '
        'code=${e.code.name} description=${e.description}',
      );
      return null;
    }
  }

  /// Best-effort, non-interactive Drive authorization check. Never prompts the
  /// user and never throws; a missing token simply leaves the session as-is.
  Future<void> _validateDriveAccess(GoogleSignInAccount account) async {
    try {
      await account.authorizationClient.authorizationForScopes(
        AppConfig.driveScopes,
      );
    } on GoogleSignInException catch (e) {
      debugPrint(
        'MapNote Drive token validation failed: '
        'code=${e.code.name} description=${e.description}',
      );
    }
  }

  @override
  Future<AuthUser> signIn() async {
    await initialize();
    try {
      // Try the non-interactive path first: if the platform still has a
      // restorable credential (e.g. a chooser dismissal left the session
      // half-alive), reuse it instead of raising the Credential Manager
      // chooser again — the chooser is what triggers "Account reauth
      // failed" on some devices/accounts.
      GoogleSignInAccount? account;
      final Future<GoogleSignInAccount?>? lightweight =
          GoogleSignIn.instance.attemptLightweightAuthentication();
      if (lightweight != null) {
        account = await lightweight;
      }
      account ??= await GoogleSignIn.instance.authenticate();
      _account = account;
      // Build the user into a final local before the `await` below so the
      // non-null value cannot be lost to a concurrent mutation of `_user`.
      final AuthUser user = _toUser(account);
      _user = user;
      await _ensureAuthorized(account);
      return user;
    } on GoogleSignInException catch (e) {
      debugPrint(
        'MapNote GoogleSignIn.signIn failed: '
        'code=${e.code.name} description=${e.description}',
      );
      throw AuthException('${e.code.name}: ${e.description ?? ''}'.trim());
    }
  }

  Future<void> _ensureAuthorized(GoogleSignInAccount account) async {
    final GoogleSignInAuthorizationClient client = account.authorizationClient;
    final GoogleSignInClientAuthorization? existing = await client
        .authorizationForScopes(AppConfig.driveScopes);
    if (existing == null) {
      await client.authorizeScopes(AppConfig.driveScopes);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } on GoogleSignInException {
      // Ignore: we clear local state regardless.
    } finally {
      _account = null;
      _user = null;
    }
  }

  @override
  Future<Map<String, String>?> authorizationHeaders({
    bool prompt = false,
  }) async {
    final GoogleSignInAccount? account = _account;
    if (account == null) return null;
    try {
      return await account.authorizationClient.authorizationHeaders(
        AppConfig.driveScopes,
        promptIfNecessary: prompt,
      );
    } on GoogleSignInException {
      return null;
    }
  }

  AuthUser _toUser(GoogleSignInAccount account) {
    return AuthUser(
      id: account.id,
      email: account.email,
      displayName: account.displayName,
      photoUrl: account.photoUrl,
    );
  }
}
