import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Minimal Google authorization for the Drive appDataFolder transport.
///
/// OAuth client IDs are public identifiers and are supplied at build time.
/// No client secret or access token is stored in source control or SQLite.
class GoogleDriveOAuthService {
  GoogleDriveOAuthService._();

  static final GoogleDriveOAuthService instance = GoogleDriveOAuthService._();

  static const List<String> driveScopes = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
  ];

  static const String _webClientId =
      String.fromEnvironment('GOOGLE_OAUTH_WEB_CLIENT_ID');
  static const String _iosClientId =
      String.fromEnvironment('GOOGLE_OAUTH_IOS_CLIENT_ID');

  final GoogleSignIn _signIn = GoogleSignIn.instance;
  Future<void>? _initialization;
  GoogleSignInAccount? _account;

  bool get isPlatformSupported =>
      !kIsWeb && _signIn.supportsAuthenticate();

  String? get accountEmail => _account?.email;
  String? get accountName => _account?.displayName;

  Future<void> _ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    String? clientId;
    String? serverClientId;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        if (_webClientId.isEmpty) {
          throw StateError(
            'Google OAuth is not configured. Add '
            'GOOGLE_OAUTH_WEB_CLIENT_ID to the Android build.',
          );
        }
        // Android's Google Sign-In SDK expects the OAuth Web client ID here.
        serverClientId = _webClientId;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        if (_iosClientId.isEmpty) {
          throw StateError(
            'Google OAuth is not configured. Add '
            'GOOGLE_OAUTH_IOS_CLIENT_ID to the Apple-platform build and '
            'register its reversed client ID URL scheme.',
          );
        }
        clientId = _iosClientId;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'Google Drive sign-in is not configured for this platform yet.',
        );
    }

    await _signIn.initialize(
      clientId: clientId,
      serverClientId: serverClientId,
    );
  }

  /// Restores a previously authenticated account without opening consent UI.
  Future<GoogleDriveAccount?> restoreAccount() async {
    await _ensureInitialized();
    if (!_signIn.supportsAuthenticate()) return null;
    _account ??= await _signIn.attemptLightweightAuthentication();
    final account = _account;
    return account == null
        ? null
        : GoogleDriveAccount(
            email: account.email,
            displayName: account.displayName,
          );
  }

  /// Starts Google sign-in if necessary and requests only Drive appData access.
  /// Call this from a user-initiated button handler.
  Future<GoogleDriveAccount> signInAndAuthorize() async {
    await _ensureInitialized();
    if (!_signIn.supportsAuthenticate()) {
      throw UnsupportedError(
        'Google sign-in on this platform requires its platform-rendered '
        'Google Sign-In button or a dedicated OAuth redirect flow.',
      );
    }

    _account ??= await _signIn.attemptLightweightAuthentication();
    _account ??= await _signIn.authenticate(scopeHint: driveScopes);

    final account = _account!;
    var authorization =
        await account.authorizationClient.authorizationForScopes(driveScopes);
    authorization ??=
        await account.authorizationClient.authorizeScopes(driveScopes);

    if (authorization.accessToken.isEmpty) {
      throw StateError('Google returned an empty Drive access token.');
    }

    return GoogleDriveAccount(
      email: account.email,
      displayName: account.displayName,
    );
  }

  /// Obtains a current SDK-managed access token for the Drive transport.
  ///
  /// Native SDKs may renew cached authorization. If the SDK cannot provide a
  /// valid token, the user must reconnect from the foreground Sync Center.
  Future<String> accessToken() async {
    await _ensureInitialized();
    _account ??= await _signIn.attemptLightweightAuthentication();
    final account = _account;
    if (account == null) {
      throw StateError('Connect a Google account before syncing.');
    }

    final authorization =
        await account.authorizationClient.authorizationForScopes(driveScopes);
    if (authorization == null || authorization.accessToken.isEmpty) {
      throw StateError(
        'Google Drive authorization expired. Reconnect Google Drive and retry.',
      );
    }
    return authorization.accessToken;
  }

  /// Disconnects the account and asks Google to revoke this app's authorization.
  Future<void> disconnect() async {
    await _ensureInitialized();
    await _signIn.disconnect();
    _account = null;
  }
}

class GoogleDriveAccount {
  const GoogleDriveAccount({required this.email, this.displayName});

  final String email;
  final String? displayName;
}
