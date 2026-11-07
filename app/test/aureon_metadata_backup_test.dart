import 'package:aureon/src/backup/aureon_metadata_backup.dart';
import 'package:aureon_contracts/aureon_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderFileReference _file(String account, String item, String name) => ProviderFileReference(
  provider: ProviderKind.googleDrive,
  providerAccountId: account,
  accountLabel: account,
  providerItemId: item,
  name: name,
  providerParentId: 'provider-parent-original',
);

AureonMetadataSnapshot _snapshot() {
  final ref = _file('drive-account-01', 'provider-item-01', 'design.pdf');
  return AureonMetadataSnapshot(
    snapshotId: 'snapshot-fixture',
    generation: 4,
    createdAtEpochMs: 123456,
    rootFolders: [
      AureonMetadataFolder(
        id: 'root-projects',
        name: 'Projects',
        order: 0,
        folders: [
          AureonMetadataFolder(
            id: 'nested-design',
            name: 'Design',
            order: 2,
            files: [
              AureonMetadataFileEntry(
                reference: ref,
                order: 7,
                tags: const ['client', 'important'],
                favorite: true,
                customLabel: 'Final design',
              ),
            ],
          ),
        ],
      ),
    ],
    virtualFolders: [
      AureonVirtualFolder(
        id: 'virtual-cross-account',
        name: 'Cross-account research',
        createdAtEpochMs: 100,
        items: [ref, _file('drive-account-02', 'provider-item-02', 'budget.xlsx')],
      ),
    ],
    savedViews: const [
      AureonSavedView(id: 'view-recent', name: 'Recent work', sortField: 'modified', descending: true),
    ],
    globalTags: const ['client', 'important'],
    preferences: const {'sort': 'custom', 'showHidden': false},
  );
}

void main() {
  test('snapshot serialization preserves exact nested folder and file ordering', () {
    final decoded = AureonMetadataSnapshot.fromJson(_snapshot().toJson());
    final root = decoded.rootFolders.single;
    expect(root.name, 'Projects');
    expect(root.order, 0);
    expect(root.folders.single.name, 'Design');
    expect(root.folders.single.order, 2);
    expect(root.folders.single.files.single.order, 7);
    expect(root.folders.single.files.single.customLabel, 'Final design');
    expect(root.folders.single.files.single.favorite, isTrue);
    expect(decoded.virtualFolders.single.items, hasLength(2));
    expect(decoded.savedViews.single.sortField, 'modified');
    expect(decoded.preferences['sort'], 'custom');
  });

  test('encrypted metadata archive round trips and rejects wrong passphrase', () async {
    final codec = AureonMetadataBackupCodec();
    final bytes = await codec.encrypt(_snapshot(), 'independent-metadata-backup-passphrase');
    final restored = await codec.decrypt(bytes, 'independent-metadata-backup-passphrase');
    expect(restored.toJson(), _snapshot().toJson());
    await expectLater(
      codec.decrypt(bytes, 'incorrect-independent-passphrase'),
      throwsA(anything),
    );
  });

  test('restore keeps exact backup tree and marks provider references pending', () {
    final backup = _snapshot();
    final current = AureonMetadataSnapshot(
      snapshotId: 'current',
      generation: 8,
      createdAtEpochMs: 999,
      rootFolders: const [AureonMetadataFolder(id: 'local-only', name: 'Local only', order: 9)],
      virtualFolders: const [],
    );
    final result = AureonMetadataRestorePlanner().merge(current: current, backup: backup);
    expect(result.snapshot.rootFolders.first.name, 'Projects');
    expect(result.snapshot.rootFolders.first.folders.single.name, 'Design');
    expect(result.snapshot.rootFolders.last.id, 'local-only');
    expect(result.snapshot.rootFolders.first.folders.single.files.single.pendingProviderReconciliation, isTrue);
    expect(result.pendingProviderReferences, greaterThanOrEqualTo(3));
    expect(result.snapshot.generation, 9);
  });

  test('provider re-index filter never restores a missing provider object', () {
    final backup = _snapshot();
    final result = AureonMetadataRestorePlanner().merge(
      current: AureonMetadataSnapshot(snapshotId: 'current', generation: 1, createdAtEpochMs: 1),
      backup: backup,
      liveProviderStableKeys: {'googleDrive|15:drive-account-01|16:provider-item-01'},
    );
    expect(result.snapshot.virtualFolders.single.items, hasLength(1));
    expect(result.snapshot.virtualFolders.single.items.single.providerItemId, 'provider-item-01');
    expect(result.pendingProviderReferences, 0);
  });
}
