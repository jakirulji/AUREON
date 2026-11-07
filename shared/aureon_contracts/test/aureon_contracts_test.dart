import 'dart:convert';
import 'dart:io';

import 'package:aureon_contracts/aureon_contracts.dart';
import 'package:test/test.dart';

void main() {

  group('TransferStateMachine', () {
    test('enforces the forward transfer lifecycle', () {
      expect(TransferStateMachine.canTransition(TransferState.queued, TransferState.preparing), isTrue);
      expect(TransferStateMachine.canTransition(TransferState.preparing, TransferState.transferring), isTrue);
      expect(TransferStateMachine.canTransition(TransferState.transferring, TransferState.finalizing), isTrue);
      expect(TransferStateMachine.canTransition(TransferState.finalizing, TransferState.verifying), isTrue);
    });

    test('verified requires remote verification evidence', () {
      expect(TransferStateMachine.canTransition(TransferState.verifying, TransferState.verified), isFalse);
      expect(TransferStateMachine.canTransition(
        TransferState.verifying, TransferState.verified, remoteVerified: true,
      ), isTrue);
    });

    test('prevents skipping verification and reopening terminal states', () {
      expect(TransferStateMachine.canTransition(
        TransferState.transferring, TransferState.verified, remoteVerified: true,
      ), isFalse);
      expect(TransferStateMachine.canTransition(TransferState.verified, TransferState.queued), isFalse);
      expect(TransferStateMachine.canTransition(TransferState.cancelled, TransferState.queued), isFalse);
    });

    test('allows auth-blocked work to resume', () {
      expect(TransferStateMachine.canTransition(
        TransferState.waitingForAuth, TransferState.queued,
      ), isTrue);
    });
  });


  group('CleanupEvidence', () {
    test('default-safe evidence never permits cleanup without opt-in', () {
      const evidence = CleanupEvidence(
        remoteObjectCommitted: true,
        remoteVerified: true,
        canonicalLocationPersisted: true,
        keyRecoveryMetadataReady: true,
        userOptedIn: false,
        osDeletionPermissionGranted: true,
      );
      expect(evidence.eligible, isFalse);
    });

    test('every safety condition is required', () {
      const evidence = CleanupEvidence(
        remoteObjectCommitted: true,
        remoteVerified: true,
        canonicalLocationPersisted: true,
        keyRecoveryMetadataReady: true,
        userOptedIn: true,
        osDeletionPermissionGranted: true,
      );
      expect(evidence.eligible, isTrue);

      const noVerification = CleanupEvidence(
        remoteObjectCommitted: true,
        remoteVerified: false,
        canonicalLocationPersisted: true,
        keyRecoveryMetadataReady: true,
        userOptedIn: true,
        osDeletionPermissionGranted: true,
      );
      expect(noVerification.eligible, isFalse);
    });
  });

  test('checkpoint rejects negative or over-acknowledged byte counts', () {
    const valid = TransferCheckpoint(
      operationId: 'op-1',
      fileId: 'file-1',
      versionId: 'v1',
      providerAccountId: 'drive-1',
      state: TransferState.transferring,
      acknowledgedBytes: 50,
      totalBytes: 100,
    );
    expect(valid.byteCountsValid, isTrue);

    const overrun = TransferCheckpoint(
      operationId: 'op-2',
      fileId: 'file-1',
      versionId: 'v1',
      providerAccountId: 'drive-1',
      state: TransferState.transferring,
      acknowledgedBytes: 101,
      totalBytes: 100,
    );
    expect(overrun.byteCountsValid, isFalse);
  });

  test('serialization uses stable state names', () {
    const checkpoint = TransferCheckpoint(
      operationId: 'op-3',
      fileId: 'file-2',
      versionId: 'v4',
      providerAccountId: 'dropbox-1',
      state: TransferState.waitingForAuth,
      acknowledgedBytes: 0,
    );
    expect(checkpoint.toJson()['state'], 'waitingForAuth');
    expect(checkpoint.toJson()['totalBytes'], isNull);
  });

  test('shared cross-platform fixture matches Dart contract serialization', () {
    final fixture = jsonDecode(
      File('../contract-fixtures/contract-v1.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    expect(fixture['schemaVersion'], 1);

    final identity = FileIdentity(
      fileId: 'file-fixture-001',
      versionId: 'version-fixture-001',
      providerAccountId: 'drive-account-001',
      providerItemId: 'provider-item-001',
      providerParentId: 'provider-folder-001',
      providerVersion: 'rev-7',
      canonicalLocationId: 'location-001',
      contentFingerprintSha256: 'a' * 64,
    );
    expect(identity.toJson(), fixture['fileIdentity']);

    final capabilities = ProviderCapabilities(
      resumableUpload: true,
      resumableDownload: true,
      rangeDownload: true,
      remoteChecksum: false,
      readBackVerification: true,
      hierarchyListing: true,
      changeCursor: true,
      placeholderHydration: false,
      offlinePinning: false,
      maximumObjectBytes: 1073741824,
      minimumChunkBytes: 262144,
      maximumChunkBytes: 8388608,
    );
    expect(capabilities.toJson(), fixture['providerCapabilities']);

    final checkpoint = TransferCheckpoint(
      operationId: 'operation-fixture-001',
      fileId: 'file-fixture-001',
      versionId: 'version-fixture-001',
      providerAccountId: 'drive-account-001',
      state: TransferState.waitingForAuth,
      acknowledgedBytes: 524288,
      totalBytes: 1048576,
      error: TransferError.authRequired,
    );
    expect(checkpoint.toJson(), fixture['transferCheckpoint']);

    final cleanup = fixture['cleanupEvidence'] as Map<String, dynamic>;
    final evidence = CleanupEvidence(
      remoteObjectCommitted: cleanup['remoteObjectCommitted'] as bool,
      remoteVerified: cleanup['remoteVerified'] as bool,
      canonicalLocationPersisted: cleanup['canonicalLocationPersisted'] as bool,
      keyRecoveryMetadataReady: cleanup['keyRecoveryMetadataReady'] as bool,
      userOptedIn: cleanup['userOptedIn'] as bool,
      osDeletionPermissionGranted: cleanup['osDeletionPermissionGranted'] as bool,
    );
    expect(evidence.eligible, cleanup['eligible']);
    expect(evidence.eligible, isFalse);
  });
}

  group('AUREON virtual folders', () {
    ProviderFileReference makeFile(String account, String item) => ProviderFileReference(
      provider: ProviderKind.googleDrive,
      providerAccountId: account,
      accountLabel: account,
      providerItemId: item,
      name: 'report.pdf',
      providerParentId: 'original-parent',
    );

    test('one logical folder can contain files from multiple provider accounts', () {
      final folder = AureonVirtualFolder(
        id: 'folder-1', name: 'Projects', createdAtEpochMs: 100,
      ).add(makeFile('drive-a', 'item-a')).add(makeFile('drive-b', 'item-b'));
      expect(folder.items, hasLength(2));
      expect(folder.items.map((item) => item.providerAccountId).toSet(), {'drive-a', 'drive-b'});
      expect(folder.items.every((item) => item.providerParentId == 'original-parent'), isTrue);
    });

    test('membership is idempotent and scoped by provider account identity', () {
      final first = makeFile('drive-a', 'same-item');
      final second = makeFile('drive-b', 'same-item');
      final folder = AureonVirtualFolder(
        id: 'folder-2', name: 'Mixed', createdAtEpochMs: 100,
      ).add(first).add(first).add(second);
      expect(folder.items, hasLength(2));
      expect(folder.remove(first.stableKey).items.single.providerAccountId, 'drive-b');
    });

    test('virtual folder serialization round trips stable provider identity', () {
      final folder = AureonVirtualFolder(
        id: 'folder-3', name: 'Archive', createdAtEpochMs: 123,
      ).add(makeFile('dropbox-account', 'dropbox-object'));
      final restored = AureonVirtualFolder.fromJson(folder.toJson());
      expect(restored.id, folder.id);
      expect(restored.items.single.stableKey, folder.items.single.stableKey);
    });
  });
