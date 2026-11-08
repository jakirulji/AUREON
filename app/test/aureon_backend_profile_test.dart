import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/src/auth/aureon_backend_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saves a user-owned profile and restores it as active', () async {
    final store = AureonBackendProfileStore();
    final saved = await store.saveProfile(
      name: 'Personal',
      firebaseApiKey: 'public-firebase-client-key',
      firebaseProjectId: 'aureon-test-123',
      workerBaseUrl: 'https://aureon-owner.workers.dev/',
    );

    final restored = await AureonBackendProfileStore().activeProfile();
    expect(restored?.id, saved.id);
    expect(restored?.workerBaseUrl, 'https://aureon-owner.workers.dev');
    expect(restored?.firebaseIssuer,
        'https://securetoken.google.com/aureon-test-123');
    expect(restored?.boundUid, isNull);
  });

  test('binds profile to Firebase issuer, UID and Worker identity', () async {
    final store = AureonBackendProfileStore();
    await store.saveProfile(
      name: 'Personal',
      firebaseApiKey: 'public-firebase-client-key',
      firebaseProjectId: 'aureon-test-123',
      workerBaseUrl: 'https://aureon-owner.workers.dev',
    );

    final bound = await store.bindActiveProfile('firebase-uid-1');
    expect(bound.isBound, isTrue);
    expect(bound.boundIssuer,
        'https://securetoken.google.com/aureon-test-123');
    expect(bound.boundWorkerIdentity, 'https://aureon-owner.workers.dev');

    final again = await store.bindActiveProfile('firebase-uid-1');
    expect(again.boundUid, 'firebase-uid-1');
    expect(() => bound.bindToUid('another-user'), throwsStateError);
  });

  test('supports separate profiles for separate Firebase projects', () async {
    final store = AureonBackendProfileStore();
    final first = await store.saveProfile(
      name: 'Personal',
      firebaseApiKey: 'first-public-key',
      firebaseProjectId: 'aureon-first-123',
      workerBaseUrl: 'https://first.workers.dev',
    );
    final second = await store.saveProfile(
      name: 'Work',
      firebaseApiKey: 'second-public-key',
      firebaseProjectId: 'aureon-second-123',
      workerBaseUrl: 'https://second.workers.dev',
    );

    expect((await store.listProfiles()).map((profile) => profile.id),
        containsAll([first.id, second.id]));
    expect((await store.activeProfile())?.id, second.id);
    await store.activateProfile(first.id);
    expect((await store.activeProfile())?.id, first.id);
  });

  test('rejects insecure or malformed Worker endpoints', () async {
    final store = AureonBackendProfileStore();
    await expectLater(
      store.saveProfile(
        name: 'Unsafe',
        firebaseApiKey: 'public-key',
        firebaseProjectId: 'aureon-test-123',
        workerBaseUrl: 'http://example.workers.dev',
      ),
      throwsArgumentError,
    );
    expect(await store.listProfiles(), isEmpty);
  });

  test('rejects malformed or identity-tampered persisted profiles', () async {
    SharedPreferences.setMockInitialValues({
      'aureon.backend_profiles.v1':
          '[{"id":"p1","name":"P","firebaseApiKey":"key","firebaseProjectId":"aureon-test-123","workerBaseUrl":"https://one.workers.dev","boundUid":"uid-1","boundIssuer":"https://securetoken.google.com/other-project","boundWorkerIdentity":"https://one.workers.dev"}]',
    });
    final store = AureonBackendProfileStore();
    await expectLater(store.listProfiles(), throwsFormatException);
  });
}
