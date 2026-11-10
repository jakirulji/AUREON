import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../auth/aureon_firebase_auth_service.dart';
import 'aureon_cloudflare_vault_client.dart';

import '../virtual_folders/aureon_virtual_folder_store.dart';
import 'aureon_metadata_backup.dart';
import 'aureon_metadata_store.dart';
import 'aureon_recovery_key_service.dart';
import 'aureon_credential_vault_store.dart';

class AureonBackupPage extends StatefulWidget {
  const AureonBackupPage({super.key, this.auth});

  final AureonFirebaseAuthService? auth;

  @override
  State<AureonBackupPage> createState() => _AureonBackupPageState();
}

class _AureonBackupPageState extends State<AureonBackupPage> {
  final _recovery = AureonRecoveryKeyService();
  final _metadataCodec = AureonMetadataBackupCodec();
  final _metadataStore = AureonMetadataStore();
  final _virtualFolders = AureonVirtualFolderStore();
  final _vaultStore = AureonCredentialVaultStore();
  final _fallbackAuth = AureonFirebaseAuthService();
  String get _cloudflareApiUrl => _auth.activeBackendProfile?.workerBaseUrl ?? '';

  AureonFirebaseAuthService get _auth => widget.auth ?? _fallbackAuth;

  ManualRecoveryKeySet? _keySet;
  VaultRecoveryBundle? _vaultBundle;
  bool _busy = false;
  String _status = 'Local recovery tools are ready. Cloudflare vault sync and recovery use the AUREON Central Backend after you sign in.';
  List<String> _restoreConflicts = const [];

  @override
  void initState() {
    super.initState();
    _loadExistingVaultBundle();
  }

  Future<void> _loadExistingVaultBundle() async {
    try {
      final bundle = await _vaultStore.loadPendingBundle() ?? await _vaultStore.loadBundle();
      if (mounted && bundle != null) setState(() => _vaultBundle = bundle);
    } catch (error) {
      if (mounted) setState(() => _status = 'Local Recovery Bundle could not be read: $error');
    }
  }

  String _newVaultId() {
    final random = Random.secure();
    final suffix = List<int>.generate(16, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return 'vault-$suffix';
  }

  Future<String?> _askPassphrase({required String title, bool confirm = false}) async {
    final first = TextEditingController();
    final second = TextEditingController();
    var obscure = true;
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: first,
              obscureText: obscure,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Passphrase (14+ characters)'),
            ),
            if (confirm)
              TextField(
                controller: second,
                obscureText: obscure,
                decoration: const InputDecoration(labelText: 'Confirm passphrase'),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setDialogState(() => obscure = !obscure),
                icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                label: Text(obscure ? 'Show' : 'Hide'),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (first.text.trim().length < 14 ||
                    (confirm && first.text != second.text)) {
                  return;
                }
                Navigator.pop(dialogContext, first.text);
              },
              child: const Text('Continue'),
            ),
          ],
        )),
      );
    } finally {
      first.dispose();
      second.dispose();
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'Operation failed: $error');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generateKeys() => _run(() async {
    final existing = _vaultBundle ?? await _vaultStore.loadPendingBundle() ?? await _vaultStore.loadBundle();
    if (existing != null) {
      setState(() => _vaultBundle = existing);
      throw StateError('A local vault already exists. Import its matching .key file instead of creating a new vault.');
    }
    final set = _recovery.generateKeySet(vaultId: _newVaultId());
    final bundle = await _vaultStore.initialize(set);
    setState(() {
      _keySet = set;
      _vaultBundle = bundle;
      _status = 'Five independent keys generated. A random vault DEK is protected by platform secure storage and the encrypted Recovery Bundle is ready to export.';
    });
  });

  Future<void> _exportPlainTextKeys() => _run(() async {
    final set = _keySet;
    if (set == null) throw StateError('Generate or import a recovery key set first.');
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save plaintext AUREON recovery keys',
      fileName: 'AUREON-Recovery-Keys.txt',
      bytes: Uint8List.fromList(utf8.encode(set.toPlainText())),
    );
    if (uri != null && mounted) setState(() => _status = 'Plaintext recovery key TXT exported. Keep it offline and protected.');
  });

  Future<void> _exportEncryptedKeyFile() => _run(() async {
    final set = _keySet;
    if (set == null) throw StateError('Generate or import a recovery key set first.');
    final passphrase = await _askPassphrase(title: 'Protect AUREON-Recovery.key', confirm: true);
    if (passphrase == null) return;
    final bytes = await _recovery.exportEncryptedKeyFile(keySet: set, passphrase: passphrase);
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save encrypted AUREON recovery key',
      fileName: 'AUREON-Recovery.key',
      bytes: Uint8List.fromList(bytes),
    );
    if (uri != null && mounted) setState(() => _status = 'Encrypted .key file exported. The passphrase is not stored by AUREON.');
  });

  Future<void> _importEncryptedKeyFile() => _run(() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['key'],
    );
    if (file == null) return;
    final passphrase = await _askPassphrase(title: 'Unlock encrypted recovery key file');
    if (passphrase == null) return;
    final knownBundle = _vaultBundle ?? await _vaultStore.loadPendingBundle() ?? await _vaultStore.loadBundle();
    final imported = await _recovery.importEncryptedKeyFile(
      bytes: await file.readAsBytes(),
      passphrase: passphrase,
      expectedVaultId: knownBundle?.vaultId,
    );
    setState(() {
      _keySet = imported;
      _vaultBundle = knownBundle;
      _status = knownBundle == null
          ? 'Encrypted key file opened. Import the matching encrypted Vault Recovery Bundle to recover the vault.'
          : 'Encrypted key file opened and vault identity matched. Restore the matching bundle to unlock this device.';
    });
  });

  Future<void> _exportVaultBundle() => _run(() async {
    final bytes = await _vaultStore.exportBundle();
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Export encrypted AUREON Vault Recovery Bundle',
      fileName: 'AUREON-Vault-Recovery.aureon-vault',
      bytes: bytes,
    );
    if (uri != null && mounted) {
      setState(() => _status = 'Encrypted Vault Recovery Bundle exported. Store it outside this device and Cloudflare. It contains no plaintext recovery keys or OAuth tokens.');
    }
  });

  Future<void> _importVaultBundle() => _run(() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['aureon-vault'],
    );
    if (file == null) return;
    final bundle = await _vaultStore.importBundle(await file.readAsBytes());
    final existingKeys = _keySet;
    if (existingKeys != null &&
        (existingKeys.vaultId != bundle.vaultId ||
         existingKeys.generation != bundle.generation)) {
      setState(() => _keySet = null);
    }
    setState(() {
      _vaultBundle = bundle;
      _status = 'Encrypted Recovery Bundle imported: vault ${bundle.vaultId}, generation ${bundle.generation}, ${bundle.encryptedCredentialRecords.length} encrypted credential records. Import its matching .key file to unlock.';
    });
  });

  Future<String?> _chooseManualKey(ManualRecoveryKeySet keys) => showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Choose a recovery key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < keys.keys.length; i++)
            ListTile(
              leading: CircleAvatar(radius: 13, child: Text('${i + 1}', style: const TextStyle(fontSize: 11))),
              title: Text(keys.keys[i].id, style: const TextStyle(fontSize: 12)),
              subtitle: const Text('Use this one key to unlock the vault'),
              onTap: () => Navigator.pop(dialogContext, keys.keys[i].id),
            ),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel'))],
    ),
  );

  Future<void> _restoreVaultBundle() => _run(() async {
    final keys = _keySet;
    final bundle = _vaultBundle ?? await _vaultStore.loadPendingBundle() ?? await _vaultStore.loadBundle();
    if (keys == null) throw StateError('Import the matching AUREON-Recovery.key file first.');
    if (bundle == null) throw StateError('Import the matching .aureon-vault bundle first.');
    if (keys.vaultId != bundle.vaultId || keys.generation != bundle.generation) {
      throw StateError('The selected key file and Recovery Bundle do not match.');
    }
    final selectedKeyId = await _chooseManualKey(keys);
    if (selectedKeyId == null) return;
    final result = await _vaultStore.restoreWithManualKey(
      bundle: bundle,
      keySet: keys,
      manualKeyId: selectedKeyId,
    );
    if (mounted) {
      setState(() => _status = 'Manual recovery succeeded using the selected active key. The imported bundle passed authentication and is now promoted to the active local snapshot; the vault DEK is protected in device secure storage. Restored ${result.length} encrypted-vault credential records; provider sign-in/refresh integration is still pending.');
    }
  });

  Future<void> _rotateRecoveryGeneration() => _run(() async {
    final currentKeys = _keySet;
    if (currentKeys == null) throw StateError('Import the current .key file before rotating recovery keys.');
    final currentBundle = _vaultBundle ?? await _vaultStore.loadBundle();
    if (currentBundle == null) throw StateError('The active Vault Recovery Bundle is missing.');
    if (currentBundle.generation != currentKeys.generation ||
        currentBundle.vaultId != currentKeys.vaultId) {
      throw StateError('Current key set and active vault do not match.');
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rotate all recovery keys?'),
        content: const Text(
          'AUREON will create a new vault generation and five new independent keys. '
          'You must save the new plaintext TXT, encrypted .key and encrypted Vault Bundle. '
          'The current generation remains active until all three exports succeed. '
          'Old copies stored elsewhere cannot be remotely revoked.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Continue')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final passphrase = await _askPassphrase(title: 'Protect the new AUREON-Recovery.key', confirm: true);
    if (passphrase == null) return;
    final selectedKeyId = await _chooseManualKey(currentKeys);
    if (selectedKeyId == null) return;

    final plan = await _vaultStore.prepareRotation(
      currentKeySet: currentKeys,
      currentManualKeyId: selectedKeyId,
    );
    final encryptedKeyBytes = await _recovery.exportEncryptedKeyFile(
      keySet: plan.keySet,
      passphrase: passphrase,
    );
    final bundleBytes = Uint8List.fromList(utf8.encode(jsonEncode(plan.bundle.toJson())));

    final txtUri = await FilePicker.saveFile(
      dialogTitle: 'Save new plaintext AUREON recovery keys',
      fileName: 'AUREON-Recovery-Keys.txt',
      bytes: Uint8List.fromList(utf8.encode(plan.keySet.toPlainText())),
    );
    if (txtUri == null || !mounted) {
      setState(() => _status = 'Rotation cancelled before commit. The previous generation remains active.');
      return;
    }
    final keyUri = await FilePicker.saveFile(
      dialogTitle: 'Save new encrypted AUREON recovery key',
      fileName: 'AUREON-Recovery.key',
      bytes: Uint8List.fromList(encryptedKeyBytes),
    );
    if (keyUri == null || !mounted) {
      setState(() => _status = 'Rotation not committed. The previous generation remains active. An uncommitted TXT export may exist; keep it separate and do not use it to replace the current backup.');
      return;
    }
    final bundleUri = await FilePicker.saveFile(
      dialogTitle: 'Save new encrypted AUREON Vault Recovery Bundle',
      fileName: 'AUREON-Vault-Recovery.aureon-vault',
      bytes: bundleBytes,
    );
    if (bundleUri == null || !mounted) {
      setState(() => _status = 'Rotation not committed. The previous generation remains active. Keep any partial new exports separate.');
      return;
    }

    await _vaultStore.commitRotation(currentKeySet: currentKeys, plan: plan);
    if (mounted) {
      setState(() {
        _keySet = plan.keySet;
        _vaultBundle = plan.bundle;
        _status = 'Recovery generation ${plan.keySet.generation} is now active. New TXT, .key and Vault Bundle exports were saved. Store them separately; old-generation external backups remain independently decryptable.';
      });
    }
  });

  AureonCloudflareVaultClient _cloudflareClient() {
    if (_cloudflareApiUrl.trim().isEmpty) {
      throw StateError('No active Cloudflare backend profile is configured. Open Account → Your backend and save your own Worker URL first.');
    }
    return AureonCloudflareVaultClient(baseUrl: _cloudflareApiUrl);
  }

  Future<void> _syncCloudflare() => _run(() async {
    if (!_auth.isConfigured) throw StateError('Configure Firebase before cloud vault sync.');
    final user = await _auth.reloadUser();
    if (!user.emailVerified) {
      throw StateError('Verify your AUREON account email before cloud vault sync.');
    }
    final password = await _askAccountPassword();
    if (password == null) return;
    await _auth.reauthenticate(password: password);
    final client = _cloudflareClient();
    late final VaultRecoveryBundle bundle;
    try {
      bundle = await _vaultStore.syncWithCloudflare(
        client: client,
        idTokenProvider: () => _auth.getIdToken(),
      );
    } finally {
      client.close();
    }
    if (mounted) {
      setState(() {
        _vaultBundle = bundle;
        _status = 'Encrypted credential-vault snapshot synchronized to Cloudflare D1. Snapshot generation ${bundle.generation}; ${bundle.encryptedCredentialRecords.length} encrypted records. Provider file bytes and plaintext OAuth tokens were not uploaded.';
      });
    }
  });

  Future<String?> _askVaultId(String initialValue) async {
    final controller = TextEditingController(text: initialValue);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cloud recovery vault ID'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Vault ID from your Recovery Bundle'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Continue')),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<String?> _askAccountPassword() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Recent account verification'),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'AUREON account password'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Reauthenticate')),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _restoreCloudflare() => _run(() async {
    if (!_auth.isConfigured) throw StateError('Configure Firebase before Cloudflare recovery.');
    final user = await _auth.reloadUser();
    if (!user.emailVerified) {
      throw StateError('Verify your AUREON account email before cloud recovery.');
    }
    final password = await _askAccountPassword();
    if (password == null) return;
    await _auth.reauthenticate(password: password);
    final known = _vaultBundle ?? await _vaultStore.loadPendingBundle() ?? await _vaultStore.loadBundle();
    final vaultId = await _askVaultId(known?.vaultId ?? '');
    if (vaultId == null || vaultId.isEmpty) return;
    final client = _cloudflareClient();
    late final List<Map<String, Object?>> records;
    try {
      records = await _vaultStore.restoreWithCloudflare(
        vaultId: vaultId,
        client: client,
        idTokenProvider: () => _auth.getIdToken(),
      );
    } finally {
      client.close();
    }
    final restored = await _vaultStore.loadBundle();
    if (mounted) {
      setState(() {
        _vaultBundle = restored;
        _status = 'Cloudflare-assisted recovery succeeded after recent password reauthentication. Restored ${records.length} encrypted credential records. The DEK was delivered only as a device-bound envelope and stored in platform secure storage.';
      });
    }
  });

  Future<AureonMetadataSnapshot> _currentSnapshot() async {
    final previous = await _metadataStore.load();
    final folders = await _virtualFolders.load();
    return AureonMetadataSnapshot(
      snapshotId: 'metadata-${DateTime.now().microsecondsSinceEpoch}',
      generation: previous.generation + 1,
      createdAtEpochMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      rootFolders: previous.rootFolders,
      virtualFolders: folders,
      savedViews: previous.savedViews,
      globalTags: previous.globalTags,
      preferences: previous.preferences,
    );
  }

  Future<void> _exportMetadata() => _run(() async {
    final passphrase = await _askPassphrase(title: 'Set independent metadata-backup passphrase', confirm: true);
    if (passphrase == null) return;
    final snapshot = await _currentSnapshot();
    final bytes = await _metadataCodec.encrypt(snapshot, passphrase);
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save encrypted AUREON metadata backup',
      fileName: 'AUREON-Metadata-Backup.aureon-meta',
      bytes: Uint8List.fromList(bytes),
    );
    if (uri == null) return;
    await _metadataStore.save(snapshot);
    if (mounted) {
      setState(() => _status = 'Encrypted metadata archive exported. It preserves the serialized folder tree, order, virtual folders, provider IDs, tags, favourites, saved views and preferences.');
    }
  });

  Future<void> _importMetadata() => _run(() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['aureon-meta'],
    );
    if (file == null) return;
    final passphrase = await _askPassphrase(title: 'Unlock metadata backup');
    if (passphrase == null) return;
    final backup = await _metadataCodec.decrypt(await file.readAsBytes(), passphrase);
    final current = await _currentSnapshot();
    final result = AureonMetadataRestorePlanner().merge(
      current: current,
      backup: backup,
      // No live provider inventory exists in this preview yet. Keep references
      // pending; never claim they are live or recreate remote objects.
    );
    await _metadataStore.save(result.snapshot);
    await _virtualFolders.save(result.snapshot.virtualFolders);
    if (mounted) {
      setState(() {
        _restoreConflicts = result.conflicts;
        _status = 'Metadata restored as a merge. ${result.pendingProviderReferences} provider references are pending account re-link and re-index; ${result.conflicts.length} conflicts need review.';
      });
    }
  });

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      const Text('Recovery & backups', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const Text('Two independent recovery systems. Losing the credential-vault keys must not destroy your AUREON folder organization.', style: TextStyle(color: Color(0xFF9AA8BD))),
      const SizedBox(height: 18),
      _section(
        title: 'Manual credential-vault recovery',
        subtitle: 'Exactly five independent 256-bit keys. Any one active key can unwrap the same vault DEK when the matching encrypted Vault Recovery Bundle is available.',
        children: [
          if (_keySet == null && _vaultBundle == null)
            FilledButton.icon(
              onPressed: _busy ? null : _generateKeys,
              icon: const Icon(Icons.key_outlined),
              label: const Text('Generate five recovery keys'),
            )
          else if (_keySet == null) ...[
            Text('Existing vault: ${_vaultBundle!.vaultId} • Generation ${_vaultBundle!.generation}', style: const TextStyle(fontSize: 12, color: Color(0xFF9AA8BD))),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _importEncryptedKeyFile,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Import matching .key file'),
            ),
            const Text('A vault already exists on this device. A new key set will not be generated over it. Import the matching recovery-key file to unlock it.', style: TextStyle(fontSize: 12, color: Color(0xFFFFD27A))),
          ]
          else ...[
            Text('Vault: ${_keySet!.vaultId} • Generation ${_keySet!.generation}', style: const TextStyle(fontSize: 12, color: Color(0xFF9AA8BD))),
            const SizedBox(height: 8),
            for (var i = 0; i < _keySet!.keys.length; i++)
              ListTile(
                dense: true,
                leading: CircleAvatar(radius: 13, child: Text('${i + 1}', style: const TextStyle(fontSize: 11))),
                title: Text(_keySet!.keys[i].id, style: const TextStyle(fontSize: 12)),
                subtitle: const Text('256-bit key • hidden from screen', style: TextStyle(fontSize: 11)),
              ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: _busy ? null : _exportPlainTextKeys, icon: const Icon(Icons.text_snippet_outlined), label: const Text('Export TXT')),
              OutlinedButton.icon(onPressed: _busy ? null : _exportEncryptedKeyFile, icon: const Icon(Icons.lock_outline), label: const Text('Export .key')),
              OutlinedButton.icon(onPressed: _busy ? null : _importEncryptedKeyFile, icon: const Icon(Icons.file_open_outlined), label: const Text('Import .key')),
              OutlinedButton.icon(onPressed: _busy ? null : _rotateRecoveryGeneration, icon: const Icon(Icons.autorenew), label: const Text('Rotate recovery keys')),
            ]),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: _busy ? null : _exportVaultBundle, icon: const Icon(Icons.inventory_2_outlined), label: const Text('Export Vault Bundle')),
            OutlinedButton.icon(onPressed: _busy ? null : _importVaultBundle, icon: const Icon(Icons.file_open_outlined), label: const Text('Import Vault Bundle')),
            FilledButton.tonalIcon(onPressed: _busy ? null : _restoreVaultBundle, icon: const Icon(Icons.lock_open_outlined), label: const Text('Unlock / Restore Vault')),
          ]),
          if (_vaultBundle != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Bundle ready • generation ${_vaultBundle!.generation} • ${_vaultBundle!.encryptedCredentialRecords.length} encrypted credential records • Cloudflare envelope: ${_vaultBundle!.cloudflareEnvelope == null ? "not provisioned" : "present"}', style: const TextStyle(fontSize: 11, color: Color(0xFF9AA8BD))),
            ),
          const SizedBox(height: 8),
          const Text('The TXT contains plaintext recovery keys. The .key file encrypts all five keys using Argon2id + AES-256-GCM. The separate .aureon-vault file contains encrypted credential records and wrapped-DEK envelopes, never plaintext keys or OAuth tokens. The local DEK is stored through platform secure storage. Cloudflare snapshot sync/recovery is available in the section below; provider OAuth/token refresh integration remains pending.', style: TextStyle(fontSize: 12, color: Color(0xFFFFD27A))),
        ],
      ),
      const SizedBox(height: 14),
      _section(
        title: 'Cloudflare-assisted credential-vault recovery',
        subtitle: 'Encrypted credential snapshot only. Cloudflare Worker wraps the vault DEK; recovery requires a verified Firebase account and recent password reauthentication.',
        children: [
          Text(
            _cloudflareApiUrl.trim().isEmpty
                ? 'Cloudflare API URL: not configured in this build.'
                : 'Cloudflare API: $_cloudflareApiUrl',
            style: const TextStyle(fontSize: 12, color: Color(0xFF9AA8BD)),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy || _cloudflareApiUrl.trim().isEmpty ? null : _syncCloudflare,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Sync encrypted vault snapshot'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy || _cloudflareApiUrl.trim().isEmpty ? null : _restoreCloudflare,
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Recover vault from Cloudflare'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Cloudflare is not a substitute for the offline TXT/.key + portable Vault Bundle. Keep an independent bundle copy. The current D1 snapshot limit is 900 KB; provider file contents and E2E content keys never pass through this service.',
            style: TextStyle(fontSize: 12, color: Color(0xFFFFD27A)),
          ),
        ],
      ),
      const SizedBox(height: 14),
      _section(
        title: 'Independent AUREON metadata backup',
        subtitle: 'Encrypted with a separate passphrase and key hierarchy—not the five Manual Recovery Keys or the credential-vault DEK.',
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _exportMetadata,
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Create encrypted metadata backup'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _importMetadata,
            icon: const Icon(Icons.settings_backup_restore_outlined),
            label: const Text('Restore metadata backup'),
          ),
          const SizedBox(height: 8),
          const Text('Archive format preserves nested AUREON folder hierarchy and ordering, file/provider identity references, virtual-folder memberships, tags, favourites, saved views and organization preferences. Restore merges by stable IDs; provider references remain pending until official account re-link and inventory reconciliation.', style: TextStyle(fontSize: 12, color: Color(0xFF9AA8BD))),
          const SizedBox(height: 8),
          const Text('Store exported backups outside the phone (for example, an offline drive). This build does not yet provide automatic off-device/cloud metadata replication or live provider re-indexing.', style: TextStyle(fontSize: 12, color: Color(0xFFFFD27A))),
        ],
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFF111A2E), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF26334A))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, color: Color(0xFF64E6C2)),
          const SizedBox(width: 10),
          Expanded(child: Text(_status, style: const TextStyle(fontSize: 12))),
        ]),
      ),
      if (_restoreConflicts.isNotEmpty)
        ExpansionTile(
          title: Text('Restore conflicts (${_restoreConflicts.length})'),
          children: _restoreConflicts.map((conflict) => ListTile(dense: true, leading: const Icon(Icons.warning_amber_outlined, color: Color(0xFFFFC477)), title: Text(conflict, style: const TextStyle(fontSize: 12)))).toList(),
        ),
      if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
    ],
  );

  Widget _section({required String title, required String subtitle, required List<Widget> children}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF111A2E), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF26334A))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF9AA8BD))),
          const SizedBox(height: 14),
          ...children,
        ]),
      );
}
