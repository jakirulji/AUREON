import 'package:flutter/services.dart';

class AureonLocalRoot {
  const AureonLocalRoot({
    required this.rootId,
    required this.displayName,
    required this.rootDocumentId,
  });

  final String rootId;
  final String displayName;
  final String rootDocumentId;

  factory AureonLocalRoot.fromMap(Map<Object?, Object?> map) {
    final id = map['rootId'];
    final name = map['displayName'];
    final documentId = map['rootDocumentId'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty || documentId is! String || documentId.isEmpty) {
      throw const FormatException('Native folder picker returned an invalid root.');
    }
    return AureonLocalRoot(rootId: id, displayName: name, rootDocumentId: documentId);
  }
}

class AureonTrashMoveResult {
  const AureonTrashMoveResult({required this.id, required this.name, required this.trashFolderId,
    required this.originalParentId, required this.trashedAt, required this.mode});
  final String id;
  final String name;
  final String trashFolderId;
  final String originalParentId;
  final int trashedAt;
  final String mode;
}

class AureonLocalEntry {
  const AureonLocalEntry({
    required this.id,
    required this.name,
    required this.isDirectory,
    required this.isHidden,
    this.sizeBytes,
    this.modifiedEpochMs,
    this.isSystemTrash = false,
  });

  final String id;
  final String name;
  final bool isDirectory;
  final bool isHidden;
  final int? sizeBytes;
  final int? modifiedEpochMs;
  final bool isSystemTrash;

  factory AureonLocalEntry.fromMap(Map<Object?, Object?> map) {
    final id = map['id'];
    final name = map['name'];
    final directory = map['isDirectory'];
    if (id is! String || name is! String || directory is! bool) {
      throw const FormatException('Native file entry is missing required fields.');
    }
    return AureonLocalEntry(
      id: id,
      name: name,
      isDirectory: directory,
      isHidden: map['isHidden'] == true,
      sizeBytes: map['sizeBytes'] is int ? map['sizeBytes'] as int : null,
      modifiedEpochMs: map['modifiedEpochMs'] is int
          ? map['modifiedEpochMs'] as int
          : null,
      isSystemTrash: map['isSystemTrash'] == true,
    );
  }
}

/// Read-only folder picker and directory enumerator.
/// Android root IDs are persisted SAF tree URIs; child IDs are document IDs.
/// Windows root and child IDs are filesystem paths.
class AureonLocalFiles {
  AureonLocalFiles({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('aureon/local_files');

  final MethodChannel _channel;

  Future<AureonLocalRoot?> pickRoot() async {
    final value = await _channel.invokeMethod<Object?>('pickRoot');
    if (value == null) return null;
    if (value is! Map) {
      throw const FormatException('Native folder picker returned an invalid response.');
    }
    return AureonLocalRoot.fromMap(value);
  }

  Future<String> copyFile({required AureonLocalRoot root, required String sourceId, required String parentId, required String targetName}) async {
    final value = await _channel.invokeMethod<Object?>('copyFile', <String, Object?>{
      'rootId': root.rootId, 'sourceId': sourceId, 'parentId': parentId, 'targetName': targetName,
    });
    if (value is! String || value.isEmpty) throw const FormatException('Native copy returned an invalid identity.');
    return value;
  }

  Future<String> moveEntry({required AureonLocalRoot root, required String entryId, required String sourceParentId, required String targetParentId}) async {
    final value = await _channel.invokeMethod<Object?>('moveEntry', <String, Object?>{
      'rootId': root.rootId, 'entryId': entryId,
      'sourceParentId': sourceParentId, 'targetParentId': targetParentId,
    });
    if (value is! String || value.isEmpty) throw const FormatException('Native move returned an invalid identity.');
    return value;
  }

  Future<AureonTrashMoveResult> moveToTrash({required AureonLocalRoot root, required String entryId, required String parentId}) async {
    final value = await _channel.invokeMethod<Object?>('moveToTrash', <String, Object?>{
      'rootId': root.rootId, 'entryId': entryId, 'parentId': parentId,
    });
    if (value == true) {
      return AureonTrashMoveResult(id: entryId, name: '', trashFolderId: '__windows__',
        originalParentId: parentId, trashedAt: DateTime.now().millisecondsSinceEpoch, mode: 'windows');
    }
    if (value is! Map) throw const FormatException('Native Trash returned an invalid response.');
    final id = value['id'];
    final name = value['name'];
    final trashFolderId = value['trashFolderId'];
    final originalParentId = value['originalParentId'];
    final trashedAt = value['trashedAt'];
    final mode = value['mode'] is String ? value['mode'] as String : 'managed';
    if (id is! String || name is! String || trashFolderId is! String ||
        originalParentId is! String || trashedAt is! int) {
      throw const FormatException('Native Trash returned incomplete restore information.');
    }
    return AureonTrashMoveResult(id: id, name: name, trashFolderId: trashFolderId,
      originalParentId: originalParentId, trashedAt: trashedAt, mode: mode);
  }

  Future<List<AureonLocalEntry>> listSystemTrash({required AureonLocalRoot root}) async {
    final value = await _channel.invokeMethod<Object?>('listSystemTrash', <String, Object?>{'rootId': root.rootId});
    if (value is! List) throw const FormatException('Native Trash listing returned an invalid response.');
    return value.map((row) {
      if (row is! Map) throw const FormatException('Native Trash contains an invalid entry.');
      return AureonLocalEntry.fromMap(row);
    }).toList(growable: false);
  }

  Future<void> restoreSystemTrashEntry({required AureonLocalRoot root, required String entryId}) async {
    await _channel.invokeMethod<void>('restoreSystemTrashEntry', <String, Object?>{
      'rootId': root.rootId, 'entryId': entryId,
    });
  }

  Future<void> deleteSystemTrashEntry({required AureonLocalRoot root, required String entryId}) async {
    await _channel.invokeMethod<void>('deleteSystemTrashEntry', <String, Object?>{
      'rootId': root.rootId, 'entryId': entryId,
    });
  }

  Future<void> deleteTrashEntry({required AureonLocalRoot root, required String entryId, required String trashFolderId}) async {
    await _channel.invokeMethod<void>('deleteTrashEntry', <String, Object?>{
      'rootId': root.rootId, 'entryId': entryId, 'trashFolderId': trashFolderId,
    });
  }

  Future<String> renameEntry({required AureonLocalRoot root, required String entryId, required String newName}) async {
    final value = await _channel.invokeMethod<Object?>('renameEntry', <String, Object?>{
      'rootId': root.rootId, 'entryId': entryId, 'newName': newName,
    });
    if (value is! String || value.isEmpty) throw const FormatException('Native rename returned an invalid identity.');
    return value;
  }

  Future<String> createFolder({required AureonLocalRoot root, required String parentId, required String name}) async {
    final value = await _channel.invokeMethod<Object?>('createFolder', <String, Object?>{
      'rootId': root.rootId, 'parentId': parentId, 'name': name,
    });
    if (value is! String || value.isEmpty) throw const FormatException('Native folder creation returned an invalid identity.');
    return value;
  }

  Future<void> openFile({required AureonLocalRoot root, required String fileId}) async {
    await _channel.invokeMethod<void>('openFile', <String, Object?>{'rootId': root.rootId, 'fileId': fileId});
  }

  Future<List<AureonLocalEntry>> listChildren({
    required AureonLocalRoot root,
    required String parentId,
  }) async {
    final value = await _channel.invokeMethod<Object?>(
      'listChildren',
      <String, Object?>{'rootId': root.rootId, 'parentId': parentId},
    );
    if (value is! List) {
      throw const FormatException('Native directory listing returned an invalid response.');
    }
    return value.map((entry) {
      if (entry is! Map) {
        throw const FormatException('Native directory listing contains an invalid entry.');
      }
      return AureonLocalEntry.fromMap(entry);
    }).toList(growable: false);
  }
}
