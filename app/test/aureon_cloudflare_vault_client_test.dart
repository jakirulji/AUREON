import 'dart:convert';
import 'dart:io';

import 'package:aureon/src/backup/aureon_cloudflare_vault_client.dart';
import 'package:aureon/src/backup/aureon_credential_vault_store.dart';
import 'package:aureon/src/backup/aureon_recovery_key_service.dart';
import 'package:cryptography/cryptography.dart';
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
  bool failUpload = false;

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
