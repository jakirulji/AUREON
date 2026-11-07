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
