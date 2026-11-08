import 'package:aureon/src/backup/aureon_recovery_key_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = AureonRecoveryKeyService();

  test('generates exactly five independent 256-bit manual recovery keys', () {
    final set = service.generateKeySet(vaultId: 'vault-test-01');
    expect(set.keys, hasLength(5));
    expect(set.keys.map((key) => key.id).toSet(), hasLength(5));
    expect(set.keys.map((key) => key.value).toSet(), hasLength(5));
    expect(set.keys.every((key) => RegExp(r'^[0-9a-f]{64}$').hasMatch(key.value)), isTrue);
    expect(set.toPlainText(), contains('FIVE PLAINTEXT SECRET KEYS'));
  });

  test('each of five independent keys unwraps the same DEK', () async {
    final set = service.generateKeySet(vaultId: 'vault-test-02');
    final dek = List<int>.generate(32, (index) => index);
    final envelopes = await service.wrapVaultDek(keySet: set, vaultDek: dek);
    expect(envelopes, hasLength(5));
    for (var index = 0; index < set.keys.length; index++) {
      final recovered = await service.unwrapVaultDek(
        manualKey: set.keys[index].value,
        keyId: set.keys[index].id,
        vaultId: set.vaultId,
        generation: set.generation,
        envelope: envelopes[index],
      );
      expect(recovered, dek);
    }
  });

  test('encrypted .key export/import round trips and rejects wrong passphrase', () async {
    final set = service.generateKeySet(vaultId: 'vault-test-03');
    final bytes = await service.exportEncryptedKeyFile(
      keySet: set,
      passphrase: 'a-long-independent-recovery-passphrase',
    );
    final imported = await service.importEncryptedKeyFile(
      bytes: bytes,
      passphrase: 'a-long-independent-recovery-passphrase',
      expectedVaultId: set.vaultId,
    );
    expect(imported.keys.map((key) => key.value), set.keys.map((key) => key.value));
    await expectLater(
      service.importEncryptedKeyFile(
        bytes: bytes,
        passphrase: 'a-long-independent-recovery-passphrase',
        expectedVaultId: 'wrong-vault-id',
      ),
      throwsFormatException,
    );
    final tampered = List<int>.from(bytes);
    tampered[tampered.length - 3] = tampered[tampered.length - 3] == 48 ? 49 : 48;
    await expectLater(
      service.importEncryptedKeyFile(
        bytes: tampered,
        passphrase: 'a-long-independent-recovery-passphrase',
        expectedVaultId: set.vaultId,
      ),
      throwsA(anything),
    );
    await expectLater(
      service.importEncryptedKeyFile(
        bytes: bytes,
        passphrase: 'a-different-wrong-passphrase',
        expectedVaultId: set.vaultId,
      ),
      throwsA(anything),
    );
  }, timeout: Timeout(Duration(minutes: 2)));
}
