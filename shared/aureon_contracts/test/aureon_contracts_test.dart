import 'package:aureon_contracts/aureon_contracts.dart';
import 'package:test/test.dart';

void main() {
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
}

import 'dart:convert';
import 'dart:io';

import 'package:aureon_contracts/aureon_contracts.dart';
import 'package:test/test.dart';

void main() {
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

    final capability = ProviderCapabilities(
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
    expect(capability.toJson(), fixture['providerCapabilities']);

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
