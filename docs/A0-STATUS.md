# AUREON A0 — Readiness and Exit-Gate Tracker

**Last updated:** 2026-11-07  
**Overall status:** <strong>IN PROGRESS</strong> — OpenAPI, PostgreSQL 18 and the initial Ktor/KMS/refresh-lease spike tests are green; production security approval, Android prototype and owner-controlled deployment/provider decisions remain open.

This file is the operational A0 checklist. A document existing in GitHub is not the same as a decision being verified or code being implemented.

## 1. Work completed in the repository

- [A0 Threat Model](./THREAT-MODEL.md) — STRIDE register, security invariants, separate credential-broker workload requirement and required test evidence.
- [Privacy and Data Governance Baseline](./PRIVACY-DATA-GOVERNANCE.md) — data inventory and policy framework; public policy/legal review remains open.
- [ADR-0002 Master Account Auth & Recovery](./adr/ADR-0002-MASTER-ACCOUNT-AUTH-RECOVERY.md) — passkey-first and offline recovery-code recommendation; owner approval pending.
- [ADR-0003 Android Local Data Boundary](./adr/ADR-0003-ANDROID-LOCAL-DATA-BOUNDARY.md) — Room/Pigeon recommendation; Android prototype pending.
- [ADR-0004 KMS, Hosting & Operations](./adr/ADR-0004-KMS-HOSTING-OPERATIONS.md) — managed KMS/HSM boundary; vendor and region intentionally undecided.
- [A1 First Vertical-Slice Backlog](./A1-FIRST-VERTICAL-SLICE-BACKLOG.md) — drafted; starts only after A0 exit review.

- [ADR-0002 Master Account Auth & Recovery](./adr/ADR-0002-MASTER-ACCOUNT-AUTH-RECOVERY.md) — passkey-first and recovery-code recommendation; owner approval pending.
- [ADR-0003 Android Local Data Boundary](./adr/ADR-0003-ANDROID-LOCAL-DATA-BOUNDARY.md) — Room/Pigeon recommendation; Android prototype pending.
- [ADR-0004 KMS, Hosting & Operations](./adr/ADR-0004-KMS-HOSTING-OPERATIONS.md) — managed KMS/HSM boundary; vendor and region intentionally undecided.
- [A1 First Vertical-Slice Backlog](./A1-FIRST-VERTICAL-SLICE-BACKLOG.md) — drafted; starts only after A0 exit review.

| Area | Artifact | Current evidence |
|---|---|---|
| Product requirements | [AUREON Plan](./AUREON-PLAN.md) | Product scope and safety rules recorded |
| Architecture | [A0 Engineering Blueprint](./A0-ENGINEERING-BLUEPRINT.md) | Modular-monolith target and trust boundaries documented |
| Backend stack | [ADR-0001](./adr/ADR-0001-BACKEND-STACK.md) | Ktor 3.6.1 / Kotlin 2.4.21 / JDK 21 scaffold, auth seam, fake-KMS fail-closed tests and refresh-lease CAS model tests passed in CI run #42370500985 |
| Data model | [DATA-MODEL](./DATA-MODEL.md) | V001/V002 entities and ownership invariants documented |
| Database schema | [V001](./migrations/V001__initial_schema.sql), [V002](./migrations/V002__vault-and-provider-inventory.sql) | Additive SQL drafts committed |
| Database tests | [V001 smoke](../tests/database/V001_schema_smoke.sql), [V002 smoke](../tests/database/V002_vault_inventory_smoke.sql) | Both smoke-test suites passed in GitHub Actions run #42370296201 on PostgreSQL 18 |
| API | [OpenAPI v1](./openapi/v1.yaml) | OAuth vault, short-lived native access-token broker, provider inventory and album contracts added; structural review found no duplicate paths/operation IDs and no unresolved component references |
| OAuth | [Provider OAuth Matrix](./PROVIDER-OAUTH-MATRIX.md), [Android OAuth lifecycle](./ANDROID-NATIVE-OAUTH-AND-CREDENTIAL-LIFECYCLE.md) | Backend refresh-token vault target, native access-token boundary, consent and refresh concurrency documented |
| Existing cloud content | [Cloud Restore and Legacy Import](./CLOUD-ACCOUNT-RESTORE-AND-LEGACY-IMPORT.md) | Drive hierarchy, metadata-first inventory, virtual categories and Photos album constraints documented |
| E2E encryption | [E2E Encryption and Recovery](./E2E-ENCRYPTION-AND-RECOVERY-DESIGN.md) | Proposal exists; independent crypto review and test vectors remain |
| CI | [Contract checks workflow](../.github/workflows/aureon-contract-checks.yml) | Run #42370296201 passed: OpenAPI formal validation and PostgreSQL 18 V001+V002 migration plus both smoke tests. Backend run #42370500985 passed build and tests. Dependabot enabled for Gradle and Actions updates. |

## 2. Remaining A0 gates

| Gate | Status | Required evidence to close |
|---|---|---|
| OpenAPI formal validation | **Passed** | GitHub Actions run #42370296201, validator step succeeded |
| PostgreSQL V001 + V002 | **Passed** | GitHub Actions run #42370296201: both migrations and both smoke tests succeeded on PostgreSQL 18 |
| Ktor architecture spike | Partially validated | Liveness + deny-all auth seam and HTTP tests passed. Fake-KMS fail-closed/key-zeroization and in-memory refresh-lease race/stale-commit tests passed. Real PostgreSQL repository/transaction, OAuth exchange, outbox and container tests remain |
| Master Account auth/recovery | Provisional ADR | Passkey-first + offline recovery codes recommended; password fallback and email recovery policy require owner approval |
| KMS/HSM | Architecture specified; deployment open | Separate credential-broker workload identity and KMS-only decrypt boundary specified; vendor/region, production IAM, rotation/destruction and independent review remain |
| Provider OAuth | Recommended path; approval open | Google Drive first; backend HTTPS callback recommended. Full-library read (`drive.readonly` + `drive.file`) vs full edit (`drive`) needs scope approval and Google verification/assessment planning |
| E2E encryption | Open | Protocol proposal exists; approve recovery design, cross-platform test vectors and independent cryptographic review |
| Android platform | Provisional ADR | Minimum API 26 / target API 37 recommended; release-time SDK policy and OEM matrix still require validation |
| Local data layer | Recommended ADR | Room owned by Kotlin + Pigeon typed Flutter boundary; Room/WorkManager/process-death prototype remains |
| Hosting and operations | Open ADR | Managed KMS/HSM and managed PostgreSQL required; provider, region, domain, email, backup policy and budget need owner decisions |
| Privacy and legal | Baseline drafted; approval open | Data inventory, consent, retention and subprocessor framework documented; jurisdiction, actual retention, public privacy policy and legal review remain |
| A1 backlog | Drafted | [First vertical-slice backlog](./A1-FIRST-VERTICAL-SLICE-BACKLOG.md) created; start only after A0 exit review |

## 3. Immediate execution order

1. Observe and resolve the OpenAPI/PostgreSQL CI run. Do not mark validation complete without the actual run and job evidence.
2. Review V001/V002 against PostgreSQL 18 behavior. If CI exposes an issue, add a new migration or amend V002 only while it remains unapplied; never rewrite V001.
3. Extend the Ktor spike with real PostgreSQL repository/transaction tests, OAuth exchange tests, outbox processing and container build.
4. Decide Master Account authentication/recovery, KMS deployment and first-provider OAuth scope/callback mode.
5. Obtain independent security review of the isolated credential broker, credential vault and E2E key recovery.
6. Complete the Android Room/Pigeon/WorkManager prototype, security reviews and operational decisions; then conduct the A0 exit review and start the [A1 vertical-slice backlog](./A1-FIRST-VERTICAL-SLICE-BACKLOG.md).

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
