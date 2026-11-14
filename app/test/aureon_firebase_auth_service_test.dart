import 'package:flutter_test/flutter_test.dart';
import 'package:aureon/src/auth/aureon_firebase_auth_service.dart';

class _FakeSecrets implements AureonAuthSecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _FakeTransport implements AureonFirebaseAuthTransport {
  final calls = <({Uri uri, Map<String, Object?> body, bool form})>[];
  final responses = <Map<String, Object?>>[];
  Object? nextError;
  @override
  Future<Map<String, Object?>> post(Uri uri, {
    required Map<String, Object?> body,
    bool formEncoded = false,
  }) async {
    calls.add((uri: uri, body: body, form: formEncoded));
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
    if (responses.isEmpty) throw StateError('No fake Firebase response queued.');
    return responses.removeAt(0);
  }
}

void main() {
  const config = AureonFirebaseAuthConfig(apiKey: 'test-public-api-key', projectId: 'aureon-test');
  late _FakeSecrets secrets;
  late _FakeTransport transport;
  late AureonFirebaseAuthService auth;

  setUp(() {
    secrets = _FakeSecrets();
    transport = _FakeTransport();
    auth = AureonFirebaseAuthService(config: config, transport: transport, secretStore: secrets);
  });

  const scope = 'YXVyZW9uLXRlc3Q';
  const activeUidKey = 'aureon.firebase.$scope.active_uid.v2';
  const refreshKey = 'aureon.firebase.$scope.user-123.refresh_token.v2';
  const emailKey = 'aureon.firebase.$scope.user-123.email.v2';

  Map<String, Object?> signInResponse({bool verified = false}) => {
    'idToken': 'firebase-id-token',
    'refreshToken': 'firebase-refresh-token',
    'localId': 'user-123',
    'email': 'owner@example.com',
    'expiresIn': '3600',
    'emailVerified': verified,
  };

  test('sign-in stores only refresh token and email, never password or ID token', () async {
    transport.responses.add(signInResponse());
    final session = await auth.signIn(email: 'owner@example.com', password: 'correct horse');
    expect(session.user.emailVerified, isFalse);
    expect(secrets.values.values, contains('firebase-refresh-token'));
    expect(secrets.values.values, isNot(contains('correct horse')));
    expect(secrets.values.values, isNot(contains('firebase-id-token')));
    expect(transport.calls.single.uri.host, 'identitytoolkit.googleapis.com');
    expect(transport.calls.single.body['password'], 'correct horse');
  });

  test('create account requests email verification', () async {
    transport.responses
      ..add(signInResponse())
      ..add(signInResponse())
      ..add({'email': 'owner@example.com'});
    await auth.createAccount(
      email: 'owner@example.com',
      password: 'correct horse',
      displayName: 'AureonUser',
    );
    expect(transport.calls.map((call) => call.uri.path), [
      '/v1/accounts:signUp',
      '/v1/accounts:update',
      '/v1/accounts:sendOobCode',
    ]);
    expect(transport.calls[1].body['displayName'], 'AureonUser');
    expect(transport.calls.last.body['requestType'], 'VERIFY_EMAIL');
  });

  test('duplicate email registration preserves Firebase EMAIL_EXISTS code', () async {
    transport.nextError = const AureonFirebaseAuthException(
      'EMAIL_EXISTS',
      'This email is already registered.',
    );
    await expectLater(
      auth.createAccount(email: 'owner@example.com', password: 'correct horse', displayName: 'AureonUser'),
      throwsA(isA<AureonFirebaseAuthException>().having(
        (error) => error.code,
        'code',
        'EMAIL_EXISTS',
      )),
    );
    expect(transport.calls.single.uri.path, '/v1/accounts:signUp');
  });

  test('password reset sends Firebase PASSWORD_RESET action for normalized email', () async {
    transport.responses.add({'email': 'owner@example.com'});
    await auth.sendPasswordResetEmail(email: ' owner@example.com ');
    expect(transport.calls.single.uri.path, '/v1/accounts:sendOobCode');
    expect(transport.calls.single.body, {
      'requestType': 'PASSWORD_RESET',
      'email': 'owner@example.com',
    });
  });

  test('password reset rejects malformed email before contacting Firebase', () async {
    await expectLater(
      auth.sendPasswordResetEmail(email: 'not-an-email'),
      throwsArgumentError,
    );
    expect(transport.calls, isEmpty);
  });

  test('passwordless sign-in requests a Firebase email action link', () async {
    transport.responses.add({'email': 'owner@example.com'});
    await auth.sendPasswordlessSignInLink(email: ' owner@example.com ');
    expect(transport.calls.single.uri.path, '/v1/accounts:sendOobCode');
    expect(transport.calls.single.body, {
      'requestType': 'EMAIL_SIGNIN',
      'email': 'owner@example.com',
      'continueUrl': 'https://aureon-test.firebaseapp.com',
      'canHandleCodeInApp': true,
    });
  });

  test('passwordless sign-in exchanges only a matching Firebase email link', () async {
    transport.responses.add(signInResponse(verified: true));
    final session = await auth.signInWithEmailLink(
      email: 'owner@example.com',
      emailLink: 'https://aureon-test.firebaseapp.com/__/auth/action?apiKey=test-public-api-key&mode=signIn&oobCode=one-time-code',
    );
    expect(session.user.localId, 'user-123');
    expect(session.user.emailVerified, isTrue);
    expect(transport.calls.single.uri.path, '/v1/accounts:signInWithEmailLink');
    expect(transport.calls.single.body, {
      'email': 'owner@example.com',
      'oobCode': 'one-time-code',
    });
    expect(secrets.values.values, contains('firebase-refresh-token'));
  });

  test('passwordless sign-in rejects links from another Firebase project', () async {
    await expectLater(
      auth.signInWithEmailLink(
        email: 'owner@example.com',
        emailLink: 'https://other.firebaseapp.com/__/auth/action?apiKey=wrong-key&mode=signIn&oobCode=code',
      ),
      throwsFormatException,
    );
    expect(transport.calls, isEmpty);
  });

  test('expired session refreshes through Secure Token API and rotates refresh token', () async {
    secrets.values[activeUidKey] = 'user-123';
    secrets.values[refreshKey] = 'old-refresh';
    secrets.values[emailKey] = 'owner@example.com';
    transport.responses.add({
      'id_token': 'new-id-token',
      'refresh_token': 'rotated-refresh',
      'user_id': 'user-123',
      'expires_in': '3600',
    });
    expect(await auth.getIdToken(), 'new-id-token');
    expect(secrets.values[refreshKey], 'rotated-refresh');
    expect(transport.calls.single.form, isTrue);
    expect(transport.calls.single.body['grant_type'], 'refresh_token');
  });

  test('concurrent callers share one refresh-token rotation', () async {
    secrets.values[activeUidKey] = 'user-123';
    secrets.values[refreshKey] = 'old-refresh';
    secrets.values[emailKey] = 'owner@example.com';
    transport.responses.add({
      'id_token': 'single-flight-id-token',
      'refresh_token': 'single-flight-refresh',
      'user_id': 'user-123',
      'expires_in': '3600',
    });
    final tokens = await Future.wait([auth.getIdToken(), auth.getIdToken()]);
    expect(tokens, ['single-flight-id-token', 'single-flight-id-token']);
    expect(transport.calls, hasLength(1));
    expect(secrets.values[refreshKey], 'single-flight-refresh');
  });

  test('email verification lookup refreshes account claim source', () async {
    transport.responses
      ..add(signInResponse())
      ..add({
        'id_token': 'lookup-id-token',
        'refresh_token': 'lookup-refresh',
        'user_id': 'user-123',
        'expires_in': '3600',
      })
      ..add({
        'users': [
          {'localId': 'user-123', 'email': 'owner@example.com', 'emailVerified': true}
        ]
      })
      ..add({
        'id_token': 'verified-id-token',
        'refresh_token': 'rotated-refresh',
        'user_id': 'user-123',
        'expires_in': '3600',
      });
    await auth.signIn(email: 'owner@example.com', password: 'correct horse');
    final user = await auth.reloadUser();
    await auth.getIdToken(forceRefresh: true);
    expect(user.emailVerified, isTrue);
    expect(auth.currentUser?.emailVerified, isTrue);
    expect(auth.currentSession?.idToken, 'verified-id-token');
  });

  test('reauthentication refreshes the same Firebase identity', () async {
    transport.responses
      ..add(signInResponse())
      ..add(signInResponse(verified: true));
    await auth.signIn(email: 'owner@example.com', password: 'initial-password');
    final refreshed = await auth.reauthenticate(password: 'fresh-password');
    expect(refreshed.user.localId, 'user-123');
    expect(refreshed.user.emailVerified, isTrue);
    expect(transport.calls.last.uri.path, '/v1/accounts:signInWithPassword');
    expect(transport.calls.last.body['email'], 'owner@example.com');
  });

  test('sign-out removes persisted refresh token and local session', () async {
    transport.responses.add(signInResponse());
    await auth.signIn(email: 'owner@example.com', password: 'correct horse');
    await auth.signOut();
    expect(auth.currentSession, isNull);
    expect(secrets.values, isEmpty);
  });

  test('unconfigured Firebase fails closed', () async {
    final disabled = AureonFirebaseAuthService(
      config: const AureonFirebaseAuthConfig(apiKey: '', projectId: ''),
      transport: transport,
      secretStore: secrets,
    );
    await expectLater(
      disabled.signIn(email: 'x@example.com', password: 'password123'),
      throwsStateError,
    );
  });
}
