import 'dart:io';

import 'package:aureon/src/backup/aureon_metadata_store.dart';
import 'package:aureon_contracts/aureon_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

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
  late _FakeKeyStore keyStore;
  late AureonMetadataStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('aureon-metadata-test-');
    keyStore = _FakeKeyStore();
    store = AureonMetadataStore(rootDirectory: root, keyStore: keyStore);
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('nested AUREON folders persist with stable order and provider references', () async {
    await store.createFolder('Projects');
    var snapshot = await store.load();
    final projects = snapshot.rootFolders.single;
    await store.createFolder('Design', parentId: projects.id);
    snapshot = await store.load();
    final design = snapshot.rootFolders.single.folders.single;

    final reference = ProviderFileReference(
      provider: ProviderKind.googleDrive,
      providerAccountId: 'drive-account',
      accountLabel: 'Work',
      providerItemId: 'provider-item',
      name: 'mockup.fig',
      providerParentId: 'native-folder-id',
    );
    await store.addFileToFolder(design.id, reference);
    snapshot = await AureonMetadataStore(rootDirectory: root, keyStore: keyStore).load();

    expect(snapshot.rootFolders.single.name, 'Projects');
    expect(snapshot.rootFolders.single.folders.single.name, 'Design');
    expect(snapshot.rootFolders.single.folders.single.files.single.reference.stableKey, reference.stableKey);
    expect(snapshot.rootFolders.single.folders.single.files.single.order, 0);
  });

  test('folder move rejects cycles and delete only removes AUREON metadata', () async {
    await store.createFolder('Root');
    var snapshot = await store.load();
    final root = snapshot.rootFolders.single;
    await store.createFolder('Child', parentId: root.id);
    snapshot = await store.load();
    final child = snapshot.rootFolders.single.folders.single;

    await expectLater(store.moveFolder(root.id, newParentId: child.id), throwsStateError);
    await store.moveFolder(child.id);
    snapshot = await store.load();
    expect(snapshot.rootFolders.map((folder) => folder.name), ['Root', 'Child']);

    await store.deleteFolder(child.id);
    snapshot = await store.load();
    expect(snapshot.rootFolders.map((folder) => folder.name), ['Root']);
  });

  test('duplicate sibling names are rejected but names may repeat in other branches', () async {
    final store = AureonMetadataStore();
    await store.createFolder('Projects');
    var snapshot = await store.load();
    final projects = snapshot.rootFolders.single;
    await store.createFolder('Design', parentId: projects.id);
    await expectLater(store.createFolder('design', parentId: projects.id), throwsStateError);
    await store.createFolder('Archive');
    snapshot = await store.load();
    final archive = snapshot.rootFolders.last;
    await store.createFolder('Design', parentId: archive.id);
    snapshot = await store.load();
    expect(snapshot.rootFolders.last.folders.single.name, 'Design');
  });
}
