import 'package:aureon_local_files/aureon_local_files.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('aureon/local_files');
  final files = AureonLocalFiles(channel: channel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('folder picker maps a native root response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickRoot');
      return {'rootId': 'content://tree/root', 'rootDocumentId': 'document-root', 'displayName': 'Documents'};
    });
    final root = await files.pickRoot();
    expect(root?.rootId, 'content://tree/root');
    expect(root?.displayName, 'Documents');
  });

  test('directory listing maps entries and passes parent identity', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'listChildren');
      expect(call.arguments, {
        'rootId': 'content://tree/root',
        'parentId': 'document-root',
      });
      return [
        {'id': 'document-folder', 'name': 'Projects', 'isDirectory': true},
        {'id': 'document-file', 'name': 'notes.txt', 'isDirectory': false,
         'sizeBytes': 120, 'modifiedEpochMs': 1700000000000},
      ];
    });
    final entries = await files.listChildren(
      root: const AureonLocalRoot(rootId: 'content://tree/root', displayName: 'Docs', rootDocumentId: 'document-root'),
      parentId: 'document-root',
    );
    expect(entries, hasLength(2));
    expect(entries.first.isDirectory, isTrue);
    expect(entries.last.sizeBytes, 120);
  });

  test('copy file sends source, parent and target name', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'copyFile');
      expect(call.arguments, {
        'rootId': 'root-uri', 'sourceId': 'source-id',
        'parentId': 'parent-id', 'targetName': 'copy.txt',
      });
      return 'copied-document-id';
    });
    const root = AureonLocalRoot(rootId: 'root-uri', displayName: 'Docs', rootDocumentId: 'root-doc');
    expect(await files.copyFile(root: root, sourceId: 'source-id',
      parentId: 'parent-id', targetName: 'copy.txt'), 'copied-document-id');
  });

  test('move sends selected source and destination parent identities', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'moveEntry');
      expect(call.arguments, {
        'rootId': 'root-uri', 'entryId': 'child-file',
        'sourceParentId': 'nested-folder', 'targetParentId': 'root-doc',
      });
      return 'moved-document-id';
    });
    const root = AureonLocalRoot(rootId: 'root-uri', displayName: 'Docs', rootDocumentId: 'root-doc');
    expect(await files.moveEntry(root: root, entryId: 'child-file',
      sourceParentId: 'nested-folder', targetParentId: 'root-doc'), 'moved-document-id');
  });

  test('move to trash sends item and parent identities', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'moveToTrash');
      expect(call.arguments, {'rootId': 'root-uri', 'entryId': 'file-id', 'parentId': 'folder-id'});
      return {'id': 'trashed-id', 'name': 'notes.txt', 'trashFolderId': 'trash-id',
        'originalParentId': 'folder-id', 'trashedAt': 1700000000000};
    });
    const root = AureonLocalRoot(rootId: 'root-uri', displayName: 'Docs', rootDocumentId: 'root-doc');
    final moved = await files.moveToTrash(root: root, entryId: 'file-id', parentId: 'folder-id');
    expect(moved.id, 'trashed-id');
    expect(moved.trashFolderId, 'trash-id');
    expect(moved.originalParentId, 'folder-id');
  });

  test('permanent Trash deletion sends scoped identities', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'deleteTrashEntry');
      expect(call.arguments, {'rootId': 'root-uri', 'entryId': 'trash-item', 'trashFolderId': 'trash-folder'});
      return true;
    });
    const root = AureonLocalRoot(rootId: 'root-uri', displayName: 'Docs', rootDocumentId: 'root-doc');
    await files.deleteTrashEntry(root: root, entryId: 'trash-item', trashFolderId: 'trash-folder');
  });

  test('rename and create folder send scoped identities', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'renameEntry' ? 'renamed-id' : 'new-folder-id';
    });
    const root = AureonLocalRoot(rootId: 'root-uri', displayName: 'Docs', rootDocumentId: 'root-doc');
    expect(await files.renameEntry(root: root, entryId: 'old-id', newName: 'new.txt'), 'renamed-id');
    expect(await files.createFolder(root: root, parentId: 'parent-id', name: 'New folder'), 'new-folder-id');
    expect(calls[0].method, 'renameEntry');
    expect(calls[0].arguments, {'rootId': 'root-uri', 'entryId': 'old-id', 'newName': 'new.txt'});
    expect(calls[1].method, 'createFolder');
    expect(calls[1].arguments, {'rootId': 'root-uri', 'parentId': 'parent-id', 'name': 'New folder'});
  });

  test('openFile sends the selected root and file identity', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'openFile');
      expect(call.arguments, {'rootId': 'root-uri', 'fileId': 'child-document'});
      return true;
    });
    await files.openFile(root: const AureonLocalRoot(rootId: 'root-uri', displayName: 'Docs', rootDocumentId: 'root-doc'), fileId: 'child-document');
  });

  test('malformed native entry is rejected', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => [
      {'id': 'x', 'name': 'broken'},
    ]);
    expect(
      () => files.listChildren(
        root: const AureonLocalRoot(rootId: 'root', displayName: 'Root', rootDocumentId: 'root'),
        parentId: 'root',
      ),
      throwsFormatException,
    );
  });
}
