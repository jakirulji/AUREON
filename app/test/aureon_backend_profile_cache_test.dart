import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aureon/src/auth/aureon_backend_profile_cache.dart';

void main() {
  const profile = AureonBackendProfile(
    accountRecoveryId: '0123456789abcdefghijklmnopqrstuv0123456789',
    firebaseApiKey: 'AIzaSyExamplePublicFirebaseClientKey',
    firebaseProjectId: 'owner-project-123',
    firebaseAuthDomain: 'owner-project-123.firebaseapp.com',
    firebaseAppId: '1:123456789:web:abcdef123456',
    workerBaseUrl: 'https://owner-api.example.workers.dev',
    profileVersion: 1,
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('profile round-trips through local cache', () async {
    final cache = AureonBackendProfileCache();
    await cache.write(profile);
    expect((await cache.read())?.toJson(), profile.toJson());
  });


  test('unregistered first-device profile can be cached before Firebase sign-in', () {
    final draft = AureonBackendProfile.fromJson({
      ...profile.toJson(),
      'profileVersion': 0,
      'registered': false,
    });
    expect(draft.registered, isFalse);
    expect(draft.profileVersion, 0);
  });

  test('legacy cached Discovery ID migrates to Account Recovery ID', () {
    final legacy = AureonBackendProfile.fromJson({
      ...profile.toJson(),
      'accountRecoveryId': null,
      'discoveryId': profile.accountRecoveryId,
    });
    expect(legacy.accountRecoveryId, profile.accountRecoveryId);
  });

  test('profile parser rejects insecure Worker URLs', () {
    expect(
      () => AureonBackendProfile.fromJson({
        ...profile.toJson(),
        'workerBaseUrl': 'http://insecure.example.workers.dev',
      }),
      throwsFormatException,
    );
  });

  test('profile parser rejects malformed discovery IDs', () {
    expect(
      () => AureonBackendProfile.fromJson({
        ...profile.toJson(),
        'accountRecoveryId': 'email@example.com',
      }),
      throwsFormatException,
    );
  });

  test('cached profile is retained until explicit profile removal', () async {
    final cache = AureonBackendProfileCache();
    await cache.write(profile);
    await cache.clear();
    expect(await cache.read(), isNull);
  });
}
