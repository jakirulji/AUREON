/// Platform-neutral contracts shared by AUREON Android and Windows clients.
library;

enum TransferState {
  queued,
  preparing,
  transferring,
  finalizing,
  verifying,
  verified,
  paused,
  waitingForNetwork,
  waitingForAuth,
  waitingForQuota,
  retryWait,
  conflict,
  failed,
  cancelled,
}

enum TransferError {
  networkUnavailable,
  rateLimited,
  providerUnavailable,
  authRequired,
  accountRevoked,
  scopeInsufficient,
  quotaExceeded,
  objectTooLarge,
  unsupportedCapability,
  sourceChanged,
  sourceUnreadable,
  destinationConflict,
  sessionExpired,
  integrityMismatch,
  permissionDenied,
  cancelled,
  internalError,
}

enum ProviderKind { googleDrive, oneDrive, dropbox, s3Compatible, other }

class FileIdentity {
  const FileIdentity({
    required this.fileId,
    required this.versionId,
    required this.providerAccountId,
    required this.providerItemId,
    this.providerParentId,
    this.providerVersion,
    this.canonicalLocationId,
    this.contentFingerprintSha256,
  });

  final String fileId;
  final String versionId;
  final String providerAccountId;
  final String providerItemId;
  final String? providerParentId;
  final String? providerVersion;
  final String? canonicalLocationId;
  final String? contentFingerprintSha256;

  Map<String, Object?> toJson() => {
        'fileId': fileId,
        'versionId': versionId,
        'providerAccountId': providerAccountId,
        'providerItemId': providerItemId,
        'providerParentId': providerParentId,
        'providerVersion': providerVersion,
        'canonicalLocationId': canonicalLocationId,
        'contentFingerprintSha256': contentFingerprintSha256,
      };
}

class ProviderCapabilities {
  const ProviderCapabilities({
    required this.resumableUpload,
    required this.resumableDownload,
    required this.rangeDownload,
    required this.remoteChecksum,
    required this.readBackVerification,
    required this.hierarchyListing,
    required this.changeCursor,
    required this.placeholderHydration,
    required this.offlinePinning,
    this.maximumObjectBytes,
    this.minimumChunkBytes,
    this.maximumChunkBytes,
  });

  final bool resumableUpload;
  final bool resumableDownload;
  final bool rangeDownload;
  final bool remoteChecksum;
  final bool readBackVerification;
  final bool hierarchyListing;
  final bool changeCursor;
  final bool placeholderHydration;
  final bool offlinePinning;
  final int? maximumObjectBytes;
  final int? minimumChunkBytes;
  final int? maximumChunkBytes;

  Map<String, Object?> toJson() => {
        'resumableUpload': resumableUpload,
        'resumableDownload': resumableDownload,
        'rangeDownload': rangeDownload,
        'remoteChecksum': remoteChecksum,
        'readBackVerification': readBackVerification,
        'hierarchyListing': hierarchyListing,
        'changeCursor': changeCursor,
        'placeholderHydration': placeholderHydration,
        'offlinePinning': offlinePinning,
        'maximumObjectBytes': maximumObjectBytes,
        'minimumChunkBytes': minimumChunkBytes,
        'maximumChunkBytes': maximumChunkBytes,
      };
}

class CleanupEvidence {
  const CleanupEvidence({
    required this.remoteObjectCommitted,
    required this.remoteVerified,
    required this.canonicalLocationPersisted,
    required this.keyRecoveryMetadataReady,
    required this.userOptedIn,
    required this.osDeletionPermissionGranted,
  });

  final bool remoteObjectCommitted;
  final bool remoteVerified;
  final bool canonicalLocationPersisted;
  final bool keyRecoveryMetadataReady;
  final bool userOptedIn;
  final bool osDeletionPermissionGranted;

  bool get eligible =>
      remoteObjectCommitted &&
      remoteVerified &&
      canonicalLocationPersisted &&
      keyRecoveryMetadataReady &&
      userOptedIn &&
      osDeletionPermissionGranted;
}

class TransferCheckpoint {
  const TransferCheckpoint({
    required this.operationId,
    required this.fileId,
    required this.versionId,
    required this.providerAccountId,
    required this.state,
    required this.acknowledgedBytes,
    this.totalBytes,
    this.error,
  });

  final String operationId;
  final String fileId;
  final String versionId;
  final String providerAccountId;
  final TransferState state;
  final int acknowledgedBytes;
  final int? totalBytes;
  final TransferError? error;

  bool get byteCountsValid =>
      acknowledgedBytes >= 0 &&
      (totalBytes == null ||
          (totalBytes! >= 0 && acknowledgedBytes <= totalBytes!));

  Map<String, Object?> toJson() => {
        'operationId': operationId,
        'fileId': fileId,
        'versionId': versionId,
        'providerAccountId': providerAccountId,
        'state': state.name,
        'acknowledgedBytes': acknowledgedBytes,
        'totalBytes': totalBytes,
        'error': error?.name,
      };
}
