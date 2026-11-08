import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:aureon_contracts/aureon_contracts.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'aureon_metadata_backup.dart';

abstract interface class AureonMetadataKeyStore {
  Future<String?> readKey();
  Future<void> writeKey(String value);
}

class PlatformAureonMetadataKeyStore implements AureonMetadataKeyStore {
  PlatformAureonMetadataKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _keyName = 'aureon.metadata.local-encryption-key.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readKey() => _storage.read(key: _keyName);

  @override
  Future<void> writeKey(String value) => _storage.write(key: _keyName, value: value);
}

/// Device-local metadata catalog. The catalog file is AES-GCM encrypted and
/// its random key is kept in Android/Windows platform secure storage.
/// Portable .aureon-meta archives use a separate passphrase-derived key.
class AureonMetadataStore {
  AureonMetadataStore({
    AureonMetadataKeyStore? keyStore,
    Directory? rootDirectory,
  })  : _keyStore = keyStore ?? PlatformAureonMetadataKeyStore(),
        _rootDirectory = rootDirectory;

  static const _format = 'AUREON-LOCAL-METADATA-CATALOG';
  static const _aadPrefix = 'AUREON|LOCAL-METADATA|v1|';
  static const _maxCatalogBytes = 128 * 1024 * 1024;
  static final _cipher = AesGcm.with256bits();
  static final _random = Random.secure();

  final AureonMetadataKeyStore _keyStore;
  final Directory? _rootDirectory;

  Future<AureonMetadataSnapshot> load() async {
    final directory = await _directory();
    final candidates = <AureonMetadataSnapshot>[];
    var foundAny = false;
    for (var slot = 0; slot < 2; slot++) {
      final file = File('${directory.path}${Platform.pathSeparator}catalog-$slot.aureon');
      if (!await file.exists()) continue;
      foundAny = true;
      try {
        final bytes = await file.readAsBytes();
        candidates.add(await _decryptCatalog(bytes));
      } catch (_) {
        // Keep searching the previous slot. If no valid slot remains, fail closed.
      }
    }
    if (candidates.isEmpty) {
      if (foundAny) throw StateError('AUREON metadata catalog is corrupted or its local secure key is unavailable. Restore an exported metadata backup.');
      return AureonMetadataSnapshot(
        snapshotId: 'local-empty',
        generation: 0,
        createdAtEpochMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      );
    }
    candidates.sort((a, b) => b.generation.compareTo(a.generation));
    return candidates.first;
  }

  Future<void> save(AureonMetadataSnapshot snapshot) async {
    final current = await load();
    if (snapshot.generation < current.generation) {
      throw StateError('Refusing to roll the local metadata catalog back to an older generation.');
    }
    if (snapshot.generation == current.generation &&
        current.snapshotId != 'local-empty' &&
        jsonEncode(snapshot.toJson()) != jsonEncode(current.toJson())) {
      throw StateError('Metadata generation already exists with different content.');
    }
    final directory = await _directory();
    final key = await _getLocalKey();
    final nonce = _randomBytes(12);
    final aad = utf8.encode('$_aadPrefix${snapshot.generation}');
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(snapshot.toJson())),
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    final envelope = utf8.encode(jsonEncode({
      'format': _format,
      'formatVersion': 1,
      'generation': snapshot.generation,
      'nonce': base64Url.encode(nonce),
      'cipherText': base64Url.encode(box.cipherText),
      'mac': base64Url.encode(box.mac.bytes),
    }));
    if (envelope.length > _maxCatalogBytes) throw StateError('AUREON local metadata catalog exceeds the supported size.');
    final slot = snapshot.generation % 2;
    final target = File('${directory.path}${Platform.pathSeparator}catalog-$slot.aureon');
    final temporary = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    if (await temporary.exists()) await temporary.delete();
    await temporary.writeAsBytes(envelope, flush: true);
    if (await backup.exists()) await backup.delete();
    final hadPrevious = await target.exists();
    if (hadPrevious) await target.rename(backup.path);
    try {
      await temporary.rename(target.path);
    } catch (_) {
      if (!await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }
    if (await backup.exists()) {
      try {
        await backup.delete();
      } on FileSystemException {
        // A committed active slot plus the other generation remain recoverable.
      }
    }
  }

  Future<AureonMetadataSnapshot> createFolder(String name, {String? parentId}) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('Folder name is required.');
    final current = await load();
    final id = _newId();
    final folder = AureonMetadataFolder(id: id, name: clean, order: 0);
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
      final order = folder.files.isEmpty ? 0 : folder.files.map((file) => file.order).reduce((a, b) => a > b ? a : b) + 1;
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

  Future<AureonMetadataSnapshot> toggleFavorite(String folderId, String stableKey) async {
    final current = await load();
    var foundFolder = false;
    var foundFile = false;
    final roots = _mapFolders(current.rootFolders, (siblings, folder) {
      if (folder.id != folderId) return folder;
      foundFolder = true;
      final files = folder.files.map((entry) {
        if (entry.reference.stableKey != stableKey) return entry;
        foundFile = true;
        return AureonMetadataFileEntry(
          reference: entry.reference, order: entry.order, tags: entry.tags,
          favorite: !entry.favorite, customLabel: entry.customLabel,
          pendingProviderReconciliation: entry.pendingProviderReconciliation,
        );
      }).toList();
      return _copyFolder(folder, files: files);
    });
    if (!foundFolder || !foundFile) throw StateError('AUREON file reference not found.');
    final updated = _next(current, roots);
    await save(updated);
    return updated;
  }

  Future<AureonMetadataSnapshot> addTagToFile(String folderId, String stableKey, String tag) async {
    final clean = tag.trim();
    if (clean.isEmpty) throw ArgumentError('Tag cannot be empty.');
    final current = await load();
    var foundFolder = false;
    var foundFile = false;
    final roots = _mapFolders(current.rootFolders, (siblings, folder) {
      if (folder.id != folderId) return folder;
      foundFolder = true;
      final files = folder.files.map((entry) {
        if (entry.reference.stableKey != stableKey) return entry;
        foundFile = true;
        return AureonMetadataFileEntry(
          reference: entry.reference, order: entry.order,
          tags: {...entry.tags, clean}.toList(), favorite: entry.favorite,
          customLabel: entry.customLabel,
          pendingProviderReconciliation: entry.pendingProviderReconciliation,
        );
      }).toList();
      return _copyFolder(folder, files: files);
    });
    if (!foundFolder || !foundFile) throw StateError('AUREON file reference not found.');
    final updated = AureonMetadataSnapshot(
      snapshotId: 'metadata-${DateTime.now().microsecondsSinceEpoch}',
      generation: current.generation + 1,
      createdAtEpochMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      rootFolders: roots, virtualFolders: current.virtualFolders,
      savedViews: current.savedViews,
      globalTags: {...current.globalTags, clean}.toList(),
      preferences: current.preferences,
    );
    await save(updated);
    return updated;
  }

  Future<AureonMetadataSnapshot> reorderFile(String folderId, String stableKey, int newIndex) async {
    final current = await load();
    var foundFolder = false;
    var foundFile = false;
    List<AureonMetadataFolder> reorder(List<AureonMetadataFolder> folders) =>
      folders.map((folder) {
        if (folder.id == folderId) {
          foundFolder = true;
          final files = [...folder.files];
          final index = files.indexWhere((entry) => entry.reference.stableKey == stableKey);
          if (index < 0) return folder;
          foundFile = true;
          final item = files.removeAt(index);
          final target = newIndex.clamp(0, files.length).toInt();
          files.insert(target, item);
          return _copyFolder(folder, files: files.asMap().entries.map((entry) =>
            AureonMetadataFileEntry(
              reference: entry.value.reference, order: entry.key,
              tags: entry.value.tags, favorite: entry.value.favorite,
              customLabel: entry.value.customLabel,
              pendingProviderReconciliation: entry.value.pendingProviderReconciliation,
            )).toList());
        }
        return _copyFolder(folder, folders: reorder(folder.folders));
      }).toList();
    final roots = reorder(current.rootFolders);
    if (!foundFolder || !foundFile) throw StateError('AUREON file reference not found.');
    final updated = _next(current, roots);
    await save(updated);
    return updated;
  }

  Future<AureonMetadataSnapshot> reorderFolder(String folderId, int newIndex) async {
    final current = await load();
    var found = false;
    List<AureonMetadataFolder> reorder(List<AureonMetadataFolder> folders) {
      final list = [...folders];
      final index = list.indexWhere((folder) => folder.id == folderId);
      if (index >= 0) {
        found = true;
        final item = list.removeAt(index);
        list.insert(newIndex.clamp(0, list.length).toInt(), item);
        return list.asMap().entries.map((entry) => _copyFolder(entry.value, order: entry.key)).toList();
      }
      return list.map((folder) => _copyFolder(folder, folders: reorder(folder.folders))).toList();
    }
    final roots = reorder(current.rootFolders);
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
      return [...siblings, _copyFolder(folder, order: siblings.length)];
    }
    var found = false;
    List<AureonMetadataFolder> visit(List<AureonMetadataFolder> items) =>
        items.map((item) {
          if (item.id == parentId) {
            found = true;
            if (item.folders.any((child) => child.name.toLowerCase() == folder.name.toLowerCase())) {
              throw StateError('A sibling folder already has this name.');
            }
            return _copyFolder(item, folders: [
              ...item.folders,
              _copyFolder(folder, order: item.folders.length),
            ]);
          }
          return _copyFolder(item, folders: visit(item.folders));
        }).toList();
    final result = visit(siblings);
    if (!found) throw StateError('Parent folder not found.');
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

  Future<Directory> _directory() async {
    final root = _rootDirectory ?? await getApplicationSupportDirectory();
    final directory = Directory('${root.path}${Platform.pathSeparator}AUREON${Platform.pathSeparator}metadata');
    await directory.create(recursive: true);
    return directory;
  }

  Future<List<int>> _getLocalKey() async {
    final stored = await _keyStore.readKey();
    if (stored != null) {
      final key = base64Url.decode(base64Url.normalize(stored));
      if (key.length != 32) throw StateError('AUREON local metadata key has an invalid length.');
      return key;
    }
    final key = _randomBytes(32);
    await _keyStore.writeKey(base64Url.encode(key));
    final confirmed = await _keyStore.readKey();
    if (confirmed == null || base64Url.decode(base64Url.normalize(confirmed)).length != 32) {
      throw StateError('Could not safely initialize AUREON local metadata key.');
    }
    return key;
  }

  Future<AureonMetadataSnapshot> _decryptCatalog(List<int> bytes) async {
    if (bytes.isEmpty || bytes.length > _maxCatalogBytes) {
      throw const FormatException('Local metadata catalog size is invalid.');
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map) throw const FormatException('Invalid local metadata catalog envelope.');
    final envelope = value.cast<String, Object?>();
    if (envelope['format'] != _format || envelope['formatVersion'] != 1 ||
        envelope['generation'] is! int) {
      throw const FormatException('Unsupported local metadata catalog format.');
    }
    final generation = envelope['generation'] as int;
    final nonce = _decode(_requiredString(envelope, 'nonce'), 12);
    final cipherText = _decode(_requiredString(envelope, 'cipherText'));
    final mac = _decode(_requiredString(envelope, 'mac'), 16);
    final clear = await _cipher.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(await _getLocalKey()),
      aad: utf8.encode('$_aadPrefix$generation'),
    );
    final payload = jsonDecode(utf8.decode(clear));
    if (payload is! Map) throw const FormatException('Invalid local metadata payload.');
    final snapshot = AureonMetadataSnapshot.fromJson(payload.cast<String, Object?>());
    if (snapshot.generation != generation) throw const FormatException('Local metadata generation mismatch.');
    return snapshot;
  }

  String _newId() {
    final bytes = _randomBytes(16);
    return 'folder-${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  List<int> _randomBytes(int count) => List<int>.generate(count, (_) => _random.nextInt(256));
  List<int> _decode(String value, [int? length]) {
    final bytes = base64Url.decode(base64Url.normalize(value));
    if (length != null && bytes.length != length) throw const FormatException('Invalid local metadata field length.');
    return bytes;
  }

}

String _requiredString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.isEmpty) throw FormatException('Missing or invalid $key.');
  return value;
}
