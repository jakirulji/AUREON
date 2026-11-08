import 'dart:convert';
import 'dart:io';

import 'package:aureon/src/backup/aureon_credential_vault_store.dart';
import 'package:aureon/src/backup/aureon_recovery_key_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryDekStore implements AureonVaultDekStore {
  final Map<String, List<int>> values = {};
  String _id(String vaultId, int generation) => '$vaultId:$generation';

  @override
  Future<List<int>?> read(String vaultId, int generation) async =>
      values[_id(vaultId, generation)]?.toList();

  @override
  Future<void> write(String vaultId, int generation, List<int> dek) async {
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
