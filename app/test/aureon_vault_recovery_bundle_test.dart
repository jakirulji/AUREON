import 'dart:convert';

import 'package:aureon/src/backup/aureon_recovery_key_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recovery bundle requires five encrypted envelopes and rejects plaintext credentials', () async {
    final keySet = AureonRecoveryKeyService().generateKeySet(vaultId: 'vault-1');
    final bundle = await CredentialVaultCryptoService().createBundle(
      keySet: keySet,
      vaultDek: List<int>.filled(32, 7),
      credentialRecords: const [
        {
          'providerAccountId': 'drive-1',
          'provider': 'google_drive',
          'refreshToken': 'test-token-is-encrypted-before-serialization',
        },
      ],
      cloudflareEnvelope: const {'keyVersion': 'cf-v1', 'cipherText': 'opaque'},
    );
    final restored = VaultRecoveryBundle.fromJson(bundle.toJson());
    expect(restored.manualKeyEnvelopes, hasLength(5));
    expect(restored.encryptedCredentialRecords.single['providerAccountId'], 'drive-1');
    expect(jsonEncode(restored.toJson()), isNot(contains('test-token-is-encrypted-before-serialization')));

    final unsafe = <String, Object?>{
      ...bundle.toJson(),
      'encryptedCredentialRecords': const [
        {'providerAccountId': 'drive-1', 'refreshToken': 'must-never-be-serialized'},
      ],
    };
    expect(() => VaultRecoveryBundle.fromJson(unsafe), throwsFormatException);
  });
}
