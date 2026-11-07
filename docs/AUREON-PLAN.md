# AUREON — Product & Technical Planning

**Tagline:** Your Digital Universe.  
**Status:** Living specification / planning baseline  
**Version:** 0.1  
**Last updated:** 2026-11-07  
**Priority:** Android first; Windows later

> This document records product decisions and plans. It is not evidence that any feature has been implemented. Implementation status must be supported by code and test evidence.

## 1. Product identity and vision

- **Product:** AUREON
- **Category:** Unified cloud storage, file management, synchronization and backup ecosystem.
- **Positioning:** Premium, futuristic, intelligent and minimal.
- **Platforms:** Android first; Windows later.
- **Principles:** Data safety first; one canonical cloud copy by default; transparent storage location; automatic operation where permitted; privacy and encryption by design; recoverability; incremental delivery.

AUREON aims to provide one coherent interface for files stored across supported cloud accounts and devices: discovery, upload, download, sync, backup, offline access and storage-health monitoring. A unified interface does not turn cloud storage into physical device storage.

Brand, domain and trademark availability have not been verified.

## 2. Platform and architecture

### Android first
Preferred architecture: Flutter UI and application workflows, with Kotlin for Android-native integrations and platform services. Use Android Storage Access Framework (SAF), DocumentsProvider and WorkManager where appropriate. Root is not required for the baseline app.

### Windows later
Begin Windows work only after Android's core file lifecycle is stable. Proposed architecture: Flutter Desktop UI plus native C++ integration with Microsoft's Cloud Files API for File Explorer placeholders, hydration and on-demand files.

### Backend
The backend is primarily a control plane:
- Master identity, sessions and device registry/revocation.
- Linked-provider account mapping and OAuth credential handling, if selected.
- Encrypted metadata synchronization and canonical file-location records.
- Settings, recovery and audit events.

Prefer direct client-to-provider file transfer where feasible. Any content relay must document its privacy, security, bandwidth and cost implications.

## 3. Master account and connected providers

AUREON has its own Master Account, separate from Google accounts. A new device should restore the linked-account inventory, file index, settings and backup state after Master Account sign-in. Google may still require re-authentication if consent is revoked, credentials expire or policy requires it.

Never ask users to enter Google passwords, OTPs or 2FA recovery codes into AUREON. Use official OAuth flows and least-privilege scopes.

Users may connect multiple supported cloud accounts. The interface should provide:
- Unified file browser and search.
- Account-wise storage dashboard.
- Per-account connection and authentication status.
- Per-file provider/account location in File Details.

**Automatic account selection is the desired UX:** users should not need to select an account for every file. However, provider-specific routing must comply with terms and API limits. In particular, do not use multiple Google accounts to evade quotas, shard files, or create an unauthorized pooled quota. A unified UI does not combine separate quotas. Disable overflow behavior where provider policy does not permit it; compliant capacity options may include a paid storage plan or another provider. Never split files into quota-evasion shards.

Design a provider abstraction for legitimate automatic placement/failover where allowed.

## 3A. Cross-device provider authorization and existing-account import

- User links each cloud account once. On a new device, AUREON Master Account sign-in restores the linked-provider inventory and automatically attempts provider reconnection using a user-consented encrypted backend credential vault.
- This vault is the target architecture for the requested seamless experience; it is not implemented yet and must pass dedicated threat-model review, managed KMS envelope-encryption design, least-privilege access controls, audit/rotation, provider-terms review and independent security testing.
- MFA is not requested on every AUREON login. If a provider requires fresh authentication, only that account pauses and the user completes the provider's official challenge. User may manually enter a verification code or authenticator code. AUREON never reads Gmail to harvest OTPs, stores authenticator seeds, collects provider passwords or bypasses MFA.
- Provider credentials remain separate from E2E file-content keys and recovery secrets.
- Existing Google Drive files must be indexed, not only files created by AUREON. Preserve full folder hierarchy and parent IDs; provide additional derived category views without moving or renaming provider files. Full-drive inventory requires the appropriate Google restricted scopes and verification; drive.file alone is insufficient.
- Google Photos is distinct from Drive: represent albums as albums, not folders. Under the API rules effective March 31, 2025, Picker API supports user-mediated selection of existing library media while Library API focuses on app-created content. Do not promise unrestricted background enumeration of an existing Photos library.
- Initial cloud indexing is metadata-first, paginated, resumable and non-destructive. Do not download every item by default; never move, rename or delete existing cloud originals during indexing.
- Detailed requirements: [Cross-Device Cloud Restore and Existing-Content Import](./CLOUD-ACCOUNT-RESTORE-AND-LEGACY-IMPORT.md).

## 4. One canonical cloud copy

Default behavior: **one canonical cloud copy per file**. Do not create duplicate cloud copies across every connected account by default.

File Details must show:
- Actual provider/account location (avoid exposing sensitive identifiers unnecessarily).
- File size.
- Upload and verification status.
- Encryption status.
- Last successful sync time.
- Offline/availability state.

Optional additional encrypted backup copies may be considered later, but are outside the default behavior.

## 5. File lifecycle and deletion safety

This is a critical, non-negotiable requirement.

### Safe upload sequence
1. Identify a user-accessible source file.
2. Confirm permissions and sufficient temporary staging space.
3. Create a temporary upload buffer/copy; preserve the source original.
4. Compute a SHA-256 source fingerprint.
5. Encrypt client-side when enabled/required.
6. Upload the complete object to one selected provider/account.
7. Confirm provider-side upload completion.
8. Verify the remote object (size and ciphertext hash; read-back/download verification where feasible).
9. Confirm encryption metadata and key-recovery readiness.
10. Mark the remote copy verified.
11. Only then may the local original become eligible for cleanup—and only if the user explicitly enabled cleanup and the OS/API grants deletion permission.

### Rules
- Upload success alone never authorizes deletion.
- Interrupted, failed, incomplete or unverified uploads must preserve the original.
- Network loss, crash, reboot, token expiry or verification failure must never trigger deletion.
- SAF deletion may be unavailable; never bypass user-granted permissions.
- Never delete another app's private internal data.
- Cloud deletion must never be a side effect of local cache cleanup.
- Cache eviction may remove only eligible cache entries, never the canonical cloud object, upload staging file or local original.
- If an account is full, disconnected or unauthorized, preserve the original and queue.
- During migration: upload and verify the new copy, atomically update canonical location, then remove the old remote copy only if permitted. Never delete the only known-good copy.

### Persistent lifecycle state machine
Suggested states:
`DISCOVERED`, `WAITING_FOR_PERMISSION`, `WAITING_FOR_SPACE`, `STAGED`, `HASHED`, `ENCRYPTED`, `UPLOADING`, `UPLOAD_INTERRUPTED`, `REMOTE_PENDING_VERIFICATION`, `VERIFYING`, `VERIFIED`, `CLEANUP_ELIGIBLE`, `CLEANUP_BLOCKED`, `COMPLETE`, `FAILED_RETRYABLE`, `FAILED_PERMANENT`, `REMOTE_UNAVAILABLE`.

Persist transitions across process death and reboot. Cleanup eligibility is a separate explicit state; never infer it from upload completion.

## 6. Encryption, privacy and recovery

Target: strict client-side end-to-end encryption.
- AES-256-GCM authenticated encryption.
- SHA-256 integrity fingerprints.
- Random per-file data-encryption keys.
- Secure key wrapping and versioned encryption metadata.
- Android Keystore for local key protection where supported.
- A tested recovery-key or equivalent recovery mechanism.
- TLS in transit, secure sessions and remote device revocation.

The backend must not possess file-content keys if AUREON promises that the backend cannot decrypt files. A backend-held Google OAuth refresh-token vault can simplify new-device account restoration, but makes the backend a trusted control-plane boundary for provider access. Keep provider credentials separate from E2E content keys.

Key loss can mean permanent data loss. Do not call encryption production-ready until recovery UX and restore flows have been tested.

## 7. Android system integration

Use SAF and DocumentsProvider so compatible apps can browse, open and save cloud files through Android's system picker.

Important limitations:
- This does not make cloud capacity appear as physical internal storage in Android Settings.
- Only compatible apps using supported document-provider interfaces can access it.
- An ordinary Android app cannot arbitrarily access or delete other apps' private internal data.
- Background execution is subject to Android/OEM battery and scheduling restrictions; do not promise uninterrupted background work on every device.

WorkManager should handle persistent jobs, retries/backoff, process death, reboot and network transitions where appropriate. An optional experimental Root/FUSE module may be explored later, but is not part of the rootless MVP and carries kernel, SELinux, OEM and Android-version risks.

## 8. Smart Cache and offline access

Planned capabilities:
- Configurable cache limit.
- LRU eviction for unpinned cache entries.
- Pinned files that remain available offline.
- Recent/frequent-file prioritization.
- Low-device-storage safeguards.
- Optional Wi-Fi prefetch.
- Clear cache usage and last-access information.

Cache is local storage consumption, not cloud capacity. A zero cache means cloud-only files may be unavailable offline. Reserve staging capacity for active uploads. Never evict upload staging files or local originals.

## 9. Storage Guardian

Monitor each connected account independently:
- Used/remaining provider storage and API availability.
- OAuth state and re-authentication needs.
- Upload queue, failures and verification status.
- Local disk pressure, cache usage and cleanup candidates.

Initial configurable threshold proposal (not fixed): 70% informational, 80% warning, 90% critical planning notice, 95% urgent capacity warning/preflight, 100% pause uploads to that account and preserve queue/originals. Use provider-reported capacity. Do not suggest adding another Google account to bypass quota.

## 10. Provider abstraction

Initial target: Google Drive, subject to OAuth scope, verification and policy review. Future candidates include OneDrive, Dropbox and user-controlled/self-hosted storage, subject to capabilities, cost and terms.

Provider interface should cover:
- OAuth/connect/disconnect and credential lifecycle.
- Capability and quota reporting.
- List/read/write/delete operations.
- Resumable upload/download.
- Remote metadata and object identifiers.
- Integrity/read-back verification.
- Error classification and retryability.

Do not assume providers have identical semantics or permit identical automatic-placement behavior.

## 11. Initial data model

Conceptual entities:
`User`, `Device`, `ProviderAccount`, `ProviderCredential`, `FileRecord`, `FileVersion`, `FileLocation`, `UploadJob`, `VerificationRecord`, `CacheEntry`, `EncryptionKeyEnvelope`, `AuditEvent`, `UserSettings`.

Store minimal metadata and encrypt sensitive metadata where appropriate. Never log access tokens, refresh tokens, recovery keys or file contents.

## 12. Development roadmap

### Android milestones
- **A0 — Specification and threat model:** requirements, provider-policy boundaries, API contracts, data model, state machine, acceptance tests.
- **A1 — Android foundation:** Flutter/Kotlin skeleton, navigation/design system, local database/migrations, CI.
- **A2 — Master account/device identity:** registration/login, sessions, device registration/revocation, secure local session storage.
- **A3 — Google Drive:** official OAuth, connect/disconnect, token refresh/revocation, scope minimization and verification assessment.
- **A4 — Unified file browser:** account-wise inventory, search/sort/filter, accurate file location.
- **A5 — Safe transfer engine:** queue, staging, retry/resume, persistent state machine, remote verification and no-delete tests.
- **A6 — Encryption/recovery:** client-side encryption, key management, recovery UX and restore tests.
- **A7 — DocumentsProvider:** open/import/save integration, URI permissions and Android-version testing.
- **A8 — Smart Cache/Storage Guardian:** pinning, cache limit/eviction, account/device monitoring and alerts.
- **A9 — Cross-device restore/sync:** metadata/account inventory restoration, provider re-authentication when required, conflict resolution.
- **A10 — Beta/hardening:** failure injection, large-file, process-death/reboot, network-transition, restore, key-recovery, performance, accessibility and security tests.

### Later Windows milestones
Flutter desktop client; native C++ Cloud Files API; Explorer placeholders/hydration; offline pinning and free-up-space; shared identity/metadata/provider engine; installer, signing and CI. Start only after Android core is stable.

### Optional later work
Experimental Root module, additional providers, advanced backup policies and optional multi-copy encrypted backup.

## 13. Testing and release gates

Required test categories:
- State machine, encryption metadata and account-selection unit tests.
- OAuth/provider integration tests.
- Upload/download integrity and wrong-key/passphrase tests.
- Recovery and cross-device metadata restore tests.
- Process kill, reboot, network loss and token expiry.
- Full storage and insufficient staging space.
- SAF permission denial and deletion-not-supported.
- Duplicate/conflict, large-file and interrupted-resume.
- Secret leakage and unauthorized-deletion security checks.

No release if a test demonstrates loss of the only known-good copy, deletion before verification, silent file-location corruption or unrecoverable key handling defects.

Use GitHub Actions. Keep build configuration changes small, reviewed and verified. Record artifact names, commit SHA, workflow result and test evidence for every release. Compilation alone does not prove feature completion.

## 14. Risks and unresolved decisions

1. Google OAuth scopes may trigger restricted-scope verification/security assessment.
2. Provider policies may restrict automatic overflow between accounts.
3. Backend-held refresh tokens simplify restoration but increase trust/security obligations.
4. E2E encryption complicates recovery and multi-device onboarding.
5. Android background execution varies by OEM and battery settings.
6. SAF does not grant universal filesystem access or guaranteed deletion.
7. Windows Cloud Files API is a separate native integration.
8. Provider quotas, pricing, API limits and terms can change.
9. Brand/domain/trademark availability is unverified.

Decisions required before implementation:
- Master-account backend and hosting.
- Authentication and account-recovery model.
- Exact Google OAuth scopes and verification strategy.
- Refresh-token storage/device authorization model.
- Encryption key hierarchy and recovery protocol.
- Minimum Android API range.
- Minimum free-space reserve for staging/cache.
- Provider-specific upload verification/read-back policy.
- Privacy policy, terms and data-retention policy.

## 15. Change log

### 2026-11-07 — Initial planning baseline
- Finalized AUREON name and “Your Digital Universe.” tagline.
- Android-first; Windows deferred.
- Flutter + Kotlin hybrid for Android; Flutter UI + native C++ Cloud Files API for Windows.
- One canonical cloud copy per file by default.
- Automatic account selection desired, subject to provider terms; no quota circumvention.
- File Details must show actual provider/account location.
- Local originals must never be automatically deleted without upload completion, verification, encryption/recovery checks, explicit user authorization and OS permission.
- Smart Cache, offline pinning and Storage Guardian planned.
- Strict client-side E2E encryption is the target.
- Root support is optional/experimental; rootless Android is primary.

### 2026-11-07 — A0 vault and legacy inventory engineering alignment
- Aligned Android OAuth with the user-consented backend credential-vault target for cross-device provider restoration.
- Added explicit consent, KMS/HSM envelope encryption, credential-broker isolation, refresh rotation/lease and access-token delivery boundaries.
- Added V002 PostgreSQL draft for OAuth transactions, provider inventory cursors, real parent hierarchy, provider items and provider-native albums.
- Added metadata-first inventory API contracts and virtual category views; provider originals remain untouched.
- Clarified that Google Photos albums are not Drive folders and are represented only where provider APIs expose them.
- Added PostgreSQL 16 CI migration/smoke-test steps; execution result remains unverified.
- Recommended Kotlin/JVM + Ktor 3.6.x modular monolith provisionally, pending a reproducible architecture spike.

## 16. Transfer Engine and Performance Architecture

### 16.1 Architectural decision

AUREON will use a **common Transfer Coordinator with provider-native transfer adapters**. It will not force every cloud provider through one universal upload protocol.

- The Coordinator owns the user experience and global job lifecycle: queue, priority, pause/resume, progress, retry/backoff, scheduling, cancellation, persistence, notifications and telemetry.
- Each provider adapter uses that provider's official, supported upload/download APIs and semantics.
- A shared transfer interface normalizes behavior without hiding provider-specific capabilities, limits or failure conditions.
- The download path may optionally use a separately audited open-source engine (aria2 is an evaluation candidate), but only where licensing, Android integration, security and provider authentication are compatible. It is not a universal requirement and must not replace provider-specific authorization or integrity checks.
- AUREON should avoid proxying all file bytes through its own backend when direct client-to-provider transfer is supported. Backend relay is an explicit fallback only, with documented privacy, bandwidth, cost and operational implications.

### 16.2 Upload strategy — provider-native resumable upload

Use the cloud provider's official resumable/session-based upload mechanism whenever available. Examples to implement and validate:
- **Google Drive:** resumable upload session for large files or unreliable mobile networks; persist the session URI securely and query server-acknowledged progress after interruption. Follow Google's chunk alignment and resume rules. Session URLs are sensitive capabilities and must be protected.
- **Microsoft OneDrive/Graph:** upload sessions and byte-range fragments; persist the session URL/expiry and follow the API's required fragment sizing, ordering and retry behavior.
- **Dropbox:** use its upload-session/chunked upload API and provider-specific append/finish semantics.
- **Other providers:** implement the official resumable/multipart mechanism where available; do not assume all providers behave identically.

The Coordinator exposes a consistent UX, but the adapter controls chunk sizing, parallelism, retry semantics, session expiry and finalization according to the provider's documented contract.

### 16.3 Upload reliability and duplicate prevention

The upload engine must be designed for **at-least-once network delivery with idempotent/reconciled finalization**, not an unsafe assumption that a request is delivered exactly once.

For every logical upload:
1. Create and persist a unique AUREON operation ID before network transfer.
2. Persist the source identity, stable source snapshot/staging reference, byte length, MIME type, modification metadata where available, and a cryptographic fingerprint.
3. Resolve the target provider/account and canonical file identity before starting.
4. Create or resume one provider upload session; securely persist its identifier/URL, expiry and acknowledged offset/parts.
5. After timeouts or ambiguous responses, query provider session/status or reconcile remote metadata before sending bytes again or creating a new object.
6. Use provider-supported idempotency/precondition/conflict controls where available. Never blindly repeat a create/finalize request after an uncertain response.
7. Finalize exactly once from the Coordinator's perspective. If the provider response is lost, search/reconcile using the operation metadata and remote object identity before retrying finalization.
8. Record the resulting provider object ID and canonical FileLocation transactionally. Enforce a uniqueness constraint for the logical operation and canonical object mapping.
9. Verify the completed remote object before marking the job successful.

If the provider does not offer a reliable idempotency key, use persisted session identity, deterministic AUREON operation metadata and remote reconciliation. Do not promise absolute exactly-once semantics where the provider API cannot guarantee them; make retries safe and duplicates detectable/remediable.

### 16.4 Chunking, speed and adaptive behavior

- Use resumable chunks for large files and unstable connections; small files may use a provider's simpler upload method when it is more efficient.
- Start with conservative provider-compliant chunk sizes, then tune through measured device/network/provider performance.
- Adapt chunk size and concurrency to connection quality, server responses, device memory, thermal/battery state and provider limits.
- Do not assume more parallel connections mean higher throughput. Respect rate limits and use bounded concurrency.
- Use exponential backoff with jitter for transient network and server failures; honor Retry-After and provider-specific guidance. Do not endlessly retry permanent errors such as revoked authorization, quota exhaustion or invalid requests.
- Support pause/resume, cancellation, queue priority, per-job and global speed limits, and background scheduling subject to Android/OEM restrictions.
- Preserve source bytes and staged chunks until remote finalization and verification succeed. Never delete the source merely because all chunks were transmitted.

### 16.5 Data integrity and file-corruption prevention

- Capture a stable source snapshot or stage a copy before transfer. If the source changes during upload, detect it and do not silently mark the uploaded object as the current version.
- Compute SHA-256 over the exact bytes being uploaded (ciphertext when client-side E2E encryption is enabled); where practical also retain a plaintext source fingerprint locally for change detection.
- Verify per-part/chunk checksums when supported by the provider/protocol.
- Verify final remote size and provider checksum/metadata where available. If the provider does not expose a comparable cryptographic checksum, perform a read-back verification where feasible or clearly record the lower assurance level.
- Do not treat an ETag as SHA-256 unless the provider explicitly documents that meaning; multipart ETags commonly are not whole-file hashes.
- Only mark `VERIFIED` after the applicable verification policy passes. A verification failure leaves the source intact and the job failed/retryable or quarantined for diagnosis.
- For encrypted files, persist versioned encryption metadata and key-envelope readiness before declaring the object recoverable.

### 16.6 Download engine and open-source integration

- Keep the same Transfer Coordinator for download jobs, with provider-native download adapters.
- Evaluate aria2 as an optional large-file download backend only after checking GPL-2.0-or-later obligations, Android process/binary integration, security maintenance, memory/battery use, OAuth header handling and compatibility with provider download URLs.
- Use segmented/range downloads only when the provider endpoint supports byte ranges and returns stable validators (such as ETag/If-Range) or equivalent consistency guarantees.
- Fall back to a single-stream resumable download when range support is absent or unsafe.
- Persist range progress and validate the remote object identity before resuming. If the remote version changed, restart safely rather than combining bytes from different versions.
- Download to a temporary file, verify length and checksum, decrypt if applicable, then atomically promote to the final destination where the filesystem permits.
- Never expose a partial or unverified download as a completed file.

### 16.7 Proposed job states

Extend the transfer state model with explicit states such as:
`QUEUED`, `PREPARING`, `SOURCE_SNAPSHOTTED`, `SESSION_CREATING`, `SESSION_ACTIVE`, `TRANSFERRING`, `PAUSED`, `RETRY_WAIT`, `RECONCILING`, `FINALIZING`, `REMOTE_PENDING_VERIFICATION`, `VERIFIED`, `COMPLETED`, `CANCELLED`, `FAILED_RETRYABLE`, `FAILED_PERMANENT`, `SESSION_EXPIRED`.

Persist state and provider session metadata across process death and reboot. Session URLs/tokens must be encrypted at rest and excluded from logs, crash reports and analytics. Session expiry should trigger provider-specific recovery/restart only after remote reconciliation.

### 16.8 Acceptance tests and performance gates

Before release, test:
- Upload pause/resume after app process kill, device reboot, network switch and temporary offline periods.
- Lost response after chunk acceptance and after finalization; prove reconciliation does not create duplicate cloud objects.
- Repeated taps/retries and concurrent requests for the same logical file; prove only one canonical object is recorded.
- Source file modified or removed during upload; preserve data and report a clear state.
- Corrupted chunk, truncated transfer, checksum mismatch and remote object mutation.
- Expired upload session, revoked OAuth token, quota exhaustion, provider throttling and 5xx responses.
- Large files, small files, low RAM, low storage, thermal/battery constraints and flaky networks.
- Provider checksum unavailable or not comparable; verify fallback behavior and disclose verification confidence.
- Encrypted upload/download round trip and key recovery.
- No source deletion before verified remote copy and explicit cleanup permission.

Performance targets must be measured on representative devices and networks; do not promise a fixed speed. Release gates require no silent corruption, no untracked duplicate canonical objects, safe resume after interruption, and preservation of the only known-good copy.

### 16.9 Initial implementation order

1. Define provider-neutral Transfer Coordinator interfaces, persistent job database and state machine.
2. Implement Google Drive adapter using official resumable upload and download APIs.
3. Build deterministic retry/reconciliation and duplicate-prevention tests before optimizing speed.
4. Add adaptive chunking/concurrency and benchmark under realistic mobile network conditions.
5. Add the next provider adapter only after its official API and policy review.
6. Evaluate aria2 independently for Android download use; adopt only if it materially improves measured performance and passes licensing/security review.


### 2026-11-07 — Transfer architecture accepted
- Added a common Transfer Coordinator with provider-native upload/download adapters.
- Selected official provider resumable/session upload APIs over a universal upload engine.
- Added persisted session state, safe resume, idempotent/reconciled finalization and duplicate prevention.
- Added source snapshotting, chunk/final integrity verification and strict preservation of originals until verified completion and explicit cleanup permission.
- Added adaptive chunking/concurrency, bounded retries, background scheduling and provider-specific download behavior.
- aria2 remains an optional download-engine evaluation candidate, subject to license, security, Android and performance review.

## 17. Engineering documents

- [A0 Status and Exit-Gate Tracker](./A0-STATUS.md) — evidence-based readiness matrix; distinguishes authored documents from validated tests and implemented code.
- [A0 Engineering Blueprint](./A0-ENGINEERING-BLUEPRINT.md) — system boundaries, backend structure, data model, API contract, OAuth/security decisions, transfer contract, validation gates and A0 exit criteria.
- [Server Data Model](./DATA-MODEL.md) — PostgreSQL entities, ownership constraints, credential-vault invariants and metadata-first provider inventory.
- [V001 PostgreSQL baseline](./migrations/V001__initial_schema.sql) and [V002 vault/inventory migration](./migrations/V002__vault-and-provider-inventory.sql) — additive schema evolution; V002 must run after V001.
- [Android Native OAuth and Credential Lifecycle](./ANDROID-NATIVE-OAUTH-AND-CREDENTIAL-LIFECYCLE.md) — provider callback patterns, user-consented credential vault, cross-device restoration and refresh safety.
- [OpenAPI v1 contract](./openapi/v1.yaml) — identity, provider authorization, inventory, file catalog, sync and transfer control-plane endpoints.
- [ADR-0001 Backend Stack](./adr/ADR-0001-BACKEND-STACK.md) — provisional Kotlin/Ktor modular-monolith recommendation and required proof-of-concept gates.

## 18. Plan maintenance

For each new idea:
1. Add a dated Change Log entry.
2. Mark it Proposed until explicitly accepted.
3. Update the relevant product/technical section.
4. Check security, provider-policy and data-safety conflicts.
5. Add acceptance criteria and tests before marking Implemented.
6. Never silently rewrite a prior decision; record why it changed.

**Source of truth:** this planning document in the AUREON GitHub repository. Keep implementation status separate from planned scope.
