import 'dart:convert';

import 'package:aureon/src/backup/aureon_recovery_key_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TXT/.key key set, portable Vault Recovery Bundle and credential restore interoperate', () async {
    final recovery = AureonRecoveryKeyService();
    final keySet = recovery.generateKeySet(vaultId: 'vault-portable-roundtrip');
    final vaultDek = List<int>.generate(32, (index) => (index * 7) & 0xff);
    final credentials = <Map<String, Object?>>[
      {
        'providerAccountId': 'google-account-stable-subject',
        'provider': 'googleDrive',
        'refreshToken': 'fixture-refresh-token-google',
        'scopes': ['drive.readonly', 'drive.file'],
      },
      {
        'providerAccountId': 'onedrive-account-stable-subject',
        'provider': 'oneDrive',
        'refreshToken': 'fixture-refresh-token-onedrive',
        'scopes': ['files.readwrite'],
      },
    ];

    final codec = CredentialVaultCryptoService();
    final createdBundle = await codec.createBundle(
      keySet: keySet,
      vaultDek: vaultDek,
      credentialRecords: credentials,
    );

    final keyFile = await recovery.exportEncryptedKeyFile(
      keySet: keySet,
      passphrase: 'portable-key-file-passphrase-2026',
    );
    final importedKeys = await recovery.importEncryptedKeyFile(
      bytes: keyFile,
      passphrase: 'portable-key-file-passphrase-2026',
      expectedVaultId: keySet.vaultId,
    );

    final portableBundleBytes = utf8.encode(jsonEncode(createdBundle.toJson()));
    final importedBundle = VaultRecoveryBundle.fromJson(
      jsonDecode(utf8.decode(portableBundleBytes)) as Map<String, Object?>,
    );

    expect(importedBundle.cloudflareEnvelope, isNull);
    expect(importedBundle.encryptedCredentialRecords, hasLength(2));
    expect(utf8.decode(portableBundleBytes), isNot(contains('fixture-refresh-token-google')));
    expect(utf8.decode(portableBundleBytes), isNot(contains('fixture-refresh-token-onedrive')));

    for (final key in importedKeys.keys) {
      final restored = await codec.restoreBundle(
        bundle: importedBundle,
        keySet: importedKeys,
        manualKeyId: key.id,
      );
      expect(restored, credentials);
    }
  });
}
