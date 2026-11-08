import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'aureon_recovery_key_service.dart';

abstract interface class AureonVaultDekStore {
  Future<List<int>?> read(String vaultId, int generation);
  Future<void> write(String vaultId, int generation, List<int> dek);
}

class PlatformAureonVaultDekStore implements AureonVaultDekStore {
  PlatformAureonVaultDekStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  String _name(String vaultId, int generation) =>
      'aureon.credential-vault.dek.v1.$vaultId.$generation';

  @override
  Future<List<int>?> read(String vaultId, int generation) async {
    final encoded = await _storage.read(key: _name(vaultId, generation));
    if (encoded == null) return null;
    final value = base64Url.decode(base64Url.normalize(encoded));
    if (value.length != 32) {
      throw StateError('Stored credential-vault key is invalid; refusing to use it.');
    }
    return value;
  }

  @override
  Future<void> write(String vaultId, int generation, List<int> dek) async {
    if (dek.length != 32) throw ArgumentError('Vault DEK must be 256 bits.');
    await _storage.write(
      key: _name(vaultId, generation),
      value: base64Url.encode(dek),
    );
  }
}

/// Owns the device-protected DEK and portable encrypted Recovery Bundle.
/// Manual Recovery Keys are never persisted by this class.
class AureonCredentialVaultStore {
  AureonCredentialVaultStore({
    AureonVaultDekStore? dekStore,
    Directory? rootDirectory,
    CredentialVaultCryptoService? crypto,
  })  : _dekStore = dekStore ?? PlatformAureonVaultDekStore(),
        _rootDirectory = rootDirectory,
        _crypto = crypto ?? CredentialVaultCryptoService();

  static const maxBundleBytes = 256 * 1024 * 1024;
  static final _random = Random.secure();

  final AureonVaultDekStore _dekStore;
  final Directory? _rootDirectory;
  final CredentialVaultCryptoService _crypto;

  Future<VaultRecoveryBundle> initialize(ManualRecoveryKeySet keySet) async {
    final dek = _randomBytes(32);
    final bundle = await _crypto.createBundle(
      keySet: keySet,
      vaultDek: dek,
      credentialRecords: const [],
    );
    await _dekStore.write(keySet.vaultId, keySet.generation, dek);
    await _writeBundle(bundle);
    return bundle;
  }

  Future<VaultRecoveryBundle?> loadBundle() async {
    final file = await _bundleFile();
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return decodeBundle(bytes);
  }

  Future<Uint8List> exportBundle() async {
    final bundle = await loadBundle();
    if (bundle == null) throw StateError('No local credential-vault Recovery Bundle exists.');
    return Uint8List.fromList(utf8.encode(jsonEncode(bundle.toJson())));
  }

  Future<VaultRecoveryBundle> importBundle(List<int> bytes) async {
    final bundle = decodeBundle(bytes);
    await _writeBundle(bundle);
    return bundle;
  }

  VaultRecoveryBundle decodeBundle(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > maxBundleBytes) {
      throw const FormatException('Vault Recovery Bundle size is invalid.');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const FormatException('Invalid Vault Recovery Bundle document.');
    return VaultRecoveryBundle.fromJson(decoded.cast<String, Object?>());
  }

  Future<List<Map<String, Object?>>> restoreWithManualKey({
    required VaultRecoveryBundle bundle,
    required ManualRecoveryKeySet keySet,
    required String manualKeyId,
  }) async {
    if (bundle.vaultId != keySet.vaultId || bundle.generation != keySet.generation) {
      throw const FormatException('Recovery key set and bundle owner/generation do not match.');
    }
    final key = keySet.keys.where((entry) => entry.id == manualKeyId).toList();
    final envelope = bundle.manualKeyEnvelopes.where((entry) => entry.keyId == manualKeyId).toList();
    if (key.length != 1 || envelope.length != 1) {
      throw const FormatException('Selected manual recovery key is not active in this bundle.');
    }
    final dek = await AureonRecoveryKeyService().unwrapVaultDek(
      manualKey: key.single.value,
      keyId: manualKeyId,
      vaultId: bundle.vaultId,
      generation: bundle.generation,
      envelope: envelope.single,
    );
    final records = await _crypto.restoreBundle(
      bundle: bundle,
      keySet: keySet,
      manualKeyId: manualKeyId,
    );
    // Persist only through the platform secure-storage adapter, never in prefs/files.
    await _dekStore.write(bundle.vaultId, bundle.generation, dek);
    await _writeBundle(bundle);
    return records;
  }

  Future<VaultRecoveryBundle> replaceCredentialRecords({
    required ManualRecoveryKeySet keySet,
    required List<Map<String, Object?>> credentialRecords,
  }) async {
    final dek = await _dekStore.read(keySet.vaultId, keySet.generation);
    if (dek == null) {
      throw StateError('This device has no unlocked vault DEK. Restore the vault first.');
    }
    final bundle = await _crypto.createBundle(
      keySet: keySet,
      vaultDek: dek,
      credentialRecords: credentialRecords,
    );
    await _writeBundle(bundle);
    return bundle;
  }

  Future<void> _writeBundle(VaultRecoveryBundle bundle) async {
    final bytes = utf8.encode(jsonEncode(bundle.toJson()));
    if (bytes.length > maxBundleBytes) {
      throw StateError('Vault Recovery Bundle exceeds the supported size.');
    }
    final file = await _bundleFile();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<File> _bundleFile() async {
    final root = _rootDirectory ?? await getApplicationSupportDirectory();
    return File('${root.path}${Platform.pathSeparator}credential-vault.aureon-vault');
  }

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));
}
