# AUREON A0 — Readiness and Exit-Gate Tracker

**Last updated:** 2026-11-07  
**Overall status:** <strong>IN PROGRESS</strong> — Contract and database CI are green; Android and Windows native prototypes are progressing. Production security approval, live platform integration and owner-controlled deployment/provider decisions remain open.

This file is the operational A0 checklist. A document existing in GitHub is not the same as a decision being verified or code being implemented.

## 1. Work completed in the repository

- [A0 Owner Decisions](./A0-OWNER-DECISIONS.md) — remaining owner approvals and recommended defaults.
- [A0 Threat Model](./THREAT-MODEL.md) — STRIDE register, security invariants, separate credential-broker workload requirement and required test evidence.
- [Privacy and Data Governance Baseline](./PRIVACY-DATA-GOVERNANCE.md) — data inventory and policy framework; public policy/legal review remains open.
- [ADR-0002 Master Account Auth & Recovery](./adr/ADR-0002-MASTER-ACCOUNT-AUTH-RECOVERY.md) — passkey-first and offline recovery-code recommendation; owner approval pending.
- [ADR-0003 Android Local Data Boundary](./adr/ADR-0003-ANDROID-LOCAL-DATA-BOUNDARY.md) — Room/Pigeon recommendation; Android prototype pending.
- [ADR-0004 KMS, Hosting & Operations](./adr/ADR-0004-KMS-HOSTING-OPERATIONS.md) — managed KMS/HSM boundary; vendor and region intentionally undecided.
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
- A first read-only local-files slice is now implemented in `packages/aureon_local_files/` and connected to the Files screen: Android uses SAF tree selection with read-only persisted URI grants and DocumentsContract child enumeration; Windows uses IFileDialog plus std::filesystem enumeration and a canonical-root containment check. Dart contract tests pass. The native platform compile and widget integration tests are still being stabilized; this is not yet verified as a usable release feature.
- Windows C++20 directory enumeration passed CMake/CTest CI run #42375617817. Safe no-overwrite rename/move/copy plus path-traversal checks passed Windows CI run #42377088269. CNG SHA-256 source-stability and destination-integrity verification passed Windows CI run #42377313897. A Shell IFileOperation recycle-bin adapter explicitly requests recycle-on-delete and passed its disposable-file integration test in Windows CI run #42377449840. A Cloud Files API sync-root register/unregister adapter and disposable-directory integration test passed Windows CI run #42377658677. Hydration callbacks, placeholder population, pinning and Explorer status integration remain open.

## 2. Remaining A0 gates

| Gate | Status | Required evidence to close |
|---|---|---|
| OpenAPI formal validation | **Passed** | GitHub Actions run #42370799202 |
| PostgreSQL V001 + V002 | **Passed** | Both migrations and smoke tests succeeded on PostgreSQL 18 |
| Ktor architecture spike | Partially validated | HTTP/auth, PKCE/state/redirect primitives, HikariCP/JDBC, PostgreSQL refresh-lease and outbox concurrency tests, KMS fail-closed/key-zeroization tests passed. Real provider code exchange, production KMS adapter, container image and production migration-runner behavior remain |
| Master Account auth/recovery | Provisional ADR | Passkey-first + offline recovery codes recommended; password fallback and email recovery policy require owner approval |
| KMS/HSM | Architecture specified; deployment open | Separate credential-broker workload identity and KMS-only decrypt boundary specified; vendor/region, production IAM, rotation/destruction and independent review remain |
| Provider OAuth | Recommended path; approval open | Google Drive first; backend HTTPS callback recommended. Full-library read (`drive.readonly` + `drive.file`) vs full edit (`drive`) needs scope approval and Google verification/assessment planning |
| E2E encryption | Open | Protocol proposal exists; recovery design approval, cross-platform test vectors and independent cryptographic review remain |
| Android platform | Provisional ADR | Minimum API 26 / prototype target API 36; release-time SDK policy and OEM matrix still require validation |
| Local data layer | Prototype in progress | Room checkpoint persistence, cleanup eligibility gate, WorkManager constraints and unique scheduling, Pigeon bridge and FlutterEngine plugin lifecycle source exist. Android CI Run #41 passed Room persistence/recovery, Pigeon, Kotlin bridge and synthetic WorkManager scheduling/Worker tests. A separate Flutter plugin now implements read-only SAF root selection and child listing; its widget/native compile verification is in progress. Live FlutterEngine↔Dart round-trip for transfer APIs, provider-session reconciliation, provider-aware Worker, process-death/reboot/OEM testing, durable root bookmarks and Keystore integration remain |
| Windows platform | Prototype in progress | C++20 directory enumeration, safe rename/move/copy/recycle-bin operations and Cloud Files sync-root registration pass prior Windows CI. A Flutter plugin now adds user-selected root picking and read-only listing with canonical-root containment; its native plugin compile is pending. ACL/path error mapping, Cloud Files callbacks/placeholders/hydration, pinning and supported shell integration remain |
| Hosting and operations | Open ADR | Managed KMS/HSM and managed PostgreSQL required; provider, region, domain, email, backup policy and budget need owner decisions |
| Privacy and legal | Baseline drafted; approval open | Data inventory, consent, retention and subprocessor framework documented; jurisdiction, actual retention, public privacy policy and legal review remain |
| A1 backlog | Drafted; not started | Start only after A0 exit review |

## 3. Immediate execution order

1. Keep OpenAPI and PostgreSQL 18 contract checks green on every relevant change.
2. Preserve the validated V001/V002 baseline; future schema changes must use new ordered migrations and regression tests.
3. Finish the read-only local folder browsing slice and pass Android/Windows widget, native compilation and path/permission tests. Then run a manual smoke test on the Redmi device and Windows laptop; CI cannot substitute for real-device SAF/OEM behavior.
4. Persist device-specific folder bookmarks and add permission-revocation/reselection recovery. Then add file preview/open, metadata sorting/search and only later safe copy/move/rename/recycle-bin operations with tests.
5. Add the Android transfer UI and prove live FlutterEngine↔Dart bridge behavior before wiring provider adapters.
6. Extend the backend OAuth exchange path with provider-specific validation and callback transaction binding; keep credentials out of logs and UI.
7. Implement Cloud Files API callback connection, placeholder population/hydration and Explorer status integration; registration alone is not a functioning cloud placeholder provider.
8. Resolve Master Account auth/recovery, OAuth scopes/callback, KMS/hosting/cost, privacy/legal and E2E recovery decisions with the owner; obtain independent security review before A0 exit. Do not start A1 before this review.

## 4. Non-negotiable implementation safety

- No plaintext provider refresh token, OAuth authorization code, PKCE verifier, KMS key material or E2E content key in source control, ordinary database fields, logs or telemetry.
- Refresh tokens remain in the consented backend vault. Short-lived access tokens are delivered only to the authenticated native provider adapter when needed and remain memory-only.
- E2E content keys remain client-controlled and separate from OAuth credentials.
- Provider accounts restore independently. A reauth challenge pauses only the affected account.
- Existing provider hierarchy is preserved; indexing never moves, renames or deletes originals.
- Upload or download success is not declared until verification policy passes.
- Local originals are never automatically deleted. Cleanup requires explicit user opt-in, successful verification, recoverable key metadata and OS permission.
- CI green, security approval and implementation are separate statuses; none may be inferred from a planning document.

## 5. A0 completion rule

A0 may be marked **COMPLETE** only when every required gate in section 2 has concrete evidence or an explicitly approved, documented deferral. Until then, the project remains in A0 and production implementation must not be represented as complete.
