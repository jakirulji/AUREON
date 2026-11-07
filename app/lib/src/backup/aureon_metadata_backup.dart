import 'dart:convert';
import 'dart:math';

import 'package:aureon_contracts/aureon_contracts.dart';
import 'package:cryptography/cryptography.dart';

class AureonMetadataFileEntry {
  const AureonMetadataFileEntry({
    required this.reference,
    this.order = 0,
    this.tags = const [],
    this.favorite = false,
    this.customLabel,
    this.pendingProviderReconciliation = true,
  });

  final ProviderFileReference reference;
  final int order;
  final List<String> tags;
  final bool favorite;
  final String? customLabel;
  final bool pendingProviderReconciliation;

  Map<String, Object?> toJson() => {
    'reference': reference.toJson(),
    'order': order,
    'tags': tags,
    'favorite': favorite,
    'customLabel': customLabel,
    'pendingProviderReconciliation': pendingProviderReconciliation,
  };

  factory AureonMetadataFileEntry.fromJson(Map<String, Object?> json) {
    final rawReference = json['reference'];
    if (rawReference is! Map) throw const FormatException('Metadata file is missing provider identity.');
    final tags = json['tags'];
    if (tags is! List || tags.any((tag) => tag is! String)) {
      throw const FormatException('Invalid metadata file tags.');
    }
    return AureonMetadataFileEntry(
      reference: ProviderFileReference.fromJson(rawReference.cast<String, Object?>()),
      order: json['order'] is int ? json['order'] as int : 0,
      tags: tags.cast<String>(),
      favorite: json['favorite'] == true,
      customLabel: json['customLabel'] as String?,
      pendingProviderReconciliation: json['pendingProviderReconciliation'] != false,
    );
  }
}

/// Logical AUREON folder tree. Child order and file order are explicit and
/// independent of provider-native hierarchy.
class AureonMetadataFolder {
  const AureonMetadataFolder({
    required this.id,
    required this.name,
    this.order = 0,
    this.folders = const [],
    this.files = const [],
    this.tags = const [],
    this.colorArgb,
  });

  final String id;
  final String name;
  final int order;
  final List<AureonMetadataFolder> folders;
  final List<AureonMetadataFileEntry> files;
  final List<String> tags;
  final int? colorArgb;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'order': order,
    'folders': folders.map((folder) => folder.toJson()).toList(),
    'files': files.map((file) => file.toJson()).toList(),
    'tags': tags,
    'colorArgb': colorArgb,
  };

  factory AureonMetadataFolder.fromJson(Map<String, Object?> json) {
    final id = _requiredString(json, 'id');
    final name = _requiredString(json, 'name');
    final folders = json['folders'];
    final files = json['files'];
    final tags = json['tags'];
    if (folders is! List || files is! List || tags is! List ||
        tags.any((tag) => tag is! String)) {
      throw const FormatException('Invalid AUREON folder hierarchy.');
    }
    return AureonMetadataFolder(
      id: id,
      name: name,
      order: json['order'] is int ? json['order'] as int : 0,
      folders: folders.map((value) {
        if (value is! Map) throw const FormatException('Invalid nested folder.');
        return AureonMetadataFolder.fromJson(value.cast<String, Object?>());
      }).toList(),
      files: files.map((value) {
        if (value is! Map) throw const FormatException('Invalid nested file.');
        return AureonMetadataFileEntry.fromJson(value.cast<String, Object?>());
      }).toList(),
      tags: tags.cast<String>(),
      colorArgb: json['colorArgb'] as int?,
    );
  }
}

class AureonSavedView {
  const AureonSavedView({
    required this.id,
    required this.name,
    this.query = '',
    this.sortField = 'name',
    this.descending = false,
    this.filterTags = const [],
  });

  final String id;
  final String name;
  final String query;
  final String sortField;
  final bool descending;
  final List<String> filterTags;

  Map<String, Object?> toJson() => {
    'id': id, 'name': name, 'query': query, 'sortField': sortField,
    'descending': descending, 'filterTags': filterTags,
  };

  factory AureonSavedView.fromJson(Map<String, Object?> json) {
    final tags = json['filterTags'] ?? const [];
    if (tags is! List || tags.any((tag) => tag is! String)) {
      throw const FormatException('Invalid saved-view tag filters.');
    }
    return AureonSavedView(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      query: json['query'] as String? ?? '',
      sortField: json['sortField'] as String? ?? 'name',
      descending: json['descending'] == true,
      filterTags: tags.cast<String>(),
    );
  }
}

class AureonMetadataSnapshot {
  const AureonMetadataSnapshot({
    required this.snapshotId,
    required this.generation,
    required this.createdAtEpochMs,
    this.rootFolders = const [],
    this.virtualFolders = const [],
    this.savedViews = const [],
    this.globalTags = const [],
    this.preferences = const {},
  });

  static const schemaVersion = 1;
  final String snapshotId;
  final int generation;
  final int createdAtEpochMs;
  final List<AureonMetadataFolder> rootFolders;
  final List<AureonVirtualFolder> virtualFolders;
  final List<AureonSavedView> savedViews;
  final List<String> globalTags;
  /// Only user organization/preferences. Never put tokens, keys or OS paths here.
  final Map<String, Object?> preferences;

  Map<String, Object?> toJson() => {
    'format': 'AUREON-METADATA-SNAPSHOT',
    'schemaVersion': schemaVersion,
    'snapshotId': snapshotId,
    'generation': generation,
    'createdAtEpochMs': createdAtEpochMs,
    'rootFolders': rootFolders.map((folder) => folder.toJson()).toList(),
    'virtualFolders': virtualFolders.map((folder) => folder.toJson()).toList(),
    'savedViews': savedViews.map((view) => view.toJson()).toList(),
    'globalTags': globalTags,
    'preferences': preferences,
  };

  factory AureonMetadataSnapshot.fromJson(Map<String, Object?> json) {
    if (json['format'] != 'AUREON-METADATA-SNAPSHOT' || json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported AUREON metadata snapshot version.');
    }
    final roots = json['rootFolders'];
    final virtuals = json['virtualFolders'];
    final views = json['savedViews'];
    final tags = json['globalTags'];
    final preferences = json['preferences'];
    if (roots is! List || virtuals is! List || views is! List || tags is! List ||
        tags.any((tag) => tag is! String) || preferences is! Map) {
      throw const FormatException('Invalid AUREON metadata snapshot.');
    }
    final snapshot = AureonMetadataSnapshot(
      snapshotId: _requiredString(json, 'snapshotId'),
      generation: _requiredInt(json, 'generation'),
      createdAtEpochMs: _requiredInt(json, 'createdAtEpochMs'),
      rootFolders: roots.map((value) {
        if (value is! Map) throw const FormatException('Invalid root folder.');
        return AureonMetadataFolder.fromJson(value.cast<String, Object?>());
      }).toList(),
      virtualFolders: virtuals.map((value) {
        if (value is! Map) throw const FormatException('Invalid virtual folder.');
        return AureonVirtualFolder.fromJson(value.cast<String, Object?>());
      }).toList(),
      savedViews: views.map((value) {
        if (value is! Map) throw const FormatException('Invalid saved view.');
        return AureonSavedView.fromJson(value.cast<String, Object?>());
      }).toList(),
      globalTags: tags.cast<String>(),
      preferences: preferences.cast<String, Object?>(),
    );
    _validateUniqueFolderIds(snapshot.rootFolders);
    return snapshot;
  }
}

/// Encrypted portable archive, independent of credential-vault keys and
/// Manual Recovery Keys. The user-selected backup passphrase is the only key.
class AureonMetadataBackupCodec {
  static const _memoryKiB = 64 * 1024;
  static const _iterations = 3;
  static const _parallelism = 2;
  static const _maxArchiveBytes = 128 * 1024 * 1024;
  static final _random = Random.secure();
  static final _cipher = AesGcm.with256bits();

  Future<List<int>> encrypt(AureonMetadataSnapshot snapshot, String passphrase) async {
    _validatePassphrase(passphrase);
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final header = <String, Object?>{
      'format': 'AUREON-ENCRYPTED-METADATA-BACKUP',
      'formatVersion': 1,
      'schemaVersion': AureonMetadataSnapshot.schemaVersion,
      'snapshotId': snapshot.snapshotId,
      'generation': snapshot.generation,
      'createdAtEpochMs': snapshot.createdAtEpochMs,
      'kdf': 'Argon2id',
      'memoryKiB': _memoryKiB,
      'iterations': _iterations,
      'parallelism': _parallelism,
      'hashLength': 32,
      'cipher': 'AES-256-GCM',
      'salt': base64Url.encode(salt),
      'nonce': base64Url.encode(nonce),
    };
    final key = await _derive(passphrase, salt);
    final aad = utf8.encode(jsonEncode(header));
    final box = await _cipher.encrypt(utf8.encode(jsonEncode(snapshot.toJson())),
      secretKey: key, nonce: nonce, aad: aad);
    final archive = utf8.encode(jsonEncode({
      'header': header,
      'cipherText': base64Url.encode(box.cipherText),
      'mac': base64Url.encode(box.mac.bytes),
    }));
    if (archive.length > _maxArchiveBytes) throw StateError('Metadata backup exceeds the supported size.');
    return archive;
  }

  Future<AureonMetadataSnapshot> decrypt(List<int> bytes, String passphrase) async {
    _validatePassphrase(passphrase);
    if (bytes.isEmpty || bytes.length > _maxArchiveBytes) {
      throw const FormatException('Metadata backup size is invalid.');
    }
    final rootValue = jsonDecode(utf8.decode(bytes));
    if (rootValue is! Map) throw const FormatException('Invalid metadata backup archive.');
    final root = rootValue.cast<String, Object?>();
    final rawHeader = root['header'];
    if (rawHeader is! Map) throw const FormatException('Metadata backup header is missing.');
    final header = rawHeader.cast<String, Object?>();
    if (header['format'] != 'AUREON-ENCRYPTED-METADATA-BACKUP' ||
        header['formatVersion'] != 1 ||
        header['schemaVersion'] != AureonMetadataSnapshot.schemaVersion ||
        header['kdf'] != 'Argon2id' ||
        header['cipher'] != 'AES-256-GCM' ||
        header['memoryKiB'] != _memoryKiB ||
        header['iterations'] != _iterations ||
        header['parallelism'] != _parallelism ||
        header['hashLength'] != 32) {
      throw const FormatException('Unsupported or unsafe metadata backup parameters.');
    }
    final salt = _decode(_requiredString(header, 'salt'), 16);
    final nonce = _decode(_requiredString(header, 'nonce'), 12);
    final cipherText = _decode(_requiredString(root, 'cipherText'));
    final mac = _decode(_requiredString(root, 'mac'), 16);
    final key = await _derive(passphrase, salt);
    final clear = await _cipher.decrypt(SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: key, aad: utf8.encode(jsonEncode(header)));
    final payloadValue = jsonDecode(utf8.decode(clear));
    if (payloadValue is! Map) throw const FormatException('Invalid decrypted metadata payload.');
    final snapshot = AureonMetadataSnapshot.fromJson(payloadValue.cast<String, Object?>());
    if (snapshot.snapshotId != header['snapshotId'] ||
        snapshot.generation != header['generation'] ||
        snapshot.createdAtEpochMs != header['createdAtEpochMs']) {
      throw const FormatException('Metadata archive header and payload do not match.');
    }
    return snapshot;
  }

  Future<SecretKey> _derive(String passphrase, List<int> salt) => Argon2id(
    memory: _memoryKiB, iterations: _iterations, parallelism: _parallelism, hashLength: 32,
  ).deriveKeyFromPassword(password: passphrase, nonce: salt);

  void _validatePassphrase(String passphrase) {
    if (passphrase.trim().length < 14 || passphrase.length > 1024) {
      throw ArgumentError('Metadata backup passphrase must contain at least 14 characters.');
    }
  }

  List<int> _randomBytes(int count) => List<int>.generate(count, (_) => _random.nextInt(256));
}

class MetadataRestoreResult {
  const MetadataRestoreResult({
    required this.snapshot,
    required this.conflicts,
    required this.pendingProviderReferences,
  });
  final AureonMetadataSnapshot snapshot;
  final List<String> conflicts;
  final int pendingProviderReferences;
}

/// Restore preserves the backup's exact AUREON ordering/tree. Current-only
/// folders are retained; provider files stay pending until re-index confirms IDs.
class AureonMetadataRestorePlanner {
  MetadataRestoreResult merge({
    required AureonMetadataSnapshot current,
    required AureonMetadataSnapshot backup,
    Map<String, ProviderFileReference>? liveProviderFiles,
  }) {
    final conflicts = <String>[];
    final mergedRoots = _mergeFolders(current.rootFolders, backup.rootFolders, conflicts, liveProviderFiles);
    final virtuals = _mergeVirtualFolders(current.virtualFolders, backup.virtualFolders, conflicts,
      liveProviderFiles);
    final views = _mergeViews(current.savedViews, backup.savedViews, conflicts);
    final merged = AureonMetadataSnapshot(
      snapshotId: backup.snapshotId,
      generation: max(current.generation, backup.generation) + 1,
      createdAtEpochMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      rootFolders: mergedRoots,
      virtualFolders: virtuals,
      savedViews: views,
      globalTags: {...current.globalTags, ...backup.globalTags}.toList(),
      preferences: {...current.preferences, ...backup.preferences},
    );
    return MetadataRestoreResult(
      snapshot: merged,
      conflicts: conflicts,
      pendingProviderReferences: _countPending(merged.rootFolders) +
          merged.virtualFolders.fold<int>(0, (sum, folder) =>
            sum + folder.items.where((item) => !item.isReconciled).length),
    );
  }

  List<AureonMetadataFolder> _mergeFolders(
    List<AureonMetadataFolder> current,
    List<AureonMetadataFolder> backup,
    List<String> conflicts,
    Map<String, ProviderFileReference>? liveProviderFiles,
  ) {
    final currentById = {for (final folder in current) folder.id: folder};
    final result = <AureonMetadataFolder>[];
    for (final saved in backup) {
      final existing = currentById.remove(saved.id);
      if (existing != null && existing.name != saved.name) {
        conflicts.add('Folder "${saved.name}" differs from the current folder with the same ID.');
      }
      final nested = _mergeFolders(existing?.folders ?? const [], saved.folders, conflicts, liveProviderFiles);
      final files = _mergeFileEntries(existing?.files ?? const [], saved.files, conflicts, liveProviderFiles);
      result.add(AureonMetadataFolder(
        id: saved.id, name: saved.name, order: saved.order,
        folders: nested, files: files,
        tags: {...?existing?.tags, ...saved.tags}.toList(),
        colorArgb: saved.colorArgb ?? existing?.colorArgb,
      ));
    }
    result.addAll(currentById.values.map((folder) => folder));
    result.sort((a, b) => a.order.compareTo(b.order));
    return result;
  }

  List<AureonMetadataFileEntry> _mergeFileEntries(
    List<AureonMetadataFileEntry> current,
    List<AureonMetadataFileEntry> backup,
    List<String> conflicts,
    Map<String, ProviderFileReference>? liveProviderFiles,
  ) {
    final currentByKey = {for (final file in current) file.reference.stableKey: file};
    final result = <AureonMetadataFileEntry>[];
    for (final saved in backup) {
      final key = saved.reference.stableKey;
      final liveReference = liveProviderFiles?[key];
      if (liveProviderFiles != null && liveReference == null) {
        conflicts.add('Provider object is no longer present; skipped: ${saved.reference.name}.');
        currentByKey.remove(key);
        continue;
      }
      final existing = currentByKey.remove(key);
      if (existing != null && existing.order != saved.order) {
        conflicts.add('File placement changed: ${saved.reference.name}.');
      }
      result.add(AureonMetadataFileEntry(
        reference: liveReference ?? saved.reference,
        order: saved.order,
        tags: {...?existing?.tags, ...saved.tags}.toList(),
        favorite: saved.favorite || (existing?.favorite ?? false),
        customLabel: saved.customLabel ?? existing?.customLabel,
        pendingProviderReconciliation: liveReference == null,
      ));
    }
    result.addAll(currentByKey.values.where((file) => liveProviderFiles == null || liveProviderFiles.containsKey(file.reference.stableKey)));
    result.sort((a, b) => a.order.compareTo(b.order));
    return result;
  }

  List<AureonVirtualFolder> _mergeVirtualFolders(
    List<AureonVirtualFolder> current,
    List<AureonVirtualFolder> backup,
    List<String> conflicts,
    Map<String, ProviderFileReference>? liveProviderFiles,
  ) {
    final currentById = {for (final folder in current) folder.id: folder};
    final result = <AureonVirtualFolder>[];
    for (final saved in backup) {
      final existing = currentById.remove(saved.id);
      if (existing != null && existing.name != saved.name) {
        conflicts.add('Virtual folder "${saved.name}" differs from current metadata.');
      }
      final items = <ProviderFileReference>[];
      final byKey = <String, ProviderFileReference>{};
      for (final item in [...?existing?.items, ...saved.items]) {
        final live = liveProviderFiles?[item.stableKey];
        if (liveProviderFiles != null && live == null) continue;
        byKey[item.stableKey] = live ?? item;
      }
      items.addAll(byKey.values);
      result.add(AureonVirtualFolder(
        id: saved.id,
        name: saved.name,
        createdAtEpochMs: saved.createdAtEpochMs,
        items: items.map((item) => ProviderFileReference(
          provider: item.provider,
          providerAccountId: item.providerAccountId,
          accountLabel: item.accountLabel,
          providerItemId: item.providerItemId,
          name: item.name,
          providerParentId: item.providerParentId,
          mimeType: item.mimeType,
          sizeBytes: item.sizeBytes,
          webUrl: item.webUrl,
          isReconciled: liveProviderFiles?.containsKey(item.stableKey) ?? false,
        )).toList(),
      ));
    }
    result.addAll(currentById.values);
    return result;
  }

  List<AureonSavedView> _mergeViews(
    List<AureonSavedView> current,
    List<AureonSavedView> backup,
    List<String> conflicts,
  ) {
    final map = {for (final view in current) view.id: view};
    for (final view in backup) {
      if (map.containsKey(view.id) && map[view.id]!.name != view.name) {
        conflicts.add('Saved view "${view.name}" differs from current metadata.');
      }
      map[view.id] = view;
    }
    return map.values.toList();
  }

  int _countPending(List<AureonMetadataFolder> folders) =>
      folders.fold<int>(0, (sum, folder) =>
        sum + folder.files.length + _countPending(folder.folders));
}

void _validateUniqueFolderIds(List<AureonMetadataFolder> roots) {
  final ids = <String>{};
  void visit(AureonMetadataFolder folder) {
    if (!ids.add(folder.id)) throw const FormatException('Duplicate logical folder ID in metadata snapshot.');
    for (final child in folder.folders) { visit(child); }
  }
  for (final root in roots) { visit(root); }
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

List<int> _decode(String value, [int? length]) {
  final bytes = base64Url.decode(base64Url.normalize(value));
  if (length != null && bytes.length != length) throw const FormatException('Invalid encoded field length.');
  return bytes;
}
