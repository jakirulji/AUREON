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

class AureonLocalEntry {
  const AureonLocalEntry({
    required this.id,
    required this.name,
    required this.isDirectory,
    required this.isHidden,
    this.sizeBytes,
    this.modifiedEpochMs,
  });

  final String id;
  final String name;
  final bool isDirectory;
  final bool isHidden;
  final int? sizeBytes;
  final int? modifiedEpochMs;

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
