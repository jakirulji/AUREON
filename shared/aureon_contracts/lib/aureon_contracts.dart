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


/// Validates durable transfer state transitions shared by platform adapters.
class TransferStateMachine {
  TransferStateMachine._();

  static const Map<TransferState, Set<TransferState>> _allowed = {
    TransferState.queued: {
      TransferState.preparing, TransferState.paused,
      TransferState.waitingForNetwork, TransferState.waitingForAuth,
      TransferState.waitingForQuota, TransferState.cancelled,
    },
    TransferState.preparing: {
      TransferState.transferring, TransferState.paused,
      TransferState.waitingForNetwork, TransferState.waitingForAuth,
      TransferState.waitingForQuota, TransferState.retryWait,
      TransferState.failed, TransferState.cancelled,
    },
    TransferState.transferring: {
      TransferState.finalizing, TransferState.paused,
      TransferState.waitingForNetwork, TransferState.waitingForAuth,
      TransferState.waitingForQuota, TransferState.retryWait,
      TransferState.conflict, TransferState.failed, TransferState.cancelled,
    },
    TransferState.finalizing: {
      TransferState.verifying, TransferState.waitingForNetwork,
      TransferState.waitingForAuth, TransferState.retryWait,
      TransferState.conflict, TransferState.failed, TransferState.cancelled,
    },
    TransferState.verifying: {
      TransferState.verified, TransferState.waitingForNetwork,
      TransferState.waitingForAuth, TransferState.retryWait,
      TransferState.conflict, TransferState.failed, TransferState.cancelled,
    },
    TransferState.paused: {TransferState.queued, TransferState.cancelled},
    TransferState.waitingForNetwork: {
      TransferState.queued, TransferState.paused, TransferState.cancelled,
    },
    TransferState.waitingForAuth: {
      TransferState.queued, TransferState.paused, TransferState.cancelled,
    },
    TransferState.waitingForQuota: {
      TransferState.queued, TransferState.paused, TransferState.cancelled,
    },
    TransferState.retryWait: {
      TransferState.queued, TransferState.paused, TransferState.cancelled,
    },
    TransferState.conflict: {TransferState.queued, TransferState.cancelled},
    TransferState.failed: {TransferState.queued, TransferState.cancelled},
    TransferState.verified: {},
    TransferState.cancelled: {},
  };

  /// A transfer can enter verified only with affirmative remote evidence.
  static bool canTransition(
    TransferState from,
    TransferState to, {
    bool remoteVerified = false,
  }) {
    if (to == TransferState.verified && !remoteVerified) return false;
    return _allowed[from]?.contains(to) ?? false;
  }
}

/// Stable identity for a provider-backed object. The provider account and
/// item IDs—not display names or paths—are the cross-device identity.
class ProviderFileReference {
  const ProviderFileReference({
    required this.provider,
    required this.providerAccountId,
    required this.accountLabel,
    required this.providerItemId,
    required this.name,
    this.providerParentId,
    this.mimeType,
    this.sizeBytes,
    this.webUrl,
    this.isReconciled = false,
  });

  final ProviderKind provider;
  final String providerAccountId;
  final String accountLabel;
  final String providerItemId;
  final String name;
  final String? providerParentId;
  final String? mimeType;
  final int? sizeBytes;
  final String? webUrl;
  /// True only after a live provider inventory confirms this stable object ID.
  final bool isReconciled;

  String get stableKey => '${provider.name}|${providerAccountId.length}:$providerAccountId|${providerItemId.length}:$providerItemId';

  Map<String, Object?> toJson() => {
    'provider': provider.name,
    'providerAccountId': providerAccountId,
    'accountLabel': accountLabel,
    'providerItemId': providerItemId,
    'name': name,
    'providerParentId': providerParentId,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
    'webUrl': webUrl,
    'isReconciled': isReconciled,
  };

  factory ProviderFileReference.fromJson(Map<String, Object?> json) {
    final providerName = json['provider'] as String?;
    if (!ProviderKind.values.any((value) => value.name == providerName)) {
      throw const FormatException('Unknown provider kind.');
    }
    final provider = ProviderKind.values.firstWhere((value) => value.name == providerName);
    final accountId = json['providerAccountId'] as String?;
    final itemId = json['providerItemId'] as String?;
    final name = json['name'] as String?;
    final label = json['accountLabel'] as String?;
    if ([accountId, itemId, name, label].any((value) => value == null || value.trim().isEmpty)) {
      throw const FormatException('Provider file identity fields are required.');
    }
    return ProviderFileReference(
      provider: provider,
      providerAccountId: accountId!,
      accountLabel: label!,
      providerItemId: itemId!,
      name: name!,
      providerParentId: json['providerParentId'] as String?,
      mimeType: json['mimeType'] as String?,
      sizeBytes: json['sizeBytes'] as int?,
      webUrl: json['webUrl'] as String?,
      isReconciled: json['isReconciled'] == true,
    );
  }
}

/// AUREON-only logical folder. Membership references remote objects and never
/// changes provider-native parents or copies remote bytes.
class AureonVirtualFolder {
  const AureonVirtualFolder({
    required this.id,
    required this.name,
    required this.createdAtEpochMs,
    this.items = const [],
  });

  final String id;
  final String name;
  final int createdAtEpochMs;
  final List<ProviderFileReference> items;

  AureonVirtualFolder add(ProviderFileReference file) {
    if (items.any((item) => item.stableKey == file.stableKey)) return this;
    return AureonVirtualFolder(
      id: id, name: name, createdAtEpochMs: createdAtEpochMs,
      items: [...items, file],
    );
  }

  AureonVirtualFolder remove(String stableKey) => AureonVirtualFolder(
    id: id, name: name, createdAtEpochMs: createdAtEpochMs,
    items: items.where((item) => item.stableKey != stableKey).toList(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAtEpochMs': createdAtEpochMs,
    'items': items.map((item) => item.toJson()).toList(),
  };

  factory AureonVirtualFolder.fromJson(Map<String, Object?> json) {
    final id = json['id'] as String?;
    final name = json['name'] as String?;
    final created = json['createdAtEpochMs'] as int?;
    final rawItems = json['items'];
    if (id == null || id.isEmpty || name == null || name.trim().isEmpty || created == null || rawItems is! List) {
      throw const FormatException('Invalid AUREON virtual folder record.');
    }
    return AureonVirtualFolder(
      id: id,
      name: name,
      createdAtEpochMs: created,
      items: rawItems.map((value) {
        if (value is! Map) throw const FormatException('Invalid virtual folder item.');
        return ProviderFileReference.fromJson(value.cast<String, Object?>());
      }).toList(),
    );
  }
}

