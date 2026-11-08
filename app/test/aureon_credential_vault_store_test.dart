import 'dart:convert';
import 'dart:io';

import 'package:aureon/src/backup/aureon_credential_vault_store.dart';
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
  Future<void> write(String vaultId, int generation, List<int> dek) async {
    if (failWrites) throw StateError('Simulated secure-storage failure.');
    values[_id(vaultId, generation)] = dek.toList();
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
