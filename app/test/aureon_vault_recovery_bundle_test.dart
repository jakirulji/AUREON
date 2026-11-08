import 'dart:convert';

import 'package:aureon/src/backup/aureon_recovery_key_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recovery bundle requires five encrypted envelopes and rejects plaintext credentials', () {
    final bundle = VaultRecoveryBundle(
      vaultId: 'vault-1',
      generation: 2,
      createdAtEpochMs: 100,
      encryptedCredentialRecords: [
        {
          'formatVersion': 1,
          'recordVersion': 1,
          'cipher': 'AES-256-GCM',
          'providerAccountId': 'drive-1',
          'nonce': base64Url.encode(List<int>.filled(12, 9)),
          'cipherText': base64Url.encode([1, 2, 3, 4]),
          'mac': base64Url.encode(List<int>.filled(16, 8)),
        },
      ],
      manualKeyEnvelopes: List.generate(5, (index) => ManualKeyEnvelope(
        keyId: 'key-$index', salt: base64Url.encode(List<int>.filled(32, index + 1)),
        nonce: base64Url.encode(List<int>.filled(12, index + 2)),
        cipherText: base64Url.encode(List<int>.filled(32, index + 3)),
        mac: base64Url.encode(List<int>.filled(16, index + 4)),
      )),
      cloudflareEnvelope: const {'keyVersion': 'cf-v1', 'cipherText': 'opaque'},
    );
    final restored = VaultRecoveryBundle.fromJson(bundle.toJson());
    expect(restored.manualKeyEnvelopes, hasLength(5));
    expect(restored.encryptedCredentialRecords.single['providerAccountId'], 'drive-1');

    final unsafe = <String, Object?>{
      ...bundle.toJson(),
      'encryptedCredentialRecords': const [
        {'providerAccountId': 'drive-1', 'refreshToken': 'must-never-be-serialized'},
      ],
    };
    expect(() => VaultRecoveryBundle.fromJson(unsafe), throwsFormatException);
  });
}
