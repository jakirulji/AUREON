import 'dart:io';

import 'package:aureon/src/backup/aureon_metadata_backup.dart';
import 'package:aureon/src/backup/aureon_metadata_store.dart';
import 'package:aureon_contracts/aureon_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryMetadataKeyStore implements AureonMetadataKeyStore {
  String? value;
  @override
  Future<String?> readKey() async => value;
  @override
  Future<void> writeKey(String next) async { value = next; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('encrypted backup restores exact AUREON organization on a fresh device store', () async {
    final sourceDirectory = await Directory.systemTemp.createTemp('aureon-source-');
    final targetDirectory = await Directory.systemTemp.createTemp('aureon-target-');
    final sourceKeyStore = _MemoryMetadataKeyStore();
    final targetKeyStore = _MemoryMetadataKeyStore();
    addTearDown(() async {
      if (await sourceDirectory.exists()) await sourceDirectory.delete(recursive: true);
      if (await targetDirectory.exists()) await targetDirectory.delete(recursive: true);
    });

    final first = ProviderFileReference(
      provider: ProviderKind.googleDrive,
      providerAccountId: 'drive-account-a',
      accountLabel: 'Personal Drive',
      providerItemId: 'provider-file-001',
      name: 'first.pdf',
      providerParentId: 'native-parent-01',
    );
    final second = ProviderFileReference(
      provider: ProviderKind.googleDrive,
      providerAccountId: 'drive-account-b',
      accountLabel: 'Work Drive',
      providerItemId: 'provider-file-002',
      name: 'second.xlsx',
      providerParentId: 'native-parent-02',
    );
    final source = AureonMetadataSnapshot(
      snapshotId: 'disaster-recovery-fixture',
      generation: 12,
      createdAtEpochMs: 123456789,
      rootFolders: [
        AureonMetadataFolder(
          id: 'folder-projects',
          name: 'Projects',
          order: 0,
          tags: const ['work'],
          folders: [
            AureonMetadataFolder(
              id: 'folder-design',
              name: 'Design',
              order: 3,
              files: [
                AureonMetadataFileEntry(
                  reference: first,
                  order: 5,
                  tags: const ['priority', 'client'],
                  favorite: true,
                  customLabel: 'Approved artwork',
                ),
              ],
            ),
            AureonMetadataFolder(
              id: 'folder-archive',
              name: 'Archive',
              order: 8,
            ),
          ],
        ),
        AureonMetadataFolder(id: 'folder-personal', name: 'Personal', order: 4),
      ],
      virtualFolders: [
        AureonVirtualFolder(
          id: 'virtual-mixed',
          name: 'Cross-account collection',
          createdAtEpochMs: 1000,
          items: [first, second],
        ),
      ],
      savedViews: const [
        AureonSavedView(
          id: 'view-large',
          name: 'Large files',
          query: 'pdf',
          sortField: 'size',
          descending: true,
          filterTags: ['priority'],
        ),
      ],
      globalTags: const ['work', 'priority', 'client'],
      preferences: const {
        'sort': 'custom',
        'showHidden': false,
        'viewMode': 'list',
      },
    );

    final archive = await AureonMetadataBackupCodec().encrypt(
      source,
      'independent-metadata-recovery-passphrase',
    );

    // A new device has neither the old local catalog nor its local encryption key.
    final restoredSnapshot = await AureonMetadataBackupCodec().decrypt(
      archive,
      'independent-metadata-recovery-passphrase',
    );
    final planned = AureonMetadataRestorePlanner().merge(
      current: AureonMetadataSnapshot(
        snapshotId: 'new-device-empty',
        generation: 0,
        createdAtEpochMs: 1,
      ),
      backup: restoredSnapshot,
    );

    final targetStore = AureonMetadataStore(
      rootDirectory: targetDirectory,
      keyStore: targetKeyStore,
    );
    await targetStore.save(planned.snapshot);

    // Reopen with a new store instance to verify durable encrypted persistence.
    final reopened = await AureonMetadataStore(
      rootDirectory: targetDirectory,
      keyStore: targetKeyStore,
    ).load();

    expect(reopened.rootFolders.map((folder) => folder.id), [
      'folder-projects',
      'folder-personal',
    ]);
    final projects = reopened.rootFolders.first;
    expect(projects.name, 'Projects');
    expect(projects.order, 0);
    expect(projects.tags, ['work']);
    expect(projects.folders.map((folder) => folder.id), [
      'folder-design',
      'folder-archive',
    ]);
    expect(projects.folders.map((folder) => folder.order), [3, 8]);
    final designFile = projects.folders.first.files.single;
    expect(designFile.reference.stableKey, first.stableKey);
    expect(designFile.order, 5);
    expect(designFile.tags, ['priority', 'client']);
    expect(designFile.favorite, isTrue);
    expect(designFile.customLabel, 'Approved artwork');
    expect(designFile.pendingProviderReconciliation, isTrue);
    expect(reopened.virtualFolders.single.items.map((item) => item.stableKey), [
      first.stableKey,
      second.stableKey,
    ]);
    expect(reopened.savedViews.single.sortField, 'size');
    expect(reopened.savedViews.single.filterTags, ['priority']);
    expect(reopened.globalTags, containsAll(['work', 'priority', 'client']));
    expect(reopened.preferences, source.preferences);
    expect(planned.pendingProviderReferences, 3);
  });
}
