# AUREON A0 — Readiness and Exit-Gate Tracker

**Last updated:** 2026-11-07  
**Overall status:** <strong>IN PROGRESS</strong> — documentation and contracts are being aligned; implementation has not started.

This file is the operational A0 checklist. A document existing in GitHub is not the same as a decision being verified or code being implemented.

## 1. Work completed in the repository

| Area | Artifact | Current evidence |
|---|---|---|
| Product requirements | [AUREON Plan](./AUREON-PLAN.md) | Product scope and safety rules recorded |
| Architecture | [A0 Engineering Blueprint](./A0-ENGINEERING-BLUEPRINT.md) | Modular-monolith target and trust boundaries documented |
| Backend stack | [ADR-0001](./adr/ADR-0001-BACKEND-STACK.md) | Kotlin 2.4.21 + Ktor 3.6.1 spike scaffold committed; CI result pending |
| Data model | [DATA-MODEL](./DATA-MODEL.md) | V001/V002 entities and ownership invariants documented |
| Database schema | [V001](./migrations/V001__initial_schema.sql), [V002](./migrations/V002__vault-and-provider-inventory.sql) | Additive SQL drafts committed |
| Database tests | [V001 smoke](../tests/database/V001_schema_smoke.sql), [V002 smoke](../tests/database/V002_vault_inventory_smoke.sql) | Constraint and isolation tests authored; execution not yet confirmed |
| API | [OpenAPI v1](./openapi/v1.yaml) | OAuth vault, short-lived native access-token broker, provider inventory and album contracts added; structural review found no duplicate paths/operation IDs and no unresolved component references |
| OAuth | [Provider OAuth Matrix](./PROVIDER-OAUTH-MATRIX.md), [Android OAuth lifecycle](./ANDROID-NATIVE-OAUTH-AND-CREDENTIAL-LIFECYCLE.md) | Backend refresh-token vault target, native access-token boundary, consent and refresh concurrency documented |
| Existing cloud content | [Cloud Restore and Legacy Import](./CLOUD-ACCOUNT-RESTORE-AND-LEGACY-IMPORT.md) | Drive hierarchy, metadata-first inventory, virtual categories and Photos album constraints documented |
| E2E encryption | [E2E Encryption and Recovery](./E2E-ENCRYPTION-AND-RECOVERY-DESIGN.md) | Proposal exists; independent crypto review and test vectors remain |
| CI | [Contract checks workflow](../.github/workflows/aureon-contract-checks.yml) | Workflow configured to validate OpenAPI and apply V001+V002 on PostgreSQL 18; successful run has not been observed |

## 2. Remaining A0 gates

| Gate | Status | Required evidence to close |
|---|---|---|
| OpenAPI formal validation | Pending | GitHub Actions run with OpenAPI validator conclusion = success |
| PostgreSQL V001 + V002 | Pending | CI run applies both migrations and both smoke tests pass on PostgreSQL 16 |
| Ktor architecture spike | In progress | Reproducible app, auth/device boundary, DB migrations, fake KMS, refresh concurrency, outbox and container tests |
| Master Account auth/recovery | Open | Choose passkey-first/password/email recovery and document account recovery threat model |
| KMS/HSM | Open | Select vendor/region, workload identity, envelope format, rotation/destruction, audit and incident response |
| Provider OAuth | Open | Select first provider callback mode, exact OAuth scopes, verification/assessment path and explicit consent UX |
| E2E encryption | Open | Approve protocol, recovery design, cross-platform test vectors and independent cryptographic review |
| Android platform | Open | Set minimum API, target API, device support matrix and background-work expectations |
| Local data layer | Open | Validate Room/Kotlin repository boundary versus Flutter database adapter; test process-death persistence |
| Hosting and operations | Open | Choose region/host, domain, email, backups, monitoring, support, cost ceiling and incident runbook |
| Privacy and legal | Open | Document provider data visibility, restricted-scope handling, retention, account deletion and privacy notice |
| A1 backlog | Pending | Break first vertical slice into small acceptance-tested work items |

## 3. Immediate execution order

1. Observe and resolve the OpenAPI/PostgreSQL CI run. Do not mark validation complete without the actual run and job evidence.
2. Review V001/V002 against PostgreSQL 16 behavior. If CI exposes an issue, add a new migration or amend V002 only while it remains unapplied; never rewrite V001.
3. Complete the Ktor proof-of-concept described in [ADR-0001](./adr/ADR-0001-BACKEND-STACK.md).
4. Decide Master Account authentication/recovery, KMS deployment and first-provider OAuth scope/callback mode.
5. Conduct security review of credential vault and E2E key recovery.
6. Close the A0 exit review and create the A1 vertical-slice backlog.

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
