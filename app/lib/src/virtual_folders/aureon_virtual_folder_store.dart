import 'dart:convert';
import 'dart:math';

import 'package:aureon_contracts/aureon_contracts.dart';

import '../backup/aureon_metadata_backup.dart';
import '../backup/aureon_metadata_store.dart';

/// Virtual-folder memberships share the encrypted local metadata catalog.
/// Adding/removing a membership never calls a provider API or mutates originals.
class AureonVirtualFolderStore {
  AureonVirtualFolderStore({AureonMetadataStore? metadataStore})
      : _metadataStore = metadataStore ?? AureonMetadataStore();

  final AureonMetadataStore _metadataStore;

  Future<List<AureonVirtualFolder>> load() async =>
      (await _metadataStore.load()).virtualFolders;

  Future<void> save(List<AureonVirtualFolder> folders) async {
    final current = await _metadataStore.load();
    final updated = AureonMetadataSnapshot(
      snapshotId: 'metadata-${DateTime.now().microsecondsSinceEpoch}',
      generation: current.generation + 1,
      createdAtEpochMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      rootFolders: current.rootFolders,
      virtualFolders: folders,
      savedViews: current.savedViews,
      globalTags: current.globalTags,
      preferences: current.preferences,
    );
    await _metadataStore.save(updated);
  }

  Future<AureonVirtualFolder> create(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError.value(name, 'name', 'Folder name is required.');
    final folders = await load();
    if (folders.any((folder) => folder.name.toLowerCase() == clean.toLowerCase())) {
      throw StateError('A virtual folder with this name already exists.');
    }
    final folder = AureonVirtualFolder(
      id: _newId(),
      name: clean,
      createdAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
    await save([...folders, folder]);
    return folder;
  }

  Future<void> addItem(String folderId, ProviderFileReference file) async {
    final folders = await load();
    final index = folders.indexWhere((folder) => folder.id == folderId);
    if (index < 0) throw StateError('Virtual folder no longer exists.');
    final updated = [...folders];
    updated[index] = updated[index].add(file);
    await save(updated);
  }

  Future<void> removeItem(String folderId, String stableKey) async {
    final folders = await load();
    final index = folders.indexWhere((folder) => folder.id == folderId);
    if (index < 0) throw StateError('Virtual folder no longer exists.');
    final updated = [...folders];
    updated[index] = updated[index].remove(stableKey);
    await save(updated);
  }

  Future<void> delete(String folderId) async {
    final folders = await load();
    await save(folders.where((folder) => folder.id != folderId).toList());
  }

  String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
