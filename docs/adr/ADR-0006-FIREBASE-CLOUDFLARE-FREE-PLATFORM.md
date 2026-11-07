# ADR-0006 — Firebase Authentication and Cloudflare Workers/D1 platform

**Status:** Accepted platform direction for personal zero-cost-first deployment; migration pending  
**Date:** 2026-11-08

## Context

OCI account creation requires a payment-card verification method that the owner's current DBBL Nexus card cannot satisfy. The owner wants to avoid obtaining a new international card solely for AUREON, avoid SMS verification and avoid purchasing a custom domain.

The existing backend prototype uses Ktor and PostgreSQL. It is not compatible with Cloudflare Workers/D1 without a deliberate port and schema redesign.

## Decision

Use the following initial platform direction:

- Firebase Authentication Spark for Master Account Email/Password sign-in and email verification. SMS verification is excluded.
- Cloudflare Workers for the public API and isolated credential-broker code path.
- Cloudflare D1 for metadata, provider inventory, encrypted credential envelopes, recovery challenges and audit metadata.
- Cloudflare's default `workers.dev` hostname initially; no custom domain purchase.
- Cloudflare Worker Secrets for the provider credential-vault wrapping root, as specified in ADR-0005. Worker Secrets are not KMS/HSM.
- Direct client-to-provider file transfer. Do not relay file payloads through Workers or D1.

## Migration constraints

1. Implement the Worker in TypeScript and define D1 schema/migrations. Do not attempt to run the Ktor JVM application inside Workers.
2. D1 is not PostgreSQL. Rework SQL, transaction boundaries, concurrency control, indexes, migrations and tests for D1 semantics.
3. Preserve API behavior where practical, but update OpenAPI/contracts for any intentional changes.
4. Validate Firebase ID tokens using supported JWT/JWKS verification, including signature, issuer, audience, expiry and verified-email policy. Derive owner UID from the token, never from request input.
5. Implement per-user data isolation, device/session lifecycle, rate limiting, audit and recovery cooldown before exposing credential recovery.
6. Keep the existing Ktor/PostgreSQL implementation until the Worker/D1 version passes contract, migration, security and integration tests. Do not delete the prototype prematurely.
7. Add tests for D1 consistency/transaction behavior, concurrent credential updates, Worker Secret rotation, secret loss, D1 export/restore and provider token refresh.
8. No production cutover until Android and Windows clients can use the new API and an independent security review is complete.

## Consequences

**Benefits**
- No international payment card is required for the selected Firebase Spark + Cloudflare Free onboarding path.
- No SMS verification or purchased custom domain is required for the initial setup.
- Free-tier quotas are suitable for a small personal prototype if usage stays within limits.

**Costs and limitations**
- Free tiers have hard quotas and no guarantee of permanent $0 cost or uninterrupted availability.
- Worker Secret is not a hardware security module. The Worker runtime can access it; a compromised deployment/account may compromise the provider credential vault.
- D1 has different capabilities and limits from PostgreSQL. The backend must be ported and thoroughly retested.
- Email verification alone is weaker than passkey/trusted-device recovery.
- The platform choice is not evidence that any cloud account, Worker, D1 database or Firebase project has been created or deployed.

## Rejected for this phase

- OCI signup requiring a payment card the owner does not have.
- Paid managed KMS/HSM or paid hosting.
- SMS verification.
- Custom domain purchase.
- Sending provider file bytes through the backend.
