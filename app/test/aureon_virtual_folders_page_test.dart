import 'dart:io';

import 'package:aureon/src/backup/aureon_metadata_store.dart';
import 'package:aureon/src/virtual_folders/aureon_virtual_folder_store.dart';
import 'package:aureon/src/virtual_folders/aureon_virtual_folders_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AureonVirtualFolderStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('aureon-virtual-page-test-');
    store = AureonVirtualFolderStore(
      metadataStore: AureonMetadataStore(rootDirectory: root, keyStore: _FakeKeyStore()),
    );
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('Virtual folders page renders its safe prototype state', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async { await store.load(); });
    await tester.pumpWidget(MaterialApp(home: AureonVirtualFoldersPage(store: store)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Virtual folders'), findsOneWidget);
    expect(find.textContaining('Connect Google Drive accounts to browse existing files'), findsOneWidget);
    expect(find.text('Google Drive accounts'), findsOneWidget);
    expect(find.text('New folder'), findsOneWidget);
  });
}

class _FakeKeyStore implements AureonMetadataKeyStore {
  String? value;
  @override
  Future<String?> readKey() async => value;
  @override
  Future<void> writeKey(String next) async { value = next; }
}
