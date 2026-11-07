# AUREON — Shared Android/Windows Platform Contracts

**Version:** 0.1  
**Status:** Proposed freeze baseline; implementation must conform, and changes require a reviewed versioned decision.  
**Purpose:** Keep Android and Windows implementations behaviorally consistent while allowing platform-native storage, transfer and shell integration.

This document is the shared contract boundary for Flutter/Dart domain logic, Android/Kotlin adapters and Windows/C++ adapters. It does not claim that either platform adapter is production-complete.

## 1. Logical file identity

A logical AUREON file is not identified by a path or provider object ID alone.

- `file_id`: immutable AUREON UUID for the logical file.
- `version_id`: immutable UUID for a content version.
- `provider_account_id`: AUREON identity of the linked provider account.
- `provider_item_id`: opaque provider-native item identifier.
- `provider_parent_id`: provider-native parent identifier; preserve the actual hierarchy.
- `provider_version`: opaque provider revision/ETag/version token where exposed.
- `canonical_location_id`: at most one verified canonical location per file version.
- `content_fingerprint`: SHA-256 of the exact byte representation defined by the encryption protocol (ciphertext when E2E encryption is active).

Paths, names and MIME types are mutable metadata, not identity. Renames and moves must not create a new logical file or content version. Provider IDs are scoped to their provider account. A shortcut/alias is a separate provider item that may point to a target; never silently duplicate or conflate the target's content.

## 2. Provider account and capability model

Every linked account has an AUREON account ID, provider type, provider subject, display label, authorization state, granted scopes, capability snapshot and last successful validation time.

Authorization states are: `connected`, `reauth_required`, `revoked`, `temporarily_unavailable`, and `disconnected`. A provider challenge pauses work for that account only; other accounts remain usable.

Capabilities are explicit booleans or typed limits, never inferred from provider name:
- resumable upload and session expiry;
- upload part/chunk bounds and maximum object size;
- resumable/range download and stable validator support;
- server-side checksum/read-back verification;
- metadata listing, change cursor and hierarchy support;
- placeholder/hydration and offline pin support;
- provider-native move, copy, rename and delete support.

Quota, rate limits and account eligibility remain provider-specific. AUREON may present a unified view but must not pool accounts to evade quotas or split files to bypass provider limits.

## 3. Transfer operation contract

Every transfer has a stable client-generated `operation_id`, scoped to the user and bound to a canonical request hash. Persist the operation before network side effects.

Minimum durable fields:
- operation ID, logical file/version IDs and provider account ID;
- operation kind and direction;
- source snapshot reference and source fingerprint;
- expected total bytes and acknowledged bytes;
- provider session envelope (encrypted at rest);
- current state, retry count, next retry time and last typed error;
- remote object ID/revision, verification evidence and timestamps.

Canonical states:
`queued` → `preparing` → `transferring` → `finalizing` → `verifying` → `verified`.

Side states: `paused`, `waiting_for_network`, `waiting_for_auth`, `waiting_for_quota`, `retry_wait`, `conflict`, `failed`, `cancelled`.

Terminal success means remote verification passed, not merely that all bytes were sent. State transitions are validated and durably persisted. Unknown/ambiguous provider outcomes require reconciliation before retry; never blindly repeat a non-idempotent create/finalize call. Do not promise exactly-once behavior where the provider API cannot guarantee it.

The shared coordinator owns queue ordering, scheduling, pause/resume/cancel, retry/backoff, progress, persistence and reconciliation. Provider adapters own OAuth access, provider-specific sessions, chunk rules, throttling, checksum semantics, range requests and conflict interpretation.

## 4. Verification and source-deletion invariant

Upload acknowledgement is not verification. Verification evidence may include provider checksum, remote read-back hash, stable remote metadata plus a provider-guaranteed checksum, or a documented provider-specific equivalent. ETag is not assumed to be SHA-256.

The local source is preserved unless every condition is true:
1. the complete remote object is committed;
2. remote verification policy passed;
3. the correct file version and canonical location are durably recorded;
4. required E2E key/recovery metadata is confirmed;
5. the user explicitly enabled source cleanup for this operation or applicable policy;
6. the operating system granted deletion permission.

Default cleanup opt-in is false. Failed, interrupted, ambiguous or auth-blocked operations never delete the source. Cache eviction must never remove a source original, staging snapshot or only known-good copy.

## 5. Encryption envelope boundary

The file-content encryption protocol is versioned and platform-neutral. Android and Windows must consume identical test vectors before either is considered interoperable.

Minimum envelope metadata:
- protocol and format version;
- algorithm suite identifier;
- file/version identity;
- nonce/stream parameters;
- wrapped per-file-version DEK and wrapping-key reference;
- authenticated metadata and ciphertext length;
- chunk/stream framing and finalization marker.

Candidate suite and key hierarchy remain subject to independent cryptographic review. Do not invent a Windows-specific format or rely on provider ETags as cryptographic integrity. Provider OAuth credential envelopes are a separate trust domain from E2E content keys.

## 6. Shared error taxonomy

Adapters map native/provider errors into stable categories:
- `network_unavailable`, `rate_limited`, `provider_unavailable`;
- `auth_required`, `account_revoked`, `scope_insufficient`;
- `quota_exceeded`, `object_too_large`, `unsupported_capability`;
- `source_changed`, `source_unreadable`, `destination_conflict`;
- `session_expired`, `integrity_mismatch`, `permission_denied`;
- `cancelled`, `internal_error`.

Preserve provider-native diagnostic codes in redacted structured details for troubleshooting. Never expose bearer tokens, signed session URLs, raw authorization codes, filesystem secrets or encryption keys in logs or UI diagnostics.

## 7. Platform adapter responsibilities

### Android
Kotlin owns Room, SAF URI permissions, Android Keystore, WorkManager, notifications, local staging and Android file operations. Flutter accesses these through typed Pigeon APIs. Flutter widgets never access Room or provider credentials directly.

### Windows
C++/Win32/WinRT owns filesystem enumeration and operations, permissions, reparse points, Cloud Files API sync roots, placeholders, hydration/dehydration and shell integration. Flutter owns cross-platform presentation and shared domain workflows. Windows must keep the native File Explorer available and use supported user-controlled associations and shell entry points.

### Shared Flutter/domain layer
Owns platform-neutral file/provider/transfer models, use cases, state presentation, accessibility and common UX. It must not embed OS-specific handles or provider HTTP details in widgets.

## 8. Contract freeze and change control

The following are freeze candidates for the first vertical slice:
- logical file/version/location identity;
- provider account and capability model;
- transfer operation ID, durable checkpoint and state/error taxonomy;
- verification evidence and no-auto-delete invariant;
- versioned encryption envelope and cross-platform test vectors.

A contract change requires:
1. update this document and the relevant OpenAPI/schema/ADR;
2. add migration or compatibility notes if persisted data changes;
3. add shared test vectors/fixtures;
4. run Android and Windows contract tests;
5. document backward compatibility and rollout behavior.

## 9. Exit criteria for parallel platform implementation

- Shared data types compile or validate independently of Android/Windows SDKs.
- Transfer state transition tests run on CI without platform dependencies.
- File identity, account capability, error mapping and cleanup eligibility fixtures are shared.
- Encryption interoperability test vectors are approved before real encrypted transfer is enabled.
- Each platform adapter has its own native integration tests and cannot weaken shared safety invariants.
