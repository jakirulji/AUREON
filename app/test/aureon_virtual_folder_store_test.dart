import 'dart:io';

import 'package:aureon/src/backup/aureon_metadata_store.dart';
import 'package:aureon/src/virtual_folders/aureon_virtual_folder_store.dart';
import 'package:aureon_contracts/aureon_contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeKeyStore implements AureonMetadataKeyStore {
  String? value;
  @override
  Future<String?> readKey() async => value;
  @override
  Future<void> writeKey(String next) async { value = next; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AureonVirtualFolderStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('aureon-virtual-folder-test-');
    store = AureonVirtualFolderStore(
      metadataStore: AureonMetadataStore(rootDirectory: root, keyStore: _FakeKeyStore()),
    );
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  ProviderFileReference file(String account, String item, String label) => ProviderFileReference(
    provider: ProviderKind.googleDrive,
    providerAccountId: account,
    accountLabel: label,
    providerItemId: item,
    name: 'shared-report.pdf',
    providerParentId: 'original-provider-folder',
  );

  test('one virtual folder can reference files from multiple accounts', () async {
    final folder = await store.create('Projects');
    await store.addItem(folder.id, file('drive-account-a', 'file-a', 'Personal'));
    await store.addItem(folder.id, file('drive-account-b', 'file-b', 'Work'));

    final restored = (await store.load()).single;
    expect(restored.items, hasLength(2));
    expect(restored.items.map((item) => item.providerAccountId).toSet(),
      {'drive-account-a', 'drive-account-b'});
    expect(restored.items.map((item) => item.providerParentId).toSet(),
      {'original-provider-folder'});
  });

  test('membership add is idempotent and remove only changes AUREON metadata', () async {
    final folder = await store.create('Archive');
    final reference = file('drive-a', 'item-1', 'Drive A');
    await store.addItem(folder.id, reference);
    await store.addItem(folder.id, reference);
    expect((await store.load()).single.items, hasLength(1));

    await store.removeItem(folder.id, reference.stableKey);
    expect((await store.load()).single.items, isEmpty);
    // No provider API exists in this store: original provider identity is untouched.
    expect(reference.providerItemId, 'item-1');
    expect(reference.providerParentId, 'original-provider-folder');
  });

  test('same provider item in different accounts is not conflated', () async {
    final folder = await store.create('Mixed');
    await store.addItem(folder.id, file('account-a', 'same-item-id', 'A'));
    await store.addItem(folder.id, file('account-b', 'same-item-id', 'B'));
    expect((await store.load()).single.items, hasLength(2));
  });

  test('duplicate folder names are rejected case-insensitively', () async {
    await store.create('Projects');
    await expectLater(store.create('projects'), throwsStateError);
  });
}
