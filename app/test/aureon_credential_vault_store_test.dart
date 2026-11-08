import 'dart:convert';
import 'dart:io';

import 'package:aureon/src/backup/aureon_credential_vault_store.dart';
import 'package:aureon/src/backup/aureon_cloudflare_vault_client.dart';
import 'package:cryptography/cryptography.dart';
import 'package:aureon/src/backup/aureon_recovery_key_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryDekStore implements AureonVaultDekStore {
  final Map<String, List<int>> values = {};
  bool failWrites = false;
  String _id(String vaultId, int generation) => '$vaultId:$generation';

  @override
  Future<List<int>?> read(String vaultId, int generation) async =>
      values[_id(vaultId, generation)]?.toList();

  @override
  Future<void> delete(String vaultId, int generation) async {
    values.remove(_id(vaultId, generation));
  }

  @override
  Future<void> write(String vaultId, int generation, List<int> dek) async {
    if (failWrites) throw StateError('Simulated secure-storage failure.');
    values[_id(vaultId, generation)] = dek.toList();
  }
}


class _FakeCloudflareTransport implements AureonVaultHttpTransport {
  Map<String, Object?>? snapshot;
  int uploads = 0;

  String _encode(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  @override
  Future<Map<String, Object?>> send({
    required String method,
    required Uri uri,
    required String idToken,
    Map<String, Object?>? body,
  }) async {
    if (method == 'GET') {
      final current = snapshot;
      if (current == null) {
        throw const AureonCloudflareApiException(404, 'Vault not found.');
      }
      final digest = await Sha256().hash(utf8.encode(jsonEncode(current)));
      final hash = digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      return {'snapshot': current, 'snapshotSha256': hash};
    }
    if (method == 'POST') {
      return {
        'envelope': {
          'formatVersion': 1,
          'rootKeyVersion': 1,
          'algorithm': 'HKDF-SHA-256/AES-256-GCM',
          'salt': _encode(List<int>.filled(32, 1)),
          'nonce': _encode(List<int>.filled(12, 2)),
          'cipherText': _encode(List<int>.filled(48, 3)),
        },
      };
    }
    if (method == 'PUT') {
      snapshot = Map<String, Object?>.from(body!);
      uploads++;
      return {'ok': true};
    }
    throw StateError('Unexpected HTTP method $method');
  }
}

void main() {
  test('portable bundle imports on a fresh device and unlocks with one manual key', () async {
    final sourceDirectory = await Directory.systemTemp.createTemp('aureon-vault-source-');
    final targetDirectory = await Directory.systemTemp.createTemp('aureon-vault-target-');
    final sourceDekStore = _MemoryDekStore();
    final targetDekStore = _MemoryDekStore();
    addTearDown(() async {
      if (await sourceDirectory.exists()) await sourceDirectory.delete(recursive: true);
      if (await targetDirectory.exists()) await targetDirectory.delete(recursive: true);
    });

    final keySet = AureonRecoveryKeyService().generateKeySet(
      vaultId: 'vault-device-transfer-test',
    );
    final source = AureonCredentialVaultStore(
      dekStore: sourceDekStore,
      rootDirectory: sourceDirectory,
    );
    final created = await source.initialize(keySet);
    expect(created.encryptedCredentialRecords, isEmpty);

    final portableBytes = await source.exportBundle();
    final portableText = utf8.decode(portableBytes);
    for (final key in keySet.keys) {
      expect(portableText, isNot(contains(key.value)));
    }
    expect(portableText, isNot(contains('refreshToken')));

    final target = AureonCredentialVaultStore(
      dekStore: targetDekStore,
      rootDirectory: targetDirectory,
    );
    final imported = await target.importBundle(portableBytes);
    expect(imported.vaultId, keySet.vaultId);
    expect(await targetDekStore.read(keySet.vaultId, keySet.generation), isNull);

    final restoredRecords = await target.restoreWithManualKey(
      bundle: imported,
      keySet: keySet,
      manualKeyId: keySet.keys[2].id,
    );
    expect(restoredRecords, isEmpty);
    final restoredDek = await targetDekStore.read(keySet.vaultId, keySet.generation);
    expect(restoredDek, isNotNull);
    expect(restoredDek, hasLength(32));
    expect(await target.loadBundle(), isNotNull);
  });

  test('Cloudflare vault sync is idempotent and refuses a newer remote snapshot', () async {
    final directory = await Directory.systemTemp.createTemp('aureon-cloud-sync-');
    final dekStore = _MemoryDekStore();
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final store = AureonCredentialVaultStore(dekStore: dekStore, rootDirectory: directory);
    final keys = AureonRecoveryKeyService().generateKeySet(vaultId: 'vault-cloud-sync');
    await store.initialize(keys);
    final transport = _FakeCloudflareTransport();
    final client = AureonCloudflareVaultClient(
      baseUrl: 'https://aureon-test.workers.dev',
      transport: transport,
    );
    addTearDown(client.close);

    final first = await store.syncWithCloudflare(
      client: client,
      idTokenProvider: () async => 'firebase-test-token',
    );
    expect(first.cloudflareEnvelope, isNotNull);
    expect(transport.uploads, 1);

    final repeated = await store.syncWithCloudflare(
      client: client,
      idTokenProvider: () async => 'firebase-test-token',
    );
    expect(repeated.createdAtEpochMs, first.createdAtEpochMs);
    expect(transport.uploads, 1);

    transport.snapshot!['createdAtEpochMs'] = first.createdAtEpochMs + 1;
    await expectLater(
      store.syncWithCloudflare(
        client: client,
        idTokenProvider: () async => 'firebase-test-token',
      ),
      throwsStateError,
    );
    expect(transport.uploads, 1);
  });

  test('generation rotation re-encrypts records and removes the old device DEK', () async {
    final directory = await Directory.systemTemp.createTemp('aureon-vault-rotation-');
    final dekStore = _MemoryDekStore();
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final service = AureonCredentialVaultStore(
      dekStore: dekStore,
      rootDirectory: directory,
    );
    final recovery = AureonRecoveryKeyService();
    final oldKeys = recovery.generateKeySet(vaultId: 'vault-generation-rotation');
    await service.initialize(oldKeys);
    final oldBundle = await service.replaceCredentialRecords(
      keySet: oldKeys,
      credentialRecords: const [
        {
          'providerAccountId': 'google-account-1',
          'provider': 'google_drive',
          'refreshToken': 'test-refresh-secret',
        },
      ],
    );

    final plan = await service.prepareRotation(
      currentKeySet: oldKeys,
      currentManualKeyId: oldKeys.keys.first.id,
    );

    expect(plan.keySet.generation, oldKeys.generation + 1);
    expect(plan.bundle.generation, oldBundle.generation + 1);
    expect(plan.bundle.encryptedCredentialRecords, hasLength(1));
    // Preparing a rotation must not invalidate the currently active vault.
    expect(await dekStore.read(oldKeys.vaultId, oldKeys.generation), hasLength(32));
    expect(await service.loadBundle(), isNotNull);
    await service.commitRotation(currentKeySet: oldKeys, plan: plan);
    expect(await dekStore.read(oldKeys.vaultId, oldKeys.generation), isNull);
    expect(await dekStore.read(plan.keySet.vaultId, plan.keySet.generation), hasLength(32));
    final restored = await CredentialVaultCryptoService().restoreBundle(
      bundle: plan.bundle,
      keySet: plan.keySet,
      manualKeyId: plan.keySet.keys.last.id,
    );
    expect(restored.single['refreshToken'], 'test-refresh-secret');
    await expectLater(
      CredentialVaultCryptoService().restoreBundle(
        bundle: plan.bundle,
        keySet: oldKeys,
        manualKeyId: oldKeys.keys.first.id,
      ),
      throwsFormatException,
    );
  });

  test('bundle remains recoverable if device secure storage fails during initialization', () async {
    final directory = await Directory.systemTemp.createTemp('aureon-vault-secure-store-failure-');
    final dekStore = _MemoryDekStore()..failWrites = true;
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final service = AureonCredentialVaultStore(
      dekStore: dekStore,
      rootDirectory: directory,
    );
    final keys = AureonRecoveryKeyService().generateKeySet(
      vaultId: 'vault-secure-store-failure',
    );

    await expectLater(service.initialize(keys), throwsStateError);
    final savedBundle = await service.loadBundle();
    expect(savedBundle, isNotNull);
    expect(await dekStore.read(keys.vaultId, keys.generation), isNull);

    dekStore.failWrites = false;
    final restored = await service.restoreWithManualKey(
      bundle: savedBundle!,
      keySet: keys,
      manualKeyId: keys.keys.first.id,
    );
    expect(restored, isEmpty);
    expect(await dekStore.read(keys.vaultId, keys.generation), hasLength(32));
  });

  test('initialization cannot silently replace an existing vault or DEK', () async {
    final directory = await Directory.systemTemp.createTemp('aureon-vault-init-guard-');
    final dekStore = _MemoryDekStore();
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final service = AureonCredentialVaultStore(
      dekStore: dekStore,
      rootDirectory: directory,
    );
    final keys = AureonRecoveryKeyService().generateKeySet(
      vaultId: 'vault-init-guard',
    );
    final original = await service.initialize(keys);
    final originalDek = await dekStore.read(keys.vaultId, keys.generation);

    await expectLater(service.initialize(keys), throwsStateError);

    expect(await dekStore.read(keys.vaultId, keys.generation), originalDek);
    expect((await service.loadBundle())!.createdAtEpochMs, original.createdAtEpochMs);
  });

  test('unverified imported bundle stays pending and cannot replace active snapshot', () async {
    final directory = await Directory.systemTemp.createTemp('aureon-vault-quarantine-');
    final dekStore = _MemoryDekStore();
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final crypto = CredentialVaultCryptoService();
    final service = AureonCredentialVaultStore(
      dekStore: dekStore,
      rootDirectory: directory,
      crypto: crypto,
    );
    final recovery = AureonRecoveryKeyService();
    final keySet = recovery.generateKeySet(vaultId: 'vault-quarantine-test');
    final active = await service.initialize(keySet);
    final candidate = await crypto.createBundle(
      keySet: keySet,
      vaultDek: List<int>.generate(32, (index) => index + 1),
      credentialRecords: const [],
    );

    final staged = await service.importBundle(
      utf8.encode(jsonEncode(candidate.toJson())),
    );
    expect(staged.createdAtEpochMs, candidate.createdAtEpochMs);
    expect((await service.loadBundle())!.createdAtEpochMs, active.createdAtEpochMs);
    expect((await service.loadPendingBundle())!.createdAtEpochMs, candidate.createdAtEpochMs);

    final wrongKeys = recovery.generateKeySet(vaultId: keySet.vaultId);
    await expectLater(
      service.restoreWithManualKey(
        bundle: staged,
        keySet: wrongKeys,
        manualKeyId: wrongKeys.keys.first.id,
      ),
      throwsFormatException,
    );
    expect((await service.loadBundle())!.createdAtEpochMs, active.createdAtEpochMs);
    expect(await service.loadPendingBundle(), isNotNull);

    await service.restoreWithManualKey(
      bundle: staged,
      keySet: keySet,
      manualKeyId: keySet.keys[4].id,
    );
    expect((await service.loadBundle())!.createdAtEpochMs, candidate.createdAtEpochMs);
    expect(await service.loadPendingBundle(), isNull);
  });

  test('bundle restore rejects a recovery key from another vault', () async {
    final directory = await Directory.systemTemp.createTemp('aureon-vault-mismatch-');
    final dekStore = _MemoryDekStore();
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final service = AureonCredentialVaultStore(
      dekStore: dekStore,
      rootDirectory: directory,
    );
    final recovery = AureonRecoveryKeyService();
    final original = recovery.generateKeySet(vaultId: 'vault-original');
    final wrong = recovery.generateKeySet(vaultId: 'vault-other');
    final bundle = await service.initialize(original);
    await expectLater(
      service.restoreWithManualKey(
        bundle: bundle,
        keySet: wrong,
        manualKeyId: wrong.keys.first.id,
      ),
      throwsFormatException,
    );
    expect(await dekStore.read(original.vaultId, original.generation), isNotNull);
    expect(await dekStore.read(wrong.vaultId, wrong.generation), isNull);
  });
}
