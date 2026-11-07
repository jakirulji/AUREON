# AUREON A0 — Readiness and Exit-Gate Tracker

**Last updated:** 2026-11-08  
**Overall status:** <strong>IN PROGRESS</strong> — Contract and existing Ktor/PostgreSQL CI are green; Android and Windows native prototypes are progressing. Owner selected Firebase Spark + Cloudflare Workers/D1, but the Worker/D1 migration, production security approval and live platform integration remain open.

This file is the operational A0 checklist. A document existing in GitHub is not the same as a decision being verified or code being implemented.

## 1. Work completed in the repository

- [A0 Owner Decisions](./A0-OWNER-DECISIONS.md) — remaining owner approvals and recommended defaults.
- [A0 Threat Model](./THREAT-MODEL.md) — STRIDE register, security invariants, separate credential-broker workload requirement and required test evidence.
- [Privacy and Data Governance Baseline](./PRIVACY-DATA-GOVERNANCE.md) — data inventory and policy framework; public policy/legal review remains open.
- [ADR-0002 Master Account Auth & Recovery](./adr/ADR-0002-MASTER-ACCOUNT-AUTH-RECOVERY.md) — passkey-first and offline recovery-code recommendation; owner approval pending.
- [ADR-0003 Android Local Data Boundary](./adr/ADR-0003-ANDROID-LOCAL-DATA-BOUNDARY.md) — Room/Pigeon recommendation; Android prototype pending.
- [ADR-0004 KMS, Hosting & Operations](./adr/ADR-0004-KMS-HOSTING-OPERATIONS.md) — historical managed-KMS proposal; superseded for the current no-card personal deployment by ADR-0005 and the Cloudflare/Firebase direction.
- [ADR-0005 Zero-cost Credential Vault](./adr/ADR-0005-ZERO-COST-CREDENTIAL-VAULT.md) — accepted Worker-Secret-wrapped provider credential vault with server-assisted recovery; not HSM/KMS or zero-knowledge.
- [ADR-0006 Firebase and Cloudflare Free Platform](./adr/ADR-0006-FIREBASE-CLOUDFLARE-FREE-PLATFORM.md) — selected no-card platform direction; TypeScript Worker + D1 migration required.
- [ADR-0007 Dual Credential Vault Recovery](./adr/ADR-0007-DUAL-CREDENTIAL-VAULT-RECOVERY.md) — independent Manual Recovery Key and Cloudflare-assisted recovery with portable encrypted bundle.
- [A1 First Vertical-Slice Backlog](./A1-FIRST-VERTICAL-SLICE-BACKLOG.md) — drafted; Android first vertical slice plus parallel Windows workstream after shared contracts freeze.
- [Windows File Manager Specification](./WINDOWS-FILE-MANAGER-SPEC.md) — accepted product direction; native filesystem spike started.

| Area | Artifact | Current evidence |
|---|---|---|
| Product requirements | [AUREON Plan](./AUREON-PLAN.md) | Product scope and safety rules recorded |
| Architecture | [A0 Engineering Blueprint](./A0-ENGINEERING-BLUEPRINT.md) | Modular-monolith target and trust boundaries documented |
| Backend stack | [ADR-0001](./adr/ADR-0001-BACKEND-STACK.md) | Ktor 3.6.1 / Kotlin 2.4.21 / JDK 21, HikariCP/JDBC to PostgreSQL 18; auth, PKCE, fake-KMS and concurrency tests passed in run #42371046029 |
| Data model | [DATA-MODEL](./DATA-MODEL.md) | V001/V002 entities and ownership invariants documented |
| Database schema | [V001](./migrations/V001__initial_schema.sql), [V002](./migrations/V002__vault-and-provider-inventory.sql) | Additive SQL drafts committed |
| Database tests | [V001 smoke](../tests/database/V001_schema_smoke.sql), [V002 smoke](../tests/database/V002_vault_inventory_smoke.sql) | Both smoke-test suites passed on PostgreSQL 18 in run #42370296201 |
| API | [OpenAPI v1](./openapi/v1.yaml) | OAuth vault, short-lived native access-token broker, provider inventory and album contracts added; formal validation passed in run #42370799202 |
| OAuth | [Provider OAuth Matrix](./PROVIDER-OAUTH-MATRIX.md), [Android OAuth lifecycle](./ANDROID-NATIVE-OAUTH-AND-CREDENTIAL-LIFECYCLE.md) | PKCE/state and exact redirect allowlist are unit-tested; provider-specific code exchange and production callback remain open |
| Existing cloud content | [Cloud Restore and Legacy Import](./CLOUD-ACCOUNT-RESTORE-AND-LEGACY-IMPORT.md) | Drive hierarchy, metadata-first inventory, virtual categories and Photos album constraints documented |
| E2E encryption | [E2E Encryption and Recovery](./E2E-ENCRYPTION-AND-RECOVERY-DESIGN.md) | Proposal exists; independent crypto review and cross-platform test vectors remain |
| CI | [Contract checks workflow](../.github/workflows/aureon-contract-checks.yml) | OpenAPI formal validation and PostgreSQL 18 migration/smoke tests passed. Backend run #42371046029 passed database, auth, PKCE, KMS-boundary, HTTP and build tests. Dependabot enabled for Gradle and Actions updates. |

### Shared contracts and Windows prototype

- Shared JSON fixture `shared/contract-fixtures/contract-v1.json` is consumed by Dart and Android Kotlin tests; Windows C++ uses the same repository baseline and its own native filesystem suite. This is parity scaffolding, not a generated cross-language SDK.
- Dart `TransferStateMachine` validates transfer lifecycle transitions and requires positive remote-verification evidence before entering `verified`; tests cover normal progression, auth recovery and terminal states.
- Android storage workflow **Run #41** (run ID `42378046823`) completed successfully. Shared Dart contract tests, Pigeon generation/analyze, Room persistence/recovery tests, Kotlin bridge compilation, Android module assembly and WorkManager unique scheduling/synthetic Worker tests passed. [View Run #41](https://github.com/jakirulji/AUREON/actions/runs/42378046823). This still does not prove a live FlutterEngine-to-Dart round trip or real provider transfer.
- The Flutter app shell under `app/` contains responsive navigation and a preview dashboard. The first preview build run #42379248406 successfully compiled Android and Windows and uploaded temporary review artifacts. Per the owner's instruction, the workflow was changed to **no artifact uploads**: subsequent runs only analyze, test and compile in ephemeral runners. Final installable APK/Windows bundle will be produced once the agreed feature scope is complete.
- The first local-files slice in `packages/aureon_local_files/` is connected to the Files screen. Android uses SAF tree selection and DocumentsContract; Windows uses IFileDialog and std::filesystem with canonical-root containment. Selected-folder bookmarks persist across launches. The Files screen supports current-folder name search, name/size/modified/type sorting, hidden-entry filtering, size and modified-time metadata, permission/drive recovery with reselection, and native file-open handoff (Android ACTION_VIEW with read grant; Windows ShellExecute after canonical path containment). This remains read-only: no copy/move/rename/delete/recycle-bin, in-app content preview, cloud upload/download or sync yet. Android/Windows widget and native compilation validation for the latest file-open and search implementation is running in [run #42387531676](https://github.com/jakirulji/AUREON/actions/runs/42387531676); no APK/EXE artifacts are uploaded.
- Windows C++20 directory enumeration passed CMake/CTest CI run #42375617817. Safe no-overwrite rename/move/copy plus path-traversal checks passed Windows CI run #42377088269. CNG SHA-256 source-stability and destination-integrity verification passed Windows CI run #42377313897. A Shell IFileOperation recycle-bin adapter explicitly requests recycle-on-delete and passed its disposable-file integration test in Windows CI run #42377449840. A Cloud Files API sync-root register/unregister adapter and disposable-directory integration test passed Windows CI run #42377658677. Hydration callbacks, placeholder population, pinning and Explorer status integration remain open.

## 2. Remaining A0 gates

| Gate | Status | Required evidence to close |
|---|---|---|
| OpenAPI formal validation | **Passed** | GitHub Actions run #42370799202 |
| PostgreSQL V001 + V002 | **Passed** | Both migrations and smoke tests succeeded on PostgreSQL 18 |
| Ktor architecture spike | Partially validated | HTTP/auth, PKCE/state/redirect primitives, HikariCP/JDBC, PostgreSQL refresh-lease and outbox concurrency tests, KMS fail-closed/key-zeroization tests passed. Real provider code exchange, production KMS adapter, container image and production migration-runner behavior remain |
| Master Account auth/recovery | Provisional ADR | Passkey-first + offline recovery codes recommended; password fallback and email recovery policy require owner approval |
| Credential vault recovery | Architecture direction accepted; implementation open | Worker Secret-derived envelope wrapping; not HSM/KMS; recovery policy, secret rotation/offline copy and independent review remain |
| Provider OAuth | Recommended path; approval open | Google Drive first; backend HTTPS callback recommended. Full-library read (`drive.readonly` + `drive.file`) vs full edit (`drive`) needs scope approval and Google verification/assessment planning |
| E2E encryption | Open | Protocol proposal exists; recovery design approval, cross-platform test vectors and independent cryptographic review remain |
| Android platform | Provisional ADR | Minimum API 26 / prototype target API 36; release-time SDK policy and OEM matrix still require validation |
| Local data layer | Prototype in progress | Room checkpoint persistence, cleanup eligibility gate, WorkManager constraints and unique scheduling, Pigeon bridge and FlutterEngine plugin lifecycle source exist. Android CI Run #41 passed Room persistence/recovery, Pigeon, Kotlin bridge and synthetic WorkManager scheduling/Worker tests. A separate Flutter plugin now implements read-only SAF root selection and child listing. Android app compilation passed on the previous native plugin integration commit; latest run #42383436463 includes saved-folder restoration tests and is pending. Live FlutterEngine↔Dart round-trip for transfer APIs, provider-session reconciliation, provider-aware Worker, process-death/reboot/OEM testing and Keystore integration remain |
| Windows platform | Prototype in progress | C++20 directory enumeration, safe rename/move/copy/recycle-bin operations and Cloud Files sync-root registration pass prior Windows CI. A Flutter plugin now adds user-selected root picking and read-only listing with canonical-root containment. The Windows C API registration convention was corrected after a CI compile failure; verification is pending in run #42383436463. ACL/path error mapping, Cloud Files callbacks/placeholders/hydration, pinning and supported shell integration remain |
| Hosting and operations | Platform direction accepted; implementation open | Firebase Spark + Cloudflare Workers + D1; no-card/no-custom-domain target; Worker API and D1 migration remain |
| Privacy and legal | Baseline drafted; approval open | Data inventory, consent, retention and subprocessor framework documented; jurisdiction, actual retention, public privacy policy and legal review remain |
| A1 backlog | Drafted; not started | Start only after A0 exit review |

## 3. Immediate execution order

1. Keep OpenAPI and PostgreSQL 18 contract checks green on every relevant change.
2. Preserve the validated V001/V002 baseline; future schema changes must use new ordered migrations and regression tests.
3. Finish the read-only local folder browsing slice and pass Android/Windows widget, native compilation and path/permission tests. Then run a manual smoke test on the Redmi device and Windows laptop; CI cannot substitute for real-device SAF/OEM behavior.
4. App-local folder bookmark restore, permission/drive recovery UI, in-folder search, sorting, hidden-file filtering and metadata display are implemented; continue with OS-native file open/preview and then safe copy/move/rename/recycle-bin operations with tests.
5. Add the Android transfer UI and prove live FlutterEngine↔Dart bridge behavior before wiring provider adapters.
6. Extend the backend OAuth exchange path with provider-specific validation and callback transaction binding; keep credentials out of logs and UI.
7. Implement Cloud Files API callback connection, placeholder population/hydration and Explorer status integration; registration alone is not a functioning cloud placeholder provider.
8. Implement and review Firebase auth, Worker/D1 migration, OAuth scopes/callback, credential-vault recovery, privacy/legal and E2E recovery; obtain independent security review before A0 exit. Do not start A1 before this review.

## 4. Non-negotiable implementation safety

- No plaintext provider refresh token, OAuth authorization code, PKCE verifier, Worker Secret material or E2E content key in source control, ordinary database fields, logs or telemetry.
- Refresh tokens remain in the consented backend vault. Short-lived access tokens are delivered only to the authenticated native provider adapter when needed and remain memory-only.
- E2E content keys remain client-controlled and separate from OAuth credentials.
- Provider accounts restore independently. A reauth challenge pauses only the affected account.
- Existing provider hierarchy is preserved; indexing never moves, renames or deletes originals.
- Upload or download success is not declared until verification policy passes.
- Local originals are never automatically deleted. Cleanup requires explicit user opt-in, successful verification, recoverable key metadata and OS permission.
- CI green, security approval and implementation are separate statuses; none may be inferred from a planning document.

## 5. A0 completion rule

A0 may be marked **COMPLETE** only when every required gate in section 2 has concrete evidence or an explicitly approved, documented deferral. Until then, the project remains in A0 and production implementation must not be represented as complete.


## Local file operations — current increment
- Added explicit create-folder and rename operations to the local file bridge and Files UI.
- Android SAF folder selection now requests persistable read/write grants; provider-specific unsupported operations are reported without fallback or data loss.
- Windows operations validate canonical paths remain inside the selected root, validate leaf names, and reject collisions before mutation.
- Verified file copy is implemented on Android SAF and Windows; SHA-256 read-back/source-stability checks and collision protection are in place. CI Run #40 (42392380319) passed Android and Windows analyze/test/compile jobs.
- A native one-level move-to-parent operation is implemented in the bridge/UI. Android calls DocumentsContract.moveDocument and refuses unsupported providers; Windows uses MoveFileW with no overwrite semantics. CI Run #41 (42393259097) passed Android and Windows jobs.
- Android now prefers provider-native Trash on API 37+ when the selected document advertises `FLAG_SUPPORTS_TRASH`; the app queries provider Trash and uses the native restore operation. If unavailable, it moves the item into a reserved `.AUREON Trash (AUREON)` folder inside the selected SAF root using `DocumentsContract.moveDocument`, with original-parent metadata stored locally. Restore and separately confirmed permanent deletion are exposed in an Android Trash screen. No automatic emptying or copy/delete fallback is used; unsupported providers preserve the source. CI Run #42397701586 passed Android and Windows contract tests, Flutter analyze/widget tests and platform compilation. This does not replace a live provider/device test; no artifacts were uploaded.
- Windows retains its native IFileOperation + FOFX_RECYCLEONDELETE Recycle Bin action with root containment checks and no permanent-delete fallback. The expanded Android/Windows Trash implementation passed CI Run #42397701586.


## Cross-device Trash metadata — contract/database foundation

- Added V003 trash_items for cloud-provider objects only, with user/account/device ownership constraints, provider-item foreign keys, idempotent operation IDs, optimistic row versions and one-active-Trash-record uniqueness.
- OpenAPI defines provider-backed Trash list/record/restore/purge metadata operations and includes trash_item in the sync change taxonomy. Clients must perform provider actions first and report only confirmed outcomes.
- Local SAF/Win32 items are deliberately excluded: device-specific tree URIs and filesystem paths cannot be restored safely on another device. Their Trash remains local until a provider-backed file model exists.
- Important boundary: the current Ktor runtime still exposes only health and authenticated /v1/me; these new Trash routes are contract/database groundwork, not yet a live service or app-connected sync. Master Account session issuance, provider adapter execution and route/repository integration remain prerequisites.


## Provider Trash sync implementation update (2026-11-07)

- Added authenticated Ktor route handlers for listing provider-backed Trash records, recording provider-confirmed Trash operations, and version-checked restore/permanent-delete metadata transitions. Repository methods are tenant-scoped and use operation IDs for idempotent create requests.
- Added a PostgreSQL repository implementation for the V003 `trash_items` table. It depends on V003 being applied; the current backend workflow still needs to include V003 and its smoke test before this repository is integration-tested against CI PostgreSQL.
- Added a Google Drive v3 native Trash adapter using the provider `trashed` flag, restore and guarded permanent delete. It accepts a short-lived access token from a future credential-broker integration and does not store or log it.
- Backend API and adapter are code prototypes only. They are not yet wired to the production session authenticator, credential broker, deployed backend or live provider OAuth. Provider operation receipt references are currently accepted by the API contract but not yet durably stored by the V003 schema/repository.
- Android/Windows app-side cross-device sync is not yet wired. Existing SAF/Win32 local Trash remains device-local. The client needs the real Master Account session, provider account inventory and authenticated API base URL before it can safely sync provider-backed Trash.
- Backend CI run #42401277217: Ktor tests passed and backend build passed; final job teardown/status was still in progress at last check. Adapter change run #42401338611 was still running. No APK/EXE artifacts were created.


### Cloud Trash sync client progress

- Added `app/lib/src/files/aureon_trash_sync_client.dart`: HTTPS-only authenticated transport contract, concrete Dart `HttpClient` adapter, provider-backed Trash list/create/restore/purge requests, provider-outcome-reference requirement, and HTTP 409 stale-state conflict mapping.
- Added Dart tests for authenticated listing, provider receipt requirement, HTTPS enforcement and no-session fail-closed behavior.
- This client is not yet wired into the Trash page because the app does not yet have a production Master Account session/token provider or deployed API base URL. It does not sync device-local SAF/Win32 Trash.


## Master Account session and provider Trash runtime wiring (2026-11-08)

- Added `PostgresSessionAuthenticator`: hashes opaque bearer tokens with SHA-256 and validates the hash against `sessions`, active user and active device rows, expiry and revocation on each request. It updates last-used time and never stores or logs the raw token.
- `Application.module()` now wires the PostgreSQL session authenticator and `PostgresTrashRepository` when `AUREON_DATABASE_URL`, `AUREON_DATABASE_USER` and `AUREON_DATABASE_PASSWORD` are supplied. Without DB configuration, authentication remains deny-all and readiness remains not-ready. The DB pool is closed on application shutdown.
- Added `ProviderAccessTokenBroker` as an isolated, fail-closed boundary. The default implementation deliberately refuses provider operations until a separate reviewed credential-broker workload is deployed. It must decrypt the user's consented refresh credential via managed KMS/HSM, refresh provider tokens, and expose only a short-lived access token within a scoped callback.
- Fixed Google Drive adapter URL interpolation so provider item IDs are URL-encoded and interpolated rather than sent as a literal placeholder.
- App Trash client supports an injected AUREON session-token provider and concrete HTTPS transport, but it is not yet mounted in the Files/Trash UI. The app still has no Master Account login/session lifecycle, and no deployed API base URL or credential-broker endpoint.
- Important: the current Trash record API accepts provider outcome references from an authenticated client. Before production enablement, move provider mutations behind a backend coordinator that obtains provider credentials from the isolated broker and records only backend-confirmed receipts; do not treat client-supplied receipt strings as proof of provider mutation.
- No production KMS/HSM integration, OAuth refresh implementation, provider operation coordinator, production deployment, or live Google Drive test has been completed. CI success proves compilation/schema tests only, not end-to-end cross-device sync.


## Backend runtime CI verification (2026-11-08)

- Latest backend runtime/session/provider-adapter correction run #42402686383 completed successfully. PostgreSQL migration + database smoke tests, backend tests and backend build all passed.
- This verifies the corrected Google Drive URL-encoded item-ID path and the fail-closed credential-broker boundary in CI. It does not prove a hosted deployment, live Google OAuth, cross-device Trash sync or real provider mutation.
- No Android APK or Windows EXE artifacts were created or uploaded.
- Next production-critical backend work remains: server-side provider Trash command coordinator, real credential broker with managed KMS/HSM, OAuth refresh/rotation and consented provider-account inventory. The current client-supplied provider outcome reference must not be accepted as proof of provider mutation in production.
- Owner-facing hosting decision and a no-purchase-until-approved deployment checklist are recorded in `docs/DEPLOYMENT-AND-OWNER-ACTIONS.md`.


## Zero-cost-first hosting and credential-vault decision (2026-11-08)

- Added ADR-0005: provider refresh credentials are encrypted client-side using per-account AES-256-GCM data keys wrapped by a user-held random recovery key. Backend stores opaque ciphertext only; no server-held plaintext master key and no KMS dependency in the free phase.
- New-device restore returns provider account inventory and encrypted vault data after Master Account login; the user enters the recovery key once to unlock provider credentials. Losing the recovery key requires relinking affected providers.
- Android Keystore / Windows OS-protected storage protect locally unlocked key material. E2E file-content keys remain in a separate key hierarchy.
- Updated deployment and runtime docs to distinguish free-tier staging from production. Neon Free can suspend at quota; Cloud Run free compute/request allowance does not make all network egress and related services free. No paid resource has been provisioned.
- Provider file bytes remain direct device-to-provider transfers; backend/database/KMS quotas must not cap file payload throughput. If metadata API/database is unavailable, persist jobs locally and resume metadata sync later.
- Bangladesh/VPN reliability cannot be guaranteed by any host. The design avoids backend file relay and requires real ISP/VPN route testing, resumable sessions, network-change recovery and provider Retry-After/backoff handling.
- No APK/EXE artifacts were generated or uploaded.


## Cloudflare/Firebase no-card platform decision (2026-11-08)

- Owner approved moving away from OCI signup because the available DBBL Nexus card cannot satisfy OCI's international payment-card verification.
- New platform direction: Firebase Authentication Spark (Email/Password + email verification; no SMS), Cloudflare Workers API, Cloudflare D1 metadata/encrypted-envelope store, and the initial `workers.dev` hostname (no purchased custom domain).
- Provider credential records will use AES-256-GCM envelopes with a per-vault DEK wrapped by a key derived from a Cloudflare Worker Secret. This is server-assisted recovery, **not HSM/KMS and not zero-knowledge**; a compromised Worker deployment/account may be able to decrypt credential vaults.
- Recovery must validate Firebase identity and verified email, enforce ownership, rate limits, one-time challenge, cooldown, notifications, audit and device/session revocation. Passkey or trusted-device step-up is preferred. Email-only recovery is a weaker fallback.
- E2E file-content keys remain client-controlled and separate; email recovery cannot decrypt file contents. File bytes remain direct device-to-provider transfers.
- Critical migration: the existing Ktor/PostgreSQL backend cannot run unchanged on Cloudflare Workers/D1. A TypeScript Worker API and D1 schema/migration/test suite must be built and validated before client cutover. Keep the existing backend prototype until parity and security tests pass.
- Worker Secret is not an HSM; maintain a protected offline emergency copy and versioned rotation/restore drills. Loss of both the Worker Secret and its emergency copy can make provider credentials unrecoverable.
- No cloud resource has been provisioned, no billing upgrade has been enabled, and no production deployment has occurred. This documentation decision is not implementation or deployment evidence.


## Independent dual-recovery owner requirement (2026-11-08)

- Owner clarified that AUREON must not be Cloudflare-dependent for provider credential vault recovery.
- ADR-0007 adds two independent DEK wrapping paths: owner-held random 256-bit Manual Recovery Key and Cloudflare Worker Secret-derived recovery key.
- The Manual Recovery Key works locally and is never sent to Cloudflare. Cloudflare recovery is the alternate route if the manual key is lost.
- A portable encrypted Recovery Bundle must be exportable and storable outside Cloudflare. The manual key alone cannot restore ciphertext that is unavailable; bundle freshness must be visible and stale imports reconciled safely.
- Both recovery paths are architecture requirements only; no dual-envelope code, bundle export/import, Worker recovery, or cloud deployment is implemented yet.
