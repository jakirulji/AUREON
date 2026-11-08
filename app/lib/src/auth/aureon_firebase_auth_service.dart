import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AureonFirebaseAuthConfig {
  const AureonFirebaseAuthConfig({
    required this.apiKey,
    required this.projectId,
  });

  final String apiKey;
  final String projectId;

  static const fromEnvironment = AureonFirebaseAuthConfig(
    apiKey: String.fromEnvironment('AUREON_FIREBASE_API_KEY'),
    projectId: String.fromEnvironment('AUREON_FIREBASE_PROJECT_ID'),
  );

  bool get isConfigured => apiKey.trim().isNotEmpty &&
      projectId.trim().isNotEmpty &&
      !projectId.contains('REPLACE_');
}

class AureonFirebaseUser {
  const AureonFirebaseUser({
    required this.localId,
    required this.email,
    required this.emailVerified,
  });

  final String localId;
  final String email;
  final bool emailVerified;
}

class AureonFirebaseSession {
  const AureonFirebaseSession({
    required this.user,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final AureonFirebaseUser user;
  final String idToken;
  final String refreshToken;
  final DateTime expiresAt;

  bool get isExpiring =>
      !expiresAt.isAfter(DateTime.now().toUtc().add(const Duration(seconds: 60)));
}

class AureonFirebaseAuthException implements Exception {
  const AureonFirebaseAuthException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => '$message ($code)';
}

abstract interface class AureonFirebaseAuthTransport {
  Future<Map<String, Object?>> post(
    Uri uri, {
    required Map<String, String> body,
    bool formEncoded = false,
  });
}

class AureonIoFirebaseAuthTransport implements AureonFirebaseAuthTransport {
  AureonIoFirebaseAuthTransport({HttpClient? client})
      : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<Map<String, Object?>> post(
    Uri uri, {
    required Map<String, String> body,
    bool formEncoded = false,
  }) async {
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw ArgumentError('Firebase Authentication must use HTTPS.');
    }
    final request = await _client.postUrl(uri).timeout(const Duration(seconds: 20));
    if (formEncoded) {
      request.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      request.write(body.entries
          .map((entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
          .join('&'));
    } else {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/json')
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
    final response = await request.close().timeout(const Duration(seconds: 30));
    final bytes = await response.fold<List<int>>(
      <int>[],
      (all, chunk) {
        if (all.length + chunk.length > 256 * 1024) {
          throw const FormatException('Firebase response exceeded the size limit.');
        }
        return all..addAll(chunk);
      },
    );
    final text = utf8.decode(bytes);
    Map<String, Object?> decoded = <String, Object?>{};
    if (text.isNotEmpty) {
      final value = jsonDecode(text);
      if (value is! Map) throw const FormatException('Firebase returned invalid JSON.');
      decoded = value.cast<String, Object?>();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      final message = error is Map ? error['message'] : null;
      final code = message is String ? message : 'AUTH_REQUEST_FAILED';
      throw AureonFirebaseAuthException(code, _friendlyError(code));
    }
    return decoded;
  }

  void close() => _client.close(force: true);
}

abstract interface class AureonAuthSecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class AureonPlatformAuthSecretStore implements AureonAuthSecretStore {
  AureonPlatformAuthSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Firebase Identity Toolkit + Secure Token REST integration. Only the
/// long-lived refresh token is persisted, using Android Keystore / Windows
/// DPAPI-backed secure storage. Passwords and ID tokens are never persisted.
class AureonFirebaseAuthService {
  AureonFirebaseAuthService({
    AureonFirebaseAuthConfig config = AureonFirebaseAuthConfig.fromEnvironment,
    AureonFirebaseAuthTransport? transport,
    AureonAuthSecretStore? secretStore,
  })  : _config = config,
        _transport = transport ?? AureonIoFirebaseAuthTransport(),
        _secrets = secretStore ?? AureonPlatformAuthSecretStore();

  final AureonFirebaseAuthConfig _config;
  final AureonFirebaseAuthTransport _transport;
  final AureonAuthSecretStore _secrets;
  AureonFirebaseSession? _session;

  static const _refreshKey = 'aureon.firebase.refresh_token.v1';
  static const _emailKey = 'aureon.firebase.email.v1';

  bool get isConfigured => _config.isConfigured;
  AureonFirebaseSession? get currentSession => _session;
  AureonFirebaseUser? get currentUser => _session?.user;

  Uri _identityUri(String method) => Uri.https(
        'identitytoolkit.googleapis.com',
        '/v1/$method',
        {'key': _config.apiKey},
      );

  Uri get _refreshUri => Uri.https(
        'securetoken.googleapis.com',
        '/v1/token',
        {'key': _config.apiKey},
      );

  void _requireConfiguration() {
    if (!isConfigured) {
      throw StateError(
        'Firebase is not configured. Build with AUREON_FIREBASE_API_KEY and AUREON_FIREBASE_PROJECT_ID.',
      );
    }
  }

  Future<AureonFirebaseSession> _sessionFromResponse(
    Map<String, Object?> response,
  ) async {
    final idToken = response['idToken'];
    final refreshToken = response['refreshToken'];
    final localId = response['localId'];
    final email = response['email'];
    if (idToken is! String ||
        refreshToken is! String ||
        localId is! String ||
        email is! String) {
      throw const FormatException('Firebase authentication response is incomplete.');
    }
    final expiresIn = int.tryParse(response['expiresIn']?.toString() ?? '') ?? 3600;
    final verified = response['emailVerified'] == true;
    final session = AureonFirebaseSession(
      user: AureonFirebaseUser(
        localId: localId,
        email: email,
        emailVerified: verified,
      ),
      idToken: idToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().toUtc().add(Duration(seconds: expiresIn)),
    );
    _session = session;
    await _secrets.write(_refreshKey, refreshToken);
    await _secrets.write(_emailKey, email);
    return session;
  }

  Future<AureonFirebaseSession> createAccount({
    required String email,
    required String password,
  }) async {
    _requireConfiguration();
    if (password.length < 8) {
      throw const AureonFirebaseAuthException(
        'WEAK_PASSWORD',
        'Use a password with at least 8 characters.',
      );
    }
    final response = await _transport.post(
      _identityUri('accounts:signUp'),
      body: {'email': email.trim(), 'password': password, 'returnSecureToken': 'true'},
    );
    final session = await _sessionFromResponse(response);
    await sendVerificationEmail();
    return session;
  }

  Future<AureonFirebaseSession> signIn({
    required String email,
    required String password,
  }) async {
    _requireConfiguration();
    final response = await _transport.post(
      _identityUri('accounts:signInWithPassword'),
      body: {'email': email.trim(), 'password': password, 'returnSecureToken': 'true'},
    );
    return _sessionFromResponse(response);
  }

  Future<void> sendVerificationEmail() async {
    _requireConfiguration();
    final token = await getIdToken();
    await _transport.post(
      _identityUri('accounts:sendOobCode'),
      body: {'requestType': 'VERIFY_EMAIL', 'idToken': token},
    );
  }

  Future<AureonFirebaseUser> reloadUser() async {
    _requireConfiguration();
    final token = await getIdToken(forceRefresh: true);
    final response = await _transport.post(
      _identityUri('accounts:lookup'),
      body: {'idToken': token},
    );
    final users = response['users'];
    if (users is! List || users.isEmpty || users.first is! Map) {
      throw const FormatException('Firebase user lookup returned no user.');
    }
    final user = (users.first as Map).cast<String, Object?>();
    final localId = user['localId'];
    final email = user['email'];
    if (localId is! String || email is! String) {
      throw const FormatException('Firebase user profile is incomplete.');
    }
    final updated = AureonFirebaseUser(
      localId: localId,
      email: email,
      emailVerified: user['emailVerified'] == true,
    );
    final old = _session;
    if (old != null) {
      _session = AureonFirebaseSession(
        user: updated,
        idToken: old.idToken,
        refreshToken: old.refreshToken,
        expiresAt: old.expiresAt,
      );
    }
    return updated;
  }

  /// Password reauthentication obtains a fresh auth_time claim. The password
  /// is sent only to Firebase over HTTPS and is not retained by this service.
  Future<AureonFirebaseSession> reauthenticate({
    required String password,
  }) async {
    final user = currentUser;
    if (user == null) throw StateError('Sign in before reauthentication.');
    return signIn(email: user.email, password: password);
  }

  Future<String> getIdToken({bool forceRefresh = false}) async {
    _requireConfiguration();
    var session = _session;
    if (session == null) {
      final refresh = await _secrets.read(_refreshKey);
      if (refresh == null || refresh.isEmpty) {
        throw StateError('Sign in to AUREON first.');
      }
      session = await _refreshSession(refresh);
    } else if (forceRefresh || session.isExpiring) {
      session = await _refreshSession(session.refreshToken);
    }
    return session.idToken;
  }

  Future<AureonFirebaseSession> restoreSession() async {
    _requireConfiguration();
    final refresh = await _secrets.read(_refreshKey);
    if (refresh == null || refresh.isEmpty) {
      throw StateError('No saved AUREON session exists.');
    }
    return _refreshSession(refresh);
  }

  Future<AureonFirebaseSession> _refreshSession(String refreshToken) async {
    final response = await _transport.post(
      _refreshUri,
      formEncoded: true,
      body: {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
    );
    final idToken = response['id_token'];
    final nextRefresh = response['refresh_token'];
    final localId = response['user_id'];
    if (idToken is! String || nextRefresh is! String || localId is! String) {
      throw const FormatException('Firebase refresh response is incomplete.');
    }
    final email = await _secrets.read(_emailKey) ?? '';
    final previouslyVerified = _session?.user.emailVerified ?? false;
    final session = AureonFirebaseSession(
      user: AureonFirebaseUser(localId: localId, email: email, emailVerified: previouslyVerified),
      idToken: idToken,
      refreshToken: nextRefresh,
      expiresAt: DateTime.now().toUtc().add(
        Duration(seconds: int.tryParse(response['expires_in']?.toString() ?? '') ?? 3600),
      ),
    );
    _session = session;
    await _secrets.write(_refreshKey, nextRefresh);
    return session;
  }

  Future<void> signOut() async {
    _session = null;
    await _secrets.delete(_refreshKey);
    await _secrets.delete(_emailKey);
  }

  static String _friendlyError(String code) {
    if (code.startsWith('EMAIL_EXISTS')) return 'This email is already registered.';
    if (code.startsWith('INVALID_EMAIL')) return 'Enter a valid email address.';
    if (code.startsWith('INVALID_LOGIN_CREDENTIALS') ||
        code.startsWith('EMAIL_NOT_FOUND') ||
        code.startsWith('INVALID_PASSWORD')) return 'Email or password is incorrect.';
    if (code.startsWith('WEAK_PASSWORD')) return 'Password does not meet Firebase requirements.';
    if (code.startsWith('TOO_MANY_ATTEMPTS')) return 'Too many attempts. Wait and try again.';
    if (code.startsWith('USER_DISABLED')) return 'This account has been disabled.';
    if (code.startsWith('TOKEN_EXPIRED') || code.startsWith('INVALID_REFRESH_TOKEN')) {
      return 'Your session expired. Sign in again.';
    }
    if (code.startsWith('OPERATION_NOT_ALLOWED')) return 'Email/password sign-in is not enabled in Firebase.';
    return 'Firebase Authentication request failed.';
  }
}
