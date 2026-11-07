import 'dart:io';

import 'package:aureon/src/backup/aureon_metadata_store.dart';
import 'package:aureon/src/virtual_folders/aureon_virtual_folder_store.dart';
import 'package:aureon/src/virtual_folders/aureon_virtual_folders_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AureonVirtualFolderStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('aureon-virtual-page-test-');
    store = AureonVirtualFolderStore(
      metadataStore: AureonMetadataStore(rootDirectory: root, keyStore: _FakeKeyStore()),
    );
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('Virtual folders page creates a persistent folder', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: AureonVirtualFoldersPage(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Virtual folders'), findsOneWidget);
    expect(find.textContaining('live cloud account browsing'), findsOneWidget);

    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Research');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Research'), findsOneWidget);
  });
}

class _FakeKeyStore implements AureonMetadataKeyStore {
  String? value;
  @override
  Future<String?> readKey() async => value;
  @override
  Future<void> writeKey(String next) async { value = next; }
}
