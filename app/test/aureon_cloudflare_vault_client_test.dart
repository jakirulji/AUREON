import 'dart:convert';
import 'dart:io';

import 'package:aureon/src/backup/aureon_cloudflare_vault_client.dart';
import 'package:aureon/src/backup/aureon_credential_vault_store.dart';
import 'package:aureon/src/backup/aureon_recovery_key_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:webcrypto/webcrypto.dart' as webcrypto;
import 'package:flutter_test/flutter_test.dart';

class _MemoryDekStore implements AureonVaultDekStore {
  final Map<String, List<int>> values = {};
  String _key(String vaultId, int generation) => '$vaultId:$generation';
  @override
  Future<List<int>?> read(String vaultId, int generation) async =>
      values[_key(vaultId, generation)]?.toList();
  @override
  Future<void> write(String vaultId, int generation, List<int> dek) async {
    values[_key(vaultId, generation)] = dek.toList();
  }
  @override
  Future<void> delete(String vaultId, int generation) async {
    values.remove(_key(vaultId, generation));
  }
}

class _FakeTransport implements AureonVaultHttpTransport {
  final calls = <String>[];
  Map<String, Object?>? uploaded;
  Map<String, Object?>? remote;
  bool failUpload = false;\n  List<int> expectedDek = List<int>.generate(32, (i) => i + 1);

  @override
  Future<Map<String, Object?>> send({
    required String method,
    required Uri uri,
    required String idToken,
    Map<String, Object?>? body,
  }) async {
    calls.add('$method ${uri.path}');
    expect(idToken, 'verified-firebase-id-token');
    if (uri.scheme != 'https') throw StateError('HTTPS required');
    if (method == 'POST' && uri.path.endsWith('/v1/vault/envelope')) {
      expect(body?['dek'], isA<String>());
      return {'envelope': {
        'formatVersion': 1,
        'rootKeyVersion': 1,
        'algorithm': 'HKDF-SHA-256/AES-256-GCM',
        'salt': base64Url.encode(List<int>.filled(32, 1)).replaceAll('=', ''),
        'nonce': base64Url.encode(List<int>.filled(12, 2)).replaceAll('=', ''),
        'cipherText': base64Url.encode(List<int>.filled(48, 3)).replaceAll('=', ''),
      }};
    }
    if (method == 'PUT' && uri.path.endsWith('/v1/vault/snapshot')) {
      if (failUpload) throw const AureonCloudflareApiException(503, 'offline');
      uploaded = body;
      remote = body;
      return {'ok': true};
    }
    if (method == 'POST' && uri.path.endsWith('/v1/vault/recovery/challenge')) {
      return {'challengeId': 'challenge-1', 'challenge': 'single-use-challenge', 'generation': 1};
    }
    if (method == 'POST' && uri.path.endsWith('/v1/vault/recovery/rewrap')) {
      final deviceJwk = body?['devicePublicKey'] as Map<String, Object?>;
      final serverPair = await webcrypto.EcdhPrivateKey.generateKey(webcrypto.EllipticCurve.p256);
      final serverPublicJwk = await serverPair.publicKey.exportJsonWebKey();
      final devicePublic = await webcrypto.EcdhPublicKey.importJsonWebKey(
        deviceJwk.cast<String, dynamic>(),
        webcrypto.EllipticCurve.p256,
      );
      final sharedBytes = await serverPair.privateKey.deriveBits(256, devicePublic);
      final salt = List<int>.filled(32, 7);
      final nonce = List<int>.filled(12, 8);
      final info = utf8.encode('AUREON|DEVICE-BOUND-VAULT-DEK|v1|vault-cloud-recovery|1');
      final wrappingKey = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(sharedBytes), nonce: salt, info: info,
      );
      final box = await AesGcm.with256bits().encrypt(
        expectedDek, secretKey: wrappingKey, nonce: nonce, aad: info,
      );
      sharedBytes.fillRange(0, sharedBytes.length, 0);

      final combined = [...box.cipherText, ...box.mac.bytes];
      return {'deviceBoundEnvelope': {
        'formatVersion': 1,
        'algorithm': 'ECDH-P256/HKDF-SHA-256/AES-256-GCM',
        'vaultId': 'vault-cloud-recovery',
        'generation': 1,
        'serverEphemeralPublicKey': {
          'kty': 'EC', 'crv': 'P-256',
          'x': serverPublicJwk['x'],
          'y': serverPublicJwk['y'],
        },
        'salt': base64Url.encode(salt).replaceAll('=', ''),
        'nonce': base64Url.encode(nonce).replaceAll('=', ''),
        'cipherText': base64Url.encode(combined).replaceAll('=', ''),
      }};
    }
    if (method == 'GET' && uri.path.endsWith('/v1/vault/snapshot')) {
      final snapshot = remote;
      if (snapshot == null) throw const AureonCloudflareApiException(404, 'not found');
      final hash = await Sha256().hash(utf8.encode(jsonEncode(snapshot)));
      return {
        'snapshot': snapshot,
        'snapshotSha256': hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      };
    }
    throw StateError('Unexpected API call: $method $uri');
  }
}

void main() {
  const token = 'verified-firebase-id-token';
  Future<String?> tokenProvider() async => token;

  test('provisions a Cloudflare envelope then uploads only encrypted bundle', () async {
    final directory = await Directory.systemTemp.createTemp('aureon-cloudflare-sync-');
    final dekStore = _MemoryDekStore();
    final transport = _FakeTransport();
    addTearDown(() async { if (await directory.exists()) await directory.delete(recursive: true); });
    final store = AureonCredentialVaultStore(dekStore: dekStore, rootDirectory: directory);
    final keys = AureonRecoveryKeyService().generateKeySet(vaultId: 'vault-cloud-sync');
    final local = await store.initialize(keys);
    await store.replaceCredentialRecords(keySet: keys, credentialRecords: const [
      {'providerAccountId': 'google-subject-1', 'provider': 'google_drive', 'refreshToken': 'secret-token'},
    ]);
    final client = AureonCloudflareVaultClient(
      baseUrl: 'https://aureon-api.example.workers.dev',
      transport: transport,
    );

    final synced = await store.syncWithCloudflare(client: client, idTokenProvider: tokenProvider);
    expect(synced.cloudflareEnvelope, isNotNull);
    expect(transport.calls, [
      'POST /v1/vault/envelope',
      'PUT /v1/vault/snapshot',
    ]);
    final uploadedText = jsonEncode(transport.uploaded);
    expect(uploadedText, isNot(contains('secret-token')));
    expect(uploadedText, contains('cipherText'));
    expect((await store.loadBundle())?.cloudflareEnvelope, isNotNull);
    expect(local.generation, synced.generation);

    await store.replaceCredentialRecords(keySet: keys, credentialRecords: const [
      {'providerAccountId': 'google-subject-1', 'provider': 'google_drive', 'refreshToken': 'rotated-secret'},
    ]);
    final updated = await store.syncWithCloudflare(client: client, idTokenProvider: tokenProvider);
    expect(updated.cloudflareEnvelope, synced.cloudflareEnvelope);
    expect(transport.calls.where((call) => call.startsWith('POST')).length, 1);
    expect(transport.calls.where((call) => call.startsWith('PUT')).length, 2);
  });

  test('failed upload preserves the locally provisioned envelope for retry', () async {
    final directory = await Directory.systemTemp.createTemp('aureon-cloudflare-retry-');
    final dekStore = _MemoryDekStore();
    final transport = _FakeTransport()..failUpload = true;
    addTearDown(() async { if (await directory.exists()) await directory.delete(recursive: true); });
    final store = AureonCredentialVaultStore(dekStore: dekStore, rootDirectory: directory);
    final keys = AureonRecoveryKeyService().generateKeySet(vaultId: 'vault-cloud-retry');
    await store.initialize(keys);
    final client = AureonCloudflareVaultClient(baseUrl: 'https://aureon-api.example.workers.dev', transport: transport);

    await expectLater(
      store.syncWithCloudflare(client: client, idTokenProvider: tokenProvider),
      throwsA(isA<AureonCloudflareApiException>()),
    );
    expect((await store.loadBundle())?.cloudflareEnvelope, isNotNull);
    transport.failUpload = false;
    await store.syncWithCloudflare(client: client, idTokenProvider: tokenProvider);
    expect(transport.calls.where((call) => call.startsWith('POST')).length, 1);
    expect(transport.calls.where((call) => call.startsWith('PUT')).length, 2);
  });

  test('snapshot download verifies its SHA-256 before returning bundle', () async {
    final directory = await Directory.systemTemp.createTemp('aureon-cloudflare-download-');
    final transport = _FakeTransport();
    addTearDown(() async { if (await directory.exists()) await directory.delete(recursive: true); });
    final source = AureonCredentialVaultStore(dekStore: _MemoryDekStore(), rootDirectory: directory);
    final keys = AureonRecoveryKeyService().generateKeySet(vaultId: 'vault-cloud-download');
    await source.initialize(keys);
    final client = AureonCloudflareVaultClient(baseUrl: 'https://aureon-api.example.workers.dev', transport: transport);
    final bundle = await source.loadBundle();
    transport.remote = {
      ...bundle!.toJson(),
      'cloudflareEnvelope': {
        'formatVersion': 1, 'rootKeyVersion': 1,
        'algorithm': 'HKDF-SHA-256/AES-256-GCM',
        'salt': base64Url.encode(List<int>.filled(32, 1)).replaceAll('=', ''),
        'nonce': base64Url.encode(List<int>.filled(12, 2)).replaceAll('=', ''),
        'cipherText': base64Url.encode(List<int>.filled(48, 3)).replaceAll('=', ''),
      },
    };
    final fetched = await client.fetchSnapshot(vaultId: keys.vaultId, idTokenProvider: tokenProvider);
    expect(fetched.vaultId, keys.vaultId);
    expect(fetched.cloudflareEnvelope, isNotNull);
  });

  test('Cloudflare sync and device-bound restore recover encrypted provider records', () async {
    final sourceDirectory = await Directory.systemTemp.createTemp('aureon-cloudflare-source-');
    final targetDirectory = await Directory.systemTemp.createTemp('aureon-cloudflare-target-');
    final sourceDekStore = _MemoryDekStore();
    final targetDekStore = _MemoryDekStore();
    final transport = _FakeTransport();
    addTearDown(() async {
      if (await sourceDirectory.exists()) await sourceDirectory.delete(recursive: true);
      if (await targetDirectory.exists()) await targetDirectory.delete(recursive: true);
    });
    final source = AureonCredentialVaultStore(dekStore: sourceDekStore, rootDirectory: sourceDirectory);
    final keys = AureonRecoveryKeyService().generateKeySet(vaultId: 'vault-cloud-recovery');
    await source.initialize(keys);
    await source.replaceCredentialRecords(keySet: keys, credentialRecords: const [
      {'providerAccountId': 'google-subject-1', 'provider': 'google_drive', 'refreshToken': 'vaulted-refresh-secret'},
    ]);
    transport.expectedDek = await sourceDekStore.read(keys.vaultId, keys.generation) ?? const [];
    final client = AureonCloudflareVaultClient(
      baseUrl: 'https://aureon-api.example.workers.dev',
      transport: transport,
    );
    await source.syncWithCloudflare(client: client, idTokenProvider: tokenProvider);

    final target = AureonCredentialVaultStore(dekStore: targetDekStore, rootDirectory: targetDirectory);
    final restored = await target.restoreWithCloudflare(
      vaultId: keys.vaultId,
      client: client,
      idTokenProvider: tokenProvider,
    );
    expect(restored.single['providerAccountId'], 'google-subject-1');
    expect(restored.single['refreshToken'], 'vaulted-refresh-secret');
    expect(await targetDekStore.read(keys.vaultId, keys.generation), hasLength(32));
    expect(await target.loadBundle(), isNotNull);
    expect(await target.loadPendingBundle(), isNull);
  });

  test('Cloudflare recovery unwraps a P-256 device-bound DEK envelope', () async {
    final transport = _FakeTransport();
    final client = AureonCloudflareVaultClient(
      baseUrl: 'https://aureon-api.example.workers.dev',
      transport: transport,
    );
    final recovered = await client.recoverVaultDek(
      vaultId: 'vault-cloud-recovery',
      expectedGeneration: 1,
      idTokenProvider: tokenProvider,
    );
    expect(recovered, transport.expectedDek);
    recovered.fillRange(0, recovered.length, 0);
    expect(transport.calls, [
      'POST /v1/vault/recovery/challenge',
      'POST /v1/vault/recovery/rewrap',
    ]);
  });

  test('rejects non-HTTPS API endpoints and missing Firebase tokens', () async {
    expect(
      () => AureonCloudflareVaultClient(baseUrl: 'http://insecure.example'),
      throwsArgumentError,
    );
    final client = AureonCloudflareVaultClient(baseUrl: 'https://aureon-api.example.workers.dev', transport: _FakeTransport());
    await expectLater(
      client.fetchSnapshot(vaultId: 'vault', idTokenProvider: () async => null),
      throwsStateError,
    );
  });
}
