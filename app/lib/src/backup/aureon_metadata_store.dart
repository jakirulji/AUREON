import 'dart:convert';
import 'dart:math';

import 'package:aureon_contracts/aureon_contracts.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'aureon_metadata_backup.dart';

class AureonMetadataStore {
  static const storageKey = 'aureon.metadata.snapshot.v1';

  Future<AureonMetadataSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) {
      return AureonMetadataSnapshot(
        snapshotId: 'local-empty',
        generation: 0,
        createdAtEpochMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      );
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Stored metadata snapshot is invalid.');
    return AureonMetadataSnapshot.fromJson(decoded.cast<String, Object?>());
  }

  Future<AureonMetadataSnapshot> createFolder(String name, {String? parentId}) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('Folder name is required.');
    final current = await load();
    final id = _newId();
    final folder = AureonMetadataFolder(
      id: id, name: clean, order: 0,
    );
    final roots = _insertFolder(current.rootFolders, folder, parentId);
    final updated = _next(current, roots);
    await save(updated);
    return updated;
  }

  Future<AureonMetadataSnapshot> renameFolder(String folderId, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('Folder name is required.');
    final current = await load();
    var found = false;
    final roots = _mapFolders(current.rootFolders, (siblings, folder) {
      if (folder.id != folderId) return folder;
      found = true;
      if (siblings.any((item) => item.id != folderId && item.name.toLowerCase() == clean.toLowerCase())) {
        throw StateError('A sibling folder already has this name.');
      }
      return AureonMetadataFolder(
        id: folder.id, name: clean, order: folder.order, folders: folder.folders,
        files: folder.files, tags: folder.tags, colorArgb: folder.colorArgb,
      );
    });
    if (!found) throw StateError('Folder not found.');
    final updated = _next(current, roots);
    await save(updated);
    return updated;
  }

  Future<AureonMetadataSnapshot> deleteFolder(String folderId) async {
    final current = await load();
    var removed = false;
    List<AureonMetadataFolder> remove(List<AureonMetadataFolder> folders) {
      final kept = <AureonMetadataFolder>[];
      for (final folder in folders) {
        if (folder.id == folderId) { removed = true; continue; }
        kept.add(AureonMetadataFolder(
          id: folder.id, name: folder.name, order: folder.order,
          folders: remove(folder.folders), files: folder.files,
          tags: folder.tags, colorArgb: folder.colorArgb,
        ));
      }
      return kept;
    }
    final roots = remove(current.rootFolders);
    if (!removed) throw StateError('Folder not found.');
    final updated = _next(current, roots);
    await save(updated);
    return updated;
  }

  Future<AureonMetadataSnapshot> addFileToFolder(String folderId, ProviderFileReference reference) async {
    final current = await load();
    var found = false;
    final roots = _mapFolders(current.rootFolders, (siblings, folder) {
      if (folder.id != folderId) return folder;
      found = true;
      if (folder.files.any((file) => file.reference.stableKey == reference.stableKey)) return folder;
      final order = folder.files.isEmpty ? 0 : folder.files.map((file) => file.order).reduce(max) + 1;
      return AureonMetadataFolder(
        id: folder.id, name: folder.name, order: folder.order,
        folders: folder.folders,
        files: [...folder.files, AureonMetadataFileEntry(reference: reference, order: order)],
        tags: folder.tags, colorArgb: folder.colorArgb,
      );
    });
    if (!found) throw StateError('Folder not found.');
    final updated = _next(current, roots);
    await save(updated);
    return updated;
  }

  Future<AureonMetadataSnapshot> removeFileFromFolder(String folderId, String stableKey) async {
    final current = await load();
    var found = false;
    final roots = _mapFolders(current.rootFolders, (siblings, folder) {
      if (folder.id != folderId) return folder;
      found = true;
      return AureonMetadataFolder(
        id: folder.id, name: folder.name, order: folder.order,
        folders: folder.folders,
        files: folder.files.where((file) => file.reference.stableKey != stableKey).toList(),
        tags: folder.tags, colorArgb: folder.colorArgb,
      );
    });
    if (!found) throw StateError('Folder not found.');
    final updated = _next(current, roots);
    await save(updated);
    return updated;
  }

  Future<AureonMetadataSnapshot> moveFolder(String folderId, {String? newParentId}) async {
    final current = await load();
    final moving = _findFolder(current.rootFolders, folderId);
    if (moving == null) throw StateError('Folder not found.');
    if (newParentId == folderId || (newParentId != null && _containsFolder(moving, newParentId))) {
      throw StateError('A folder cannot be moved inside itself or one of its descendants.');
    }
    final without = _removeFolder(current.rootFolders, folderId);
    if (newParentId != null && _findFolder(without, newParentId) == null) {
      throw StateError('Destination folder not found.');
    }
    final roots = _insertFolder(without, moving, newParentId);
    final updated = _next(current, roots);
    await save(updated);
    return updated;
  }

  AureonMetadataSnapshot _next(AureonMetadataSnapshot current, List<AureonMetadataFolder> roots) =>
      AureonMetadataSnapshot(
        snapshotId: 'metadata-${DateTime.now().microsecondsSinceEpoch}',
        generation: current.generation + 1,
        createdAtEpochMs: DateTime.now().toUtc().millisecondsSinceEpoch,
        rootFolders: roots,
        virtualFolders: current.virtualFolders,
        savedViews: current.savedViews,
        globalTags: current.globalTags,
        preferences: current.preferences,
      );

  List<AureonMetadataFolder> _insertFolder(
    List<AureonMetadataFolder> siblings, AureonMetadataFolder folder, String? parentId,
  ) {
    if (parentId == null) {
      if (siblings.any((item) => item.name.toLowerCase() == folder.name.toLowerCase())) {
        throw StateError('A sibling folder already has this name.');
      }
      final result = [...siblings, _copyFolder(folder, order: siblings.length)];
      return result;
    }
    var found = false;
    var found = false;
    final result = siblings.map((item) {
      if (item.id == parentId) {
        found = true;
        if (item.folders.any((child) => child.name.toLowerCase() == folder.name.toLowerCase())) {
          throw StateError('A sibling folder already has this name.');
        }
        return _copyFolder(item, folders: [...item.folders, _copyFolder(folder, order: item.folders.length)]);
      }
      return _copyFolder(item, folders: _insertFolderIfPresent(item.folders, folder, parentId, (value) { found = found || value; }));
    }).toList();
    if (!found) throw StateError('Parent folder not found.');
    return result;
  }

  List<AureonMetadataFolder> _insertFolderIfPresent(
    List<AureonMetadataFolder> siblings, AureonMetadataFolder folder, String parentId, void Function(bool) report,
  ) {
    var found = false;
    final result = siblings.map((item) {
      if (item.id == parentId) {
        found = true;
        if (item.folders.any((child) => child.name.toLowerCase() == folder.name.toLowerCase())) {
          throw StateError('A sibling folder already has this name.');
        }
        return _copyFolder(item, folders: [...item.folders, _copyFolder(folder, order: item.folders.length)]);
      }
      return _copyFolder(item, folders: _insertFolderIfPresent(item.folders, folder, parentId, (value) { found = found || value; }));
    }).toList();
    report(found);
    return result;
  }

  List<AureonMetadataFolder> _mapFolders(
    List<AureonMetadataFolder> folders,
    AureonMetadataFolder Function(List<AureonMetadataFolder>, AureonMetadataFolder) transform,
  ) {
    return folders.map((folder) {
      final nested = _mapFolders(folder.folders, transform);
      final withChildren = _copyFolder(folder, folders: nested);
      return transform(folders, withChildren);
    }).toList();
  }

  AureonMetadataFolder? _findFolder(List<AureonMetadataFolder> folders, String id) {
    for (final folder in folders) {
      if (folder.id == id) return folder;
      final nested = _findFolder(folder.folders, id);
      if (nested != null) return nested;
    }
    return null;
  }

  bool _containsFolder(AureonMetadataFolder folder, String id) =>
      folder.id == id || folder.folders.any((child) => _containsFolder(child, id));

  List<AureonMetadataFolder> _removeFolder(List<AureonMetadataFolder> folders, String id) =>
      folders.where((folder) => folder.id != id).map((folder) =>
        _copyFolder(folder, folders: _removeFolder(folder.folders, id))).toList();

  AureonMetadataFolder _copyFolder(
    AureonMetadataFolder folder, {
    String? name,
    int? order,
    List<AureonMetadataFolder>? folders,
    List<AureonMetadataFileEntry>? files,
  }) => AureonMetadataFolder(
    id: folder.id, name: name ?? folder.name, order: order ?? folder.order,
    folders: folders ?? folder.folders, files: files ?? folder.files,
    tags: folder.tags, colorArgb: folder.colorArgb,
  );

  String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return 'folder-${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  Future<void> save(AureonMetadataSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(storageKey, jsonEncode(snapshot.toJson()))) {
      throw StateError('Could not persist AUREON metadata snapshot.');
    }
  }
}
