import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class ManualRecoveryKey {
  const ManualRecoveryKey({required this.id, required this.value});
  final String id;
  final String value;

  Map<String, Object?> toJson() => {'id': id, 'key': value};
}

/// Five independent 256-bit keys. Any one key can unwrap the same vault DEK.
class ManualRecoveryKeySet {
  const ManualRecoveryKeySet({
    required this.vaultId,
    required this.generation,
    required this.keys,
    required this.createdAtEpochMs,
  });

  final String vaultId;
  final int generation;
  final List<ManualRecoveryKey> keys;
  final int createdAtEpochMs;

  String toPlainText() {
    final lines = <String>[
      'AUREON MANUAL RECOVERY KEYS',
      'WARNING: THIS FILE CONTAINS FIVE PLAINTEXT SECRET KEYS.',
      'Keep it offline in secure storage. Anyone with one active key and the matching encrypted Vault Recovery Bundle may recover the credential vault.',
      'Vault ID: $vaultId',
      'Generation: $generation',
      'Created UTC: ${DateTime.fromMillisecondsSinceEpoch(createdAtEpochMs, isUtc: true).toIso8601String()}',
      '',
    ];
    for (var i = 0; i < keys.length; i++) {
      lines.add('${i + 1}. ${keys[i].id}');
      lines.add(keys[i].value);
      lines.add('');
    }
    return lines.join('\n');
  }
}

class ManualKeyEnvelope {
  const ManualKeyEnvelope({
    required this.keyId,
    required this.salt,
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  final String keyId;
  final String salt;
  final String nonce;
  final String cipherText;
  final String mac;

  Map<String, Object?> toJson() => {
    'keyId': keyId,
    'kdf': 'HKDF-SHA-256',
    'cipher': 'AES-256-GCM',
    'salt': salt,
    'nonce': nonce,
    'cipherText': cipherText,
    'mac': mac,
  };

  factory ManualKeyEnvelope.fromJson(Map<String, Object?> json) {
    if (json['kdf'] != 'HKDF-SHA-256' || json['cipher'] != 'AES-256-GCM') {
      throw const FormatException('Unsupported manual recovery envelope algorithm.');
    }
    return ManualKeyEnvelope(
      keyId: _requiredString(json, 'keyId'),
      salt: _requiredString(json, 'salt'),
      nonce: _requiredString(json, 'nonce'),
      cipherText: _requiredString(json, 'cipherText'),
      mac: _requiredString(json, 'mac'),
    );
  }
}

class VaultRecoveryBundle {
  const VaultRecoveryBundle({
    required this.vaultId,
    required this.generation,
    required this.createdAtEpochMs,
    required this.encryptedCredentialRecords,
    required this.manualKeyEnvelopes,
    required this.cloudflareEnvelope,
  });

  final String vaultId;
  final int generation;
  final int createdAtEpochMs;
  /// Only authenticated ciphertext records. Never plaintext OAuth tokens.
  final List<Map<String, Object?>> encryptedCredentialRecords;
  final List<ManualKeyEnvelope> manualKeyEnvelopes;
  /// Opaque server-generated envelope; null until the Cloudflare broker exists.
  final Map<String, Object?>? cloudflareEnvelope;

  Map<String, Object?> toJson() => {
    'format': 'AUREON-VAULT-RECOVERY-BUNDLE',
    'formatVersion': 1,
    'vaultId': vaultId,
    'generation': generation,
    'createdAtEpochMs': createdAtEpochMs,
    'encryptedCredentialRecords': encryptedCredentialRecords,
    'manualKeyEnvelopes': manualKeyEnvelopes.map((e) => e.toJson()).toList(),
    'cloudflareEnvelope': cloudflareEnvelope,
  };

  factory VaultRecoveryBundle.fromJson(Map<String, Object?> json) {
    if (json['format'] != 'AUREON-VAULT-RECOVERY-BUNDLE' || json['formatVersion'] != 1) {
      throw const FormatException('Unsupported Vault Recovery Bundle format.');
    }
    final records = json['encryptedCredentialRecords'];
    final envelopes = json['manualKeyEnvelopes'];
    if (records is! List || envelopes is! List || envelopes.length != 5) {
      throw const FormatException('Recovery bundle must contain five manual-key envelopes.');
    }
    final parsedRecords = records.map((entry) {
      if (entry is! Map) throw const FormatException('Invalid encrypted credential record.');
      final record = entry.cast<String, Object?>();
      if (record.containsKey('accessToken') || record.containsKey('refreshToken') ||
          record.containsKey('password') || record.containsKey('plaintext')) {
        throw const FormatException('Plaintext credential fields are forbidden in a recovery bundle.');
      }
      return record;
    }).toList();
    return VaultRecoveryBundle(
      vaultId: _requiredString(json, 'vaultId'),
      generation: _requiredInt(json, 'generation'),
      createdAtEpochMs: _requiredInt(json, 'createdAtEpochMs'),
      encryptedCredentialRecords: parsedRecords,
      manualKeyEnvelopes: envelopes.map((entry) {
        if (entry is! Map) throw const FormatException('Invalid manual key envelope.');
        return ManualKeyEnvelope.fromJson(entry.cast<String, Object?>());
      }).toList(),
      cloudflareEnvelope: json['cloudflareEnvelope'] is Map
          ? (json['cloudflareEnvelope'] as Map).cast<String, Object?>()
          : null,
    );
  }
}

class AureonRecoveryKeyService {
  static const keyCount = 5;
  static const keyBytes = 32;
  static const _kdfMemoryKiB = 64 * 1024;
  static const _kdfIterations = 3;
  static const _kdfParallelism = 2;

  static final _random = Random.secure();
  static final _cipher = AesGcm.with256bits();

  ManualRecoveryKeySet generateKeySet({required String vaultId, int generation = 1}) {
    if (vaultId.trim().isEmpty || generation < 1) {
      throw ArgumentError('A vault ID and positive generation are required.');
    }
    final keys = List<ManualRecoveryKey>.generate(keyCount, (index) {
      final raw = _randomBytes(keyBytes);
      return ManualRecoveryKey(
        id: 'manual-${generation}-${index + 1}-${_hex(_randomBytes(6))}',
        value: _hex(raw),
      );
    });
    return ManualRecoveryKeySet(
      vaultId: vaultId,
      generation: generation,
      keys: keys,
      createdAtEpochMs: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
  }

  Future<List<int>> exportEncryptedKeyFile({
    required ManualRecoveryKeySet keySet,
    required String passphrase,
  }) async {
    _validateKeySet(keySet);
    _validatePassphrase(passphrase);
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final header = <String, Object?>{
      'format': 'AUREON-MANUAL-RECOVERY-KEY',
      'formatVersion': 1,
      'vaultId': keySet.vaultId,
      'generation': keySet.generation,
      'keyCount': keyCount,
      'kdf': 'Argon2id',
      'memoryKiB': _kdfMemoryKiB,
      'iterations': _kdfIterations,
      'parallelism': _kdfParallelism,
      'hashLength': 32,
      'cipher': 'AES-256-GCM',
      'salt': base64Url.encode(salt),
      'nonce': base64Url.encode(nonce),
    };
    final aad = utf8.encode(jsonEncode(header));
    final derived = await _derivePassphraseKey(passphrase, salt);
    final payload = utf8.encode(jsonEncode({
      'createdAtEpochMs': keySet.createdAtEpochMs,
      'keys': keySet.keys.map((key) => key.toJson()).toList(),
    }));
    final box = await _cipher.encrypt(payload, secretKey: derived, nonce: nonce, aad: aad);
    return utf8.encode(jsonEncode({
      'header': header,
      'cipherText': base64Url.encode(box.cipherText),
      'mac': base64Url.encode(box.mac.bytes),
    }));
  }

  Future<ManualRecoveryKeySet> importEncryptedKeyFile({
    required List<int> bytes,
    required String passphrase,
    required String expectedVaultId,
  }) async {
    _validatePassphrase(passphrase);
    if (bytes.isEmpty || bytes.length > 1024 * 1024) {
      throw const FormatException('Recovery key file size is invalid.');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const FormatException('Invalid recovery key file.');
    final root = decoded.cast<String, Object?>();
    final rawHeader = root['header'];
    if (rawHeader is! Map) throw const FormatException('Missing recovery key header.');
    final header = rawHeader.cast<String, Object?>();
    if (header['format'] != 'AUREON-MANUAL-RECOVERY-KEY' ||
        header['formatVersion'] != 1 ||
        header['keyCount'] != keyCount ||
        header['kdf'] != 'Argon2id' ||
        header['cipher'] != 'AES-256-GCM' ||
        header['memoryKiB'] != _kdfMemoryKiB ||
        header['iterations'] != _kdfIterations ||
        header['parallelism'] != _kdfParallelism ||
        header['hashLength'] != 32) {
      throw const FormatException('Unsupported or unsafe recovery key parameters.');
    }
    final vaultId = _requiredString(header, 'vaultId');
    if (vaultId != expectedVaultId) throw const FormatException('This recovery key belongs to a different vault.');
    final salt = _decodeBase64(_requiredString(header, 'salt'), expectedLength: 16);
    final nonce = _decodeBase64(_requiredString(header, 'nonce'), expectedLength: 12);
    final cipherText = _decodeBase64(_requiredString(root, 'cipherText'));
    final mac = _decodeBase64(_requiredString(root, 'mac'), expectedLength: 16);
    final derived = await _derivePassphraseKey(passphrase, salt);
    final clear = await _cipher.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: derived,
      aad: utf8.encode(jsonEncode(header)),
    );
    final payloadValue = jsonDecode(utf8.decode(clear));
    if (payloadValue is! Map) throw const FormatException('Invalid recovery key payload.');
    final payload = payloadValue.cast<String, Object?>();
    final rawKeys = payload['keys'];
    if (rawKeys is! List || rawKeys.length != keyCount) {
      throw const FormatException('Recovery key file must contain exactly five keys.');
    }
    final keys = rawKeys.map((entry) {
      if (entry is! Map) throw const FormatException('Invalid manual recovery key.');
      final item = entry.cast<String, Object?>();
      final id = _requiredString(item, 'id');
      final value = _requiredString(item, 'key');
      if (_unhex(value).length != keyBytes) throw const FormatException('Manual recovery key must be 256 bits.');
      return ManualRecoveryKey(id: id, value: value);
    }).toList();
    if (keys.map((key) => key.id).toSet().length != keyCount ||
        keys.map((key) => key.value).toSet().length != keyCount) {
      throw const FormatException('Manual recovery keys must be unique.');
    }
    return ManualRecoveryKeySet(
      vaultId: vaultId,
      generation: _requiredInt(header, 'generation'),
      createdAtEpochMs: _requiredInt(payload, 'createdAtEpochMs'),
      keys: keys,
    );
  }

  Future<List<ManualKeyEnvelope>> wrapVaultDek({
    required ManualRecoveryKeySet keySet,
    required List<int> vaultDek,
  }) async {
    _validateKeySet(keySet);
    if (vaultDek.length != 32) throw ArgumentError('Vault DEK must be 256 bits.');
    final envelopes = <ManualKeyEnvelope>[];
    for (final key in keySet.keys) {
      final salt = _randomBytes(32);
      final nonce = _randomBytes(12);
      final aad = utf8.encode('AUREON|VAULT-DEK|v1|${keySet.vaultId}|${keySet.generation}|${key.id}');
      final kek = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(_unhex(key.value)),
        nonce: salt,
        info: utf8.encode('AUREON-MANUAL-RECOVERY-KEK-v1'),
      );
      final box = await _cipher.encrypt(vaultDek, secretKey: kek, nonce: nonce, aad: aad);
      envelopes.add(ManualKeyEnvelope(
        keyId: key.id,
        salt: base64Url.encode(salt),
        nonce: base64Url.encode(nonce),
        cipherText: base64Url.encode(box.cipherText),
        mac: base64Url.encode(box.mac.bytes),
      ));
    }
    return envelopes;
  }

  Future<List<int>> unwrapVaultDek({
    required String manualKey,
    required String keyId,
    required String vaultId,
    required int generation,
    required ManualKeyEnvelope envelope,
  }) async {
    if (envelope.keyId != keyId) throw const FormatException('Recovery key ID does not match its envelope.');
    final rawKey = _unhex(manualKey);
    if (rawKey.length != keyBytes) throw const FormatException('Manual recovery key must be 256 bits.');
    final salt = _decodeBase64(envelope.salt, expectedLength: 32);
    final nonce = _decodeBase64(envelope.nonce, expectedLength: 12);
    final aad = utf8.encode('AUREON|VAULT-DEK|v1|$vaultId|$generation|$keyId');
    final kek = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(rawKey),
      nonce: salt,
      info: utf8.encode('AUREON-MANUAL-RECOVERY-KEK-v1'),
    );
    final clear = await _cipher.decrypt(
      SecretBox(
        _decodeBase64(envelope.cipherText),
        nonce: nonce,
        mac: Mac(_decodeBase64(envelope.mac, expectedLength: 16)),
      ),
      secretKey: kek,
      aad: aad,
    );
    if (clear.length != 32) throw const FormatException('Recovered vault DEK has an invalid length.');
    return clear;
  }

  Future<SecretKey> _derivePassphraseKey(String passphrase, List<int> salt) =>
      Argon2id(
        memory: _kdfMemoryKiB,
        parallelism: _kdfParallelism,
        iterations: _kdfIterations,
        hashLength: 32,
      ).deriveKeyFromPassword(password: passphrase, nonce: salt);

  void _validatePassphrase(String passphrase) {
    if (passphrase.trim().length < 14 || passphrase.length > 1024) {
      throw ArgumentError('Use a separate metadata/recovery passphrase of at least 14 characters.');
    }
  }

  void _validateKeySet(ManualRecoveryKeySet set) {
    if (set.keys.length != keyCount ||
        set.keys.map((key) => key.id).toSet().length != keyCount ||
        set.keys.map((key) => key.value).toSet().length != keyCount ||
        set.keys.any((key) => _unhex(key.value).length != keyBytes)) {
      throw const FormatException('AUREON requires exactly five unique 256-bit manual recovery keys.');
    }
  }

  List<int> _randomBytes(int count) => List<int>.generate(count, (_) => _random.nextInt(256));
  String _hex(List<int> bytes) => bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  List<int> _unhex(String value) {
    if (value.length != keyBytes * 2 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
      throw const FormatException('Invalid 256-bit manual recovery key encoding.');
    }
    return List<int>.generate(keyBytes, (index) => int.parse(value.substring(index * 2, index * 2 + 2), radix: 16));
  }
}

String _requiredString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.isEmpty) throw FormatException('Missing or invalid $key.');
  return value;
}

int _requiredInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! int) throw FormatException('Missing or invalid $key.');
  return value;
}

List<int> _decodeBase64(String value, {int? expectedLength}) {
  final decoded = base64Url.decode(base64Url.normalize(value));
  if (expectedLength != null && decoded.length != expectedLength) {
    throw const FormatException('Invalid encoded field length.');
  }
  return decoded;
}
