import 'dart:async';

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
  final calls = <({Uri uri, Map<String, String> body, bool form})>[];
  final responses = <Map<String, Object?>>[];
  Completer<Map<String, Object?>>? pendingResponse;
  @override
  Future<Map<String, Object?>> post(Uri uri, {
    required Map<String, String> body,
    bool formEncoded = false,
  }) async {
    calls.add((uri: uri, body: body, form: formEncoded));
    final pending = pendingResponse;
    if (pending != null) return pending.future;
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
      ..add({'email': 'owner@example.com'});
    await auth.createAccount(email: 'owner@example.com', password: 'correct horse');
    expect(transport.calls.map((call) => call.uri.path), [
      '/v1/accounts:signUp',
      '/v1/accounts:sendOobCode',
    ]);
    expect(transport.calls.last.body['requestType'], 'VERIFY_EMAIL');
  });

  test('expired session refreshes through Secure Token API and rotates refresh token', () async {
    secrets.values['aureon.firebase.refresh_token.v1'] = 'old-refresh';
    secrets.values['aureon.firebase.email.v1'] = 'owner@example.com';
    transport.responses.add({
      'id_token': 'new-id-token',
      'refresh_token': 'rotated-refresh',
      'user_id': 'user-123',
      'expires_in': '3600',
    });
    expect(await auth.getIdToken(), 'new-id-token');
    expect(secrets.values['aureon.firebase.refresh_token.v1'], 'rotated-refresh');
    expect(transport.calls.single.form, isTrue);
    expect(transport.calls.single.body['grant_type'], 'refresh_token');
  });

  test('concurrent callers share one refresh-token rotation', () async {
    secrets.values['aureon.firebase.refresh_token.v1'] = 'old-refresh';
    secrets.values['aureon.firebase.email.v1'] = 'owner@example.com';
    transport.responses.add({
      'id_token': 'single-flight-id-token',
      'refresh_token': 'single-flight-refresh',
      'user_id': 'user-123',
      'expires_in': '3600',
    });
    final tokens = await Future.wait([auth.getIdToken(), auth.getIdToken()]);
    expect(tokens, ['single-flight-id-token', 'single-flight-id-token']);
    expect(transport.calls, hasLength(1));
    expect(secrets.values['aureon.firebase.refresh_token.v1'], 'single-flight-refresh');
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


  test('cold-start restore rotates the saved refresh token without asking for password', () async {
    secrets.values['aureon.firebase.refresh_token.v1'] = 'persisted-refresh';
    secrets.values['aureon.firebase.email.v1'] = 'owner@example.com';
    transport.responses.add({
      'id_token': 'restored-id-token',
      'refresh_token': 'restored-rotated-refresh',
      'user_id': 'user-123',
      'expires_in': '3600',
    });
    final restored = await auth.restoreSession();
    expect(restored.user.localId, 'user-123');
    expect(restored.user.email, 'owner@example.com');
    expect(restored.idToken, 'restored-id-token');
    expect(secrets.values['aureon.firebase.refresh_token.v1'], 'restored-rotated-refresh');
    expect(transport.calls.single.body.containsKey('password'), isFalse);
  });

  test('locking a session preserves its refresh token for later verification retry', () async {
    transport.responses.add(signInResponse());
    await auth.signIn(email: 'owner@example.com', password: 'correct horse');
    auth.lockSession();
    expect(auth.currentSession, isNull);
    expect(secrets.values['aureon.firebase.refresh_token.v1'], 'firebase-refresh-token');

    transport.responses.add({
      'id_token': 'retry-id-token',
      'refresh_token': 'retry-rotated-refresh',
      'user_id': 'user-123',
      'expires_in': '3600',
    });
    final restored = await auth.restoreSession();
    expect(restored.user.localId, 'user-123');
    expect(restored.idToken, 'retry-id-token');
    expect(secrets.values['aureon.firebase.refresh_token.v1'], 'retry-rotated-refresh');
  });

  test('sign-out removes persisted refresh token and local session', () async {
    transport.responses.add(signInResponse());
    await auth.signIn(email: 'owner@example.com', password: 'correct horse');
    await auth.signOut();
    expect(auth.currentSession, isNull);
    expect(secrets.values, isEmpty);
  });

  test('sign-out prevents an in-flight refresh from restoring local credentials', () async {
    secrets.values['aureon.firebase.refresh_token.v1'] = 'old-refresh';
    secrets.values['aureon.firebase.email.v1'] = 'owner@example.com';
    transport.pendingResponse = Completer<Map<String, Object?>>();
    final pendingToken = auth.getIdToken();
    await Future<void>.delayed(Duration.zero);
    await auth.signOut();
    transport.pendingResponse!.complete({
      'id_token': 'late-id-token',
      'refresh_token': 'late-refresh-token',
      'user_id': 'user-123',
      'expires_in': '3600',
    });
    await expectLater(pendingToken, throwsStateError);
    expect(secrets.values, isEmpty);
    expect(auth.currentSession, isNull);
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
