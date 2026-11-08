import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'aureon_recovery_key_service.dart';
import 'aureon_cloudflare_vault_client.dart';

abstract interface class AureonVaultDekStore {
  Future<List<int>?> read(String vaultId, int generation);
  Future<void> write(String vaultId, int generation, List<int> dek);
  Future<void> delete(String vaultId, int generation);
}

class PlatformAureonVaultDekStore implements AureonVaultDekStore {
  PlatformAureonVaultDekStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  String _name(String vaultId, int generation) {
    if (vaultId.trim().isEmpty || generation < 1) {
      throw ArgumentError('A valid vault ID and generation are required.');
    }
    // Encode the complete ID to avoid delimiter collisions and platform-specific
    // secure-storage key-name restrictions. This is an identifier, not a secret.
    final encodedVaultId = base64Url.encode(utf8.encode(vaultId)).replaceAll('=', '');
    return 'aureon.credential-vault.dek.v1.$encodedVaultId.$generation';
  }

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
  Future<void> delete(String vaultId, int generation) =>
      _storage.delete(key: _name(vaultId, generation));

  @override
  Future<void> write(String vaultId, int generation, List<int> dek) async {
    if (dek.length != 32) throw ArgumentError('Vault DEK must be 256 bits.');
    await _storage.write(
      key: _name(vaultId, generation),
      value: base64Url.encode(dek),
    );
  }
}

class AureonVaultRotationPlan {
  const AureonVaultRotationPlan({
    required this.keySet,
    required this.bundle,
    required this.previousGeneration,
    required this.nextDek,
  });
  final ManualRecoveryKeySet keySet;
  final VaultRecoveryBundle bundle;
  final int previousGeneration;
  // Kept in memory only until the user has exported the new key set and bundle.
  final List<int> nextDek;
}

/// Owns the device-protected DEK and portable encrypted Recovery Bundle.
/// Bundle import is monotonic: older generations and other vault IDs are rejected.
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
    if (keySet.vaultId.trim().isEmpty || keySet.generation < 1 ||
        keySet.keys.length != AureonRecoveryKeyService.keyCount) {
      throw ArgumentError('A valid vault ID, generation and five-key recovery set are required.');
    }
    if (await loadBundle() != null || await loadPendingBundle() != null ||
        await _dekStore.read(keySet.vaultId, keySet.generation) != null) {
      throw StateError('A vault already exists for this device. Initialization cannot overwrite an existing vault.');
    }
    final dek = _randomBytes(32);
    final bundle = await _crypto.createBundle(
      keySet: keySet,
      vaultDek: dek,
      credentialRecords: const [],
    );
    // Commit the portable encrypted recovery data first. If secure-storage
    // initialization fails or the process stops here, the manual key can still
    // restore the DEK; an orphaned DEK must never block future recovery.
    await _writeBundle(bundle);
    await _dekStore.write(keySet.vaultId, keySet.generation, dek);
    return bundle;
  }

  Future<VaultRecoveryBundle?> loadBundle() => _readBundle();

  /// An imported bundle remains quarantined until a matching manual key
  /// successfully authenticates its wrapped DEK and decrypts every record.
  Future<VaultRecoveryBundle?> loadPendingBundle() => _readBundle(pending: true);

  Future<VaultRecoveryBundle?> _readBundle({bool pending = false}) async {
    final file = await _bundleFile(pending: pending);
    final backup = File('${file.path}.bak');
    if (!await file.exists() && await backup.exists()) {
      // Recover the last known-good snapshot after an interrupted replacement.
      await backup.rename(file.path);
    }
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
    final current = await loadBundle();
    if (current != null) {
      if (current.vaultId != bundle.vaultId) {
        throw StateError('A different vault is already present on this device. Switching vaults requires an explicit separate workflow.');
      }
      if (bundle.generation < current.generation ||
          (bundle.generation == current.generation &&
           bundle.createdAtEpochMs < current.createdAtEpochMs)) {
        throw StateError('This Recovery Bundle is older than the local vault snapshot. It was not imported to prevent rollback.');
      }
      if (bundle.generation == current.generation &&
          bundle.createdAtEpochMs == current.createdAtEpochMs &&
          jsonEncode(bundle.toJson()) != jsonEncode(current.toJson())) {
        throw StateError('Recovery Bundle generation and timestamp collide with different content. Refusing ambiguous import.');
      }
    }
    // Do not replace the trusted active snapshot with an unauthenticated file.
    // Keep it pending until restoreWithManualKey verifies the DEK and records.
    await _writeBundle(bundle, pending: true);
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
    try {
      final records = await _crypto.restoreBundle(
        bundle: bundle,
        keySet: keySet,
        manualKeyId: manualKeyId,
      );
      // Promote authenticated ciphertext before switching the device DEK. If
      // secure storage fails, the pending copy remains available for a retry.
      await _writeBundle(bundle);
      await _dekStore.write(bundle.vaultId, bundle.generation, dek);
      final pending = await _bundleFile(pending: true);
      if (await pending.exists()) await pending.delete();
      return records;
    } finally {
      dek.fillRange(0, dek.length, 0);
    }
  }

  /// Restores the latest Cloudflare snapshot using the device-bound
  /// recovery path. The downloaded bundle remains quarantined until every
  /// encrypted credential record authenticates successfully.
  Future<List<Map<String, Object?>>> restoreWithCloudflare({
    required String vaultId,
    required AureonCloudflareVaultClient client,
    required AureonFirebaseIdTokenProvider idTokenProvider,
  }) async {
    final bundle = await fetchCloudflareSnapshot(
      vaultId: vaultId,
      client: client,
      idTokenProvider: idTokenProvider,
    );
    final dek = await client.recoverVaultDek(
      vaultId: vaultId,
      expectedGeneration: bundle.generation,
      idTokenProvider: idTokenProvider,
    );
    try {
      final records = await _crypto.restoreBundleWithDek(
        bundle: bundle,
        vaultDek: dek,
      );
      final previousDek = await _dekStore.read(bundle.vaultId, bundle.generation);
      await _dekStore.write(bundle.vaultId, bundle.generation, dek);
      try {
        await _writeBundle(bundle);
      } catch (_) {
        if (previousDek == null) {
          await _dekStore.delete(bundle.vaultId, bundle.generation);
        } else {
          await _dekStore.write(bundle.vaultId, bundle.generation, previousDek);
        }
        rethrow;
      } finally {
        previousDek?.fillRange(0, previousDek.length, 0);
      }
      final pending = await _bundleFile(pending: true);
      if (await pending.exists()) await pending.delete();
      return records;
    } finally {
      dek.fillRange(0, dek.length, 0);
    }
  }

  /// Prepares a new generation without changing the active vault. The caller
  /// must export the returned five-key set and bundle before commitRotation.
  /// The next DEK remains in memory only; abandoning the plan leaves the
  /// current generation fully usable.
  Future<AureonVaultRotationPlan> prepareRotation({
    required ManualRecoveryKeySet currentKeySet,
    required String currentManualKeyId,
  }) async {
    final current = await loadBundle();
    if (current == null) throw StateError('No active vault bundle exists.');
    if (current.vaultId != currentKeySet.vaultId ||
        current.generation != currentKeySet.generation) {
      throw const FormatException('Current key set does not match the active vault generation.');
    }
    final oldDek = await _dekStore.read(current.vaultId, current.generation);
    if (oldDek == null || oldDek.length != 32) {
      throw StateError('The current vault is locked. Restore it before rotating keys.');
    }
    final records = await _crypto.restoreBundle(
      bundle: current,
      keySet: currentKeySet,
      manualKeyId: currentManualKeyId,
    );
    final nextKeys = AureonRecoveryKeyService().generateKeySet(
      vaultId: current.vaultId,
      generation: current.generation + 1,
    );
    final nextDek = _randomBytes(32);
    final nextBundle = await _crypto.createBundle(
      keySet: nextKeys,
      vaultDek: nextDek,
      credentialRecords: records,
    );
    return AureonVaultRotationPlan(
      keySet: nextKeys,
      bundle: nextBundle,
      previousGeneration: current.generation,
      nextDek: nextDek,
    );
  }

  /// Commits only after the caller has exported the new recovery files.
  /// Old-generation exported copies remain decryptable; AUREON cannot revoke
  /// offline copies outside its control.
  Future<void> commitRotation({
    required ManualRecoveryKeySet currentKeySet,
    required AureonVaultRotationPlan plan,
  }) async {
    final current = await loadBundle();
    if (current == null || current.vaultId != currentKeySet.vaultId ||
        current.generation != plan.previousGeneration ||
        currentKeySet.generation != plan.previousGeneration ||
        plan.keySet.vaultId != current.vaultId ||
        plan.keySet.generation != current.generation + 1 ||
        plan.nextDek.length != 32) {
      throw StateError('Vault changed while rotation was being prepared. Start the rotation again.');
    }
    try {
      await _dekStore.write(plan.keySet.vaultId, plan.keySet.generation, plan.nextDek);
      // Verify the generated bundle and the newly wrapped DEK before promotion.
      await _crypto.restoreBundle(
        bundle: plan.bundle,
        keySet: plan.keySet,
        manualKeyId: plan.keySet.keys.first.id,
      );
      await _writeBundle(plan.bundle);
      await _dekStore.delete(current.vaultId, current.generation);
    } finally {
      plan.nextDek.fillRange(0, plan.nextDek.length, 0);
    }
  }

  /// Provisions the server-assisted envelope once, persists it locally, then
  /// uploads only the encrypted credential snapshot. A failed upload can be
  /// retried without creating a second envelope.
  Future<VaultRecoveryBundle> syncWithCloudflare({
    required AureonCloudflareVaultClient client,
    required AureonFirebaseIdTokenProvider idTokenProvider,
  }) async {
    final current = await loadBundle();
    if (current == null) throw StateError('No local credential-vault bundle exists.');
    final dek = await _dekStore.read(current.vaultId, current.generation);
    if (dek == null) {
      throw StateError('The local vault is locked. Restore it with an active manual recovery key before cloud sync.');
    }
    try {
      VaultRecoveryBundle? remote;
      try {
        remote = await client.fetchSnapshot(
          vaultId: current.vaultId,
          idTokenProvider: idTokenProvider,
        );
      } on AureonCloudflareApiException catch (error) {
        if (error.statusCode != 404) rethrow;
      }

      if (remote != null) {
        if (remote.generation > current.generation) {
          throw StateError('Cloudflare has a newer vault generation. Restore it before attempting another upload.');
        }
        if (remote.generation == current.generation) {
          if (remote.createdAtEpochMs > current.createdAtEpochMs) {
            throw StateError('The Cloudflare snapshot is newer than this device. Restore/reconcile it before syncing to avoid overwriting another device.');
          }
          if (remote.createdAtEpochMs == current.createdAtEpochMs) {
            final sameRecords = jsonEncode(remote.encryptedCredentialRecords) ==
                jsonEncode(current.encryptedCredentialRecords);
            final sameManualEnvelopes = jsonEncode(remote.manualKeyEnvelopes) ==
                jsonEncode(current.manualKeyEnvelopes);
            if (!sameRecords || !sameManualEnvelopes) {
              throw StateError('A same-generation Cloudflare snapshot conflicts with local data. Restore and reconcile before syncing.');
            }
            if (current.cloudflareEnvelope != null &&
                jsonEncode(current.cloudflareEnvelope) != jsonEncode(remote.cloudflareEnvelope)) {
              throw StateError('The local and Cloudflare recovery envelopes differ for the same vault generation.');
            }
            if (current.cloudflareEnvelope == null) {
              final adopted = VaultRecoveryBundle(
                vaultId: current.vaultId,
                generation: current.generation,
                createdAtEpochMs: current.createdAtEpochMs,
                encryptedCredentialRecords: current.encryptedCredentialRecords,
                manualKeyEnvelopes: current.manualKeyEnvelopes,
                cloudflareEnvelope: remote.cloudflareEnvelope,
              );
              await _writeBundle(adopted);
              return adopted;
            }
            return current;
          }
        }
      }

      final envelope = current.cloudflareEnvelope ??
          await client.createCloudflareEnvelope(
            vaultId: current.vaultId,
            generation: current.generation,
            dek: dek,
            idTokenProvider: idTokenProvider,
          );
      final synchronized = VaultRecoveryBundle(
        vaultId: current.vaultId,
        generation: current.generation,
        createdAtEpochMs: current.createdAtEpochMs,
        encryptedCredentialRecords: current.encryptedCredentialRecords,
        manualKeyEnvelopes: current.manualKeyEnvelopes,
        cloudflareEnvelope: envelope,
      );
      if (current.cloudflareEnvelope == null) await _writeBundle(synchronized);
      await client.uploadSnapshot(
        bundle: synchronized,
        idTokenProvider: idTokenProvider,
      );
      return synchronized;
    } finally {
      dek.fillRange(0, dek.length, 0);
    }
  }

  /// Fetches an authenticated encrypted snapshot and quarantines it until an
  /// active manual key authenticates its DEK and every encrypted record.
  Future<VaultRecoveryBundle> fetchCloudflareSnapshot({
    required String vaultId,
    required AureonCloudflareVaultClient client,
    required AureonFirebaseIdTokenProvider idTokenProvider,
  }) async {
    final bundle = await client.fetchSnapshot(
      vaultId: vaultId,
      idTokenProvider: idTokenProvider,
    );
    return importBundle(utf8.encode(jsonEncode(bundle.toJson())));
  }

  Future<VaultRecoveryBundle> replaceCredentialRecords({
    required ManualRecoveryKeySet keySet,
    required List<Map<String, Object?>> credentialRecords,
  }) async {
    final dek = await _dekStore.read(keySet.vaultId, keySet.generation);
    if (dek == null) {
      throw StateError('This device has no unlocked vault DEK. Restore the vault first.');
    }
    final current = await loadBundle();
    if (current == null || current.vaultId != keySet.vaultId ||
        current.generation != keySet.generation) {
      dek.fillRange(0, dek.length, 0);
      throw StateError('The active vault bundle and recovery key set do not match.');
    }
    late final VaultRecoveryBundle bundle;
    try {
      bundle = await _crypto.createBundle(
        keySet: keySet,
        vaultDek: dek,
        credentialRecords: credentialRecords,
        cloudflareEnvelope: current.cloudflareEnvelope,
      );
    } finally {
      dek.fillRange(0, dek.length, 0);
    }
    final monotonicBundle = bundle.createdAtEpochMs > current.createdAtEpochMs
        ? bundle
        : VaultRecoveryBundle(
            vaultId: bundle.vaultId,
            generation: bundle.generation,
            createdAtEpochMs: current.createdAtEpochMs + 1,
            encryptedCredentialRecords: bundle.encryptedCredentialRecords,
            manualKeyEnvelopes: bundle.manualKeyEnvelopes,
            cloudflareEnvelope: bundle.cloudflareEnvelope,
          );
    await _writeBundle(monotonicBundle);
    return monotonicBundle;
  }

  Future<void> _writeBundle(VaultRecoveryBundle bundle, {bool pending = false}) async {
    final bytes = utf8.encode(jsonEncode(bundle.toJson()));
    if (bytes.length > maxBundleBytes) {
      throw StateError('Vault Recovery Bundle exceeds the supported size.');
    }
    final file = await _bundleFile(pending: pending);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    if (await temporary.exists()) await temporary.delete();
    await temporary.writeAsBytes(bytes, flush: true);

    // Windows does not consistently replace an existing destination on rename.
    // Keep the old snapshot until the new file has been promoted successfully.
    if (await backup.exists()) await backup.delete();
    final hadPrevious = await file.exists();
    if (hadPrevious) await file.rename(backup.path);
    try {
      await temporary.rename(file.path);
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
    if (await backup.exists()) {
      try {
        await backup.delete();
      } on FileSystemException {
        // The active snapshot is already committed; a stale backup is harmless
        // and will be cleaned/replaced during the next successful write.
      }
    }
  }

  Future<File> _bundleFile({bool pending = false}) async {
    final root = _rootDirectory ?? await getApplicationSupportDirectory();
    final suffix = pending ? '.pending' : '';
    return File('${root.path}${Platform.pathSeparator}credential-vault.aureon-vault$suffix');
  }

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));
}
