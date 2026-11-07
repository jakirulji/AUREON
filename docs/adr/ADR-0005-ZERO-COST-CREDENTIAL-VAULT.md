# ADR-0005 — Zero-cost credential vault with server-assisted recovery

**Status:** Accepted owner direction for the personal, zero-cost-first phase; implementation and security review pending  
**Date:** 2026-11-08

## Context

The owner cannot use OCI signup because the available DBBL Nexus card is not an international Visa/Mastercard payment card. A no-payment-card onboarding path is required. The owner also wants to recover the provider credential vault on a new device after losing the user recovery key, using verified email as part of the recovery process.

The previous client-only design protected provider refresh credentials from the backend, but made recovery impossible if every copy of the user recovery key was lost. The newly accepted direction deliberately trades some server-side confidentiality for recoverability.

## Decision

For the personal zero-cost-first deployment candidate:

- Firebase Authentication Spark is the Master Account identity provider, using email/password and verified email. SMS is out of scope. No custom domain is required for the initial flow.
- Cloudflare Workers is the API and narrowly scoped credential-vault recovery runtime.
- Cloudflare D1 stores account metadata, provider inventory and encrypted credential-vault envelopes. It stores no plaintext provider refresh tokens or wrapping keys.
- A Cloudflare Worker Secret holds a high-entropy credential-vault wrapping root key. This is **not KMS/HSM**, is not an independently isolated hardware key, and is accessible to the deployed Worker runtime. A Worker compromise or malicious deployment with access to the secret can expose all credential vaults protected by that key.
- The Worker may unwrap a user's credential-vault data-encryption key only after authenticating the Firebase identity, checking verified email, enforcing the recovery policy and writing an audit event. The normal API surface must not expose a generic decrypt endpoint.
- Email verification initiates recovery; it is not proof against compromise of the user's email account. Require recent reauthentication, notify existing trusted devices/email, impose a recovery cooldown, and use a passkey or trusted device as an additional factor when available. Any email-only fallback must be explicitly disclosed as a weaker recovery path and rate-limited.
- Keep the existing random user recovery key as an optional offline emergency factor/backup where feasible, but losing it must not be the sole reason recovery fails under the approved server-assisted path.
- E2E file-content keys remain in a separate client-controlled hierarchy. They are never wrapped by the Worker Secret, sent to Workers, stored in D1 in plaintext, or recoverable through email-only credential-vault recovery.
- Provider refresh tokens remain encrypted at rest in D1. The Worker decrypts only inside the provider credential-broker path, refreshes provider credentials, and returns only a short-lived, least-scope access token to the authenticated native adapter when direct client-to-provider transfer requires it. Access tokens are memory-only and never logged.
- File bytes continue to flow directly between device and provider APIs; they must not pass through Workers or D1 in the normal transfer path.

## Envelope and recovery requirements

1. Generate a random per-vault data-encryption key (DEK) and encrypt provider credential records with AES-256-GCM, fresh random 96-bit nonce per key, and authenticated metadata binding vault ID, owner UID, provider account ID, credential version and schema version.
2. Wrap the per-vault DEK with a key-encryption key derived from the Worker Secret using HKDF-SHA-256 with a unique random per-vault salt and a domain-separation label. Store only the wrapped DEK, salt, nonce, key version ID and ciphertext in D1.
3. Keep the Worker Secret out of source control, D1, GitHub Actions, client apps, logs and analytics. Provision it only through Cloudflare's secret-management interface. Maintain an owner-controlled offline emergency copy under a separate secure storage procedure; never put it in the public repository or chat.
4. Version the wrapping key. Rotation must support decrypting old envelopes during a controlled migration; never delete the old secret/version until all records are rewrapped and recovery tests pass.
5. The Worker must validate Firebase ID tokens (signature, issuer, audience, expiry), require verified email for recovery, derive owner identity from the verified token (never a client-supplied UID), enforce per-user/account authorization and rate limits, and fail closed if audit persistence fails.
6. Recovery must have a short-lived one-time challenge, recent reauthentication, notifications, cooldown, revocation of lost devices/sessions, and audit trail. Do not send decrypted refresh tokens or DEKs to UI code.
7. Keep local device copies protected by Android Keystore or Windows DPAPI/CNG. A device with an already unlocked local vault should continue to work during a temporary Worker outage, subject to provider token expiry/revocation.
8. If the Worker Secret is lost, deleted, or unavailable and no valid offline emergency copy exists, affected provider credentials may be unrecoverable and must be relinked. D1 backups alone cannot replace the wrapping key.
9. Use vetted crypto libraries/platform APIs; never implement AES, HKDF or secure random manually. Add cross-platform test vectors and independent security review before production use.

## Security and availability consequences

**Benefits**
- No payment card or paid KMS is required to begin the proposed Firebase Spark + Cloudflare Free deployment.
- The owner can recover provider credential access on a new device without relying exclusively on the user-held recovery key.
- Database dumps contain encrypted credential envelopes, not plaintext refresh tokens.
- Provider file bytes remain direct device-to-provider transfers, independent of Workers/D1 payload bandwidth.

**Costs and limitations**
- This is not zero-knowledge provider credential storage: the Worker runtime has a narrowly intended but real ability to decrypt provider credentials.
- Worker Secret is not an HSM/KMS and does not provide hardware-backed key isolation or independent cryptographic authorization.
- A compromised Worker deployment, Cloudflare account or secret-management control plane can compromise the provider credential vault. Minimize Worker permissions, protect account MFA, review deployments and keep immutable audit records where possible.
- Firebase email verification alone is vulnerable if the email account is compromised. Cooldown and notification reduce risk but do not eliminate it.
- Cloudflare Free quotas, service availability and D1 limits can pause metadata/recovery operations. Local jobs and known-good files must remain safe while the control plane is unavailable.
- D1 is not PostgreSQL. Existing Ktor/PostgreSQL backend code and SQL migrations cannot be assumed to run unchanged on Workers/D1.
- No free-tier service guarantees permanent $0 operation, unlimited usage, or uninterrupted availability.

## Migration and production gates

- Build a TypeScript Worker API and D1 schema/migrations; preserve the existing public API semantics where practical.
- Port and test Master Account session validation, provider inventory, vault envelope storage, audit, credential broker and Trash coordination before switching clients.
- Verify Firebase token validation, account ownership isolation, recovery cooldown, secret rotation, Worker secret loss drill, D1 backup/export and restore procedure.
- Do not enable production credential recovery until independent security review and end-to-end Android/Windows tests pass.
- No paid plan, paid domain, billing upgrade, or other charge without explicit owner approval.
