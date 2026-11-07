import 'dart:convert';

import 'package:aureon/src/backup/aureon_recovery_key_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('any one of five manual keys restores encrypted credential records', () async {
    final recovery = AureonRecoveryKeyService();
    final vaultKeys = recovery.generateKeySet(vaultId: 'vault-credential-test');
    final dek = List<int>.generate(32, (index) => index + 1);
    final credentials = [
      <String, Object?>{
        'providerAccountId': 'google-subject-001',
        'provider': 'googleDrive',
        'refreshToken': 'sensitive-refresh-token-fixture',
        'scopes': ['drive.file'],
      },
      <String, Object?>{
        'providerAccountId': 'onedrive-subject-002',
        'provider': 'oneDrive',
        'refreshToken': 'another-sensitive-token-fixture',
        'scopes': ['files.readwrite'],
      },
    ];

    final codec = CredentialVaultCryptoService();
    final created = await codec.createBundle(
      keySet: vaultKeys,
      vaultDek: dek,
      credentialRecords: credentials,
    );
    final serialized = jsonEncode(created.toJson());
    expect(serialized, isNot(contains('sensitive-refresh-token-fixture')));
    expect(created.manualKeyEnvelopes, hasLength(5));

    final imported = VaultRecoveryBundle.fromJson(created.toJson());
    for (final key in vaultKeys.keys) {
      final restored = await codec.restoreBundle(
        bundle: imported,
        keySet: vaultKeys,
        manualKeyId: key.id,
      );
      expect(restored, credentials);
    }
  });

  test('wrong key generation and tampered credential ciphertext fail closed', () async {
    final recovery = AureonRecoveryKeyService();
    final keys = recovery.generateKeySet(vaultId: 'vault-credential-test');
    final codec = CredentialVaultCryptoService();
    final bundle = await codec.createBundle(
      keySet: keys,
      vaultDek: List<int>.generate(32, (index) => 255 - index),
      credentialRecords: [
        {'providerAccountId': 'drive-account', 'refreshToken': 'token-value'},
      ],
    );

    final otherGeneration = recovery.generateKeySet(
      vaultId: keys.vaultId,
      generation: keys.generation + 1,
    );
    await expectLater(
      codec.restoreBundle(bundle: bundle, keySet: otherGeneration, manualKeyId: otherGeneration.keys.first.id),
      throwsFormatException,
    );

    final json = Map<String, Object?>.from(bundle.toJson());
    final records = (json['encryptedCredentialRecords'] as List)
        .map((entry) => Map<String, Object?>.from(entry as Map)).toList();
    final cipherText = records.single['cipherText'] as String;
    records.single['cipherText'] = '${cipherText.substring(0, cipherText.length - 1)}${cipherText.endsWith('A') ? 'B' : 'A'}';
    json['encryptedCredentialRecords'] = records;
    final tampered = VaultRecoveryBundle.fromJson(json);
    await expectLater(
      codec.restoreBundle(bundle: tampered, keySet: keys, manualKeyId: keys.keys.first.id),
      throwsA(anything),
    );
  });
}
