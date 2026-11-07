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
      return {'rootId': 'content://tree/root', 'displayName': 'Documents'};
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
      root: const AureonLocalRoot(rootId: 'content://tree/root', displayName: 'Docs'),
      parentId: 'document-root',
    );
    expect(entries, hasLength(2));
    expect(entries.first.isDirectory, isTrue);
    expect(entries.last.sizeBytes, 120);
  });

  test('malformed native entry is rejected', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => [
      {'id': 'x', 'name': 'broken'},
    ]);
    expect(
      () => files.listChildren(
        root: const AureonLocalRoot(rootId: 'root', displayName: 'Root'),
        parentId: 'root',
      ),
      throwsFormatException,
    );
  });
}
