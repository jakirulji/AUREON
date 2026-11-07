# ADR-0005 — Zero-cost-first credential vault and provider transfer

**Status:** Accepted engineering default for the no-paid-services phase  
**Date:** 2026-11-08

## Context

The owner requires a security-first design with no mandatory paid service. Managed KMS is not generally free: Google Cloud KMS's always-free cryptographic allowance applies only to keys created using Autokey, while ordinary software-protected key versions are billable. Free compute/database tiers also have hard limits, suspension behavior, and possible network/egress charges.

A backend-held master key in an environment variable, database, GitHub Actions secret, or Cloudflare Worker secret is not an equivalent replacement for managed KMS/HSM. It creates a concentrated decryption capability and weakens the credential-vault threat boundary.

## Decision

For the zero-cost-first phase, AUREON will use a **client-encrypted provider credential vault**. The backend stores and synchronizes opaque ciphertext only; it never receives the vault recovery key and cannot decrypt provider refresh credentials.

1. On first vault setup, the client generates a cryptographically random 256-bit recovery key. Show it once with checksum/verification and require the user to store it offline. Never transmit or log it.
2. Derive purpose-separated wrapping keys using HKDF-SHA-256 from the random recovery key and a per-vault random salt. Do not use a human password directly as an encryption key.
3. Generate independent random per-account data-encryption keys. Encrypt each provider refresh-token record with AES-256-GCM using a fresh 96-bit nonce and authenticated metadata (vault ID, provider, account ID, credential version, schema version). Wrap each per-account key with the vault wrapping key.
4. Store only ciphertext, wrapped per-account key, nonce, salt, algorithm/schema version and non-secret account metadata on the server. Never store the recovery key or plaintext refresh/access token.
5. After Master Account sign-in on a new device, restore account inventory and encrypted vault blobs. Ask for the recovery key once to unlock the vault on that device. Store only a locally protected copy using Android Keystore or Windows DPAPI/CNG-backed protection.
6. Refresh provider credentials in the native client/provider adapter. Keep access tokens memory-only. Persist rotated refresh-token ciphertext using compare-and-swap credential versions; reconcile concurrent device updates and provider rotation before retrying.
7. If the recovery key is lost, AUREON cannot decrypt the vault. The user must relink affected provider accounts. Do not add a hidden server recovery key or support override.
8. Keep E2E file-content keys in a separate client-controlled hierarchy. Provider OAuth credentials and file-content keys must never share a wrapping key or recovery secret.
9. Do not expose production restore, Trash mutation or destructive provider operations until authenticated provider execution, ownership checks, receipts and recovery behavior are implemented and tested.

## Cryptographic and implementation requirements

- Use vetted platform/library implementations; never implement AES, HKDF, secure random generation or key comparison manually.
- Use AES-256-GCM with unique random nonce per key; reject nonce reuse and malformed/authentication-failed records.
- Use constant-time verification where applicable; clear sensitive buffers as far as the platform permits.
- Bind provider/account/version metadata as AEAD additional authenticated data to prevent ciphertext swapping between accounts.
- Add versioned envelopes and migration tests before changing algorithms or metadata.
- Never put tokens, recovery keys, decrypted envelopes or upload-session bearer URLs in logs, analytics, crash reports, clipboard history or support bundles.
- A missing/invalid recovery key, corrupt ciphertext, failed authentication or unsupported schema must fail closed. Preserve encrypted blobs and local source files.
- Apply rate limits, account ownership checks, device revocation, and optimistic concurrency on vault update APIs.
- Do not claim the backend credential vault is protected by KMS in this phase: it is client-side encryption with a user-held recovery secret.

## Consequences and trade-offs

**Benefits**
- No KMS bill or server-side master decryption key is required.
- A database dump alone does not reveal provider refresh tokens.
- Provider file bytes remain direct client-to-provider; API host bandwidth and region do not constrain file upload throughput.
- The design works with a replaceable backend/database and does not lock AUREON into a KMS vendor.

**Costs / limitations**
- A new device requires the recovery key once after Master Account login.
- Losing the recovery key means relinking provider accounts; there is intentionally no server-side recovery bypass.
- A compromised/unlocked endpoint can access provider credentials while the vault is unlocked.
- Cross-device concurrent refresh-token rotation needs careful conflict reconciliation.
- This design is not a substitute for an independent cryptographic review.

## Future migration

If the owner later approves a paid managed KMS/HSM service, AUREON may add an isolated credential broker and offer a separately consented server-assisted vault mode. It must not silently migrate or weaken the client-encrypted vault. The file-content E2E key hierarchy remains client-controlled.

## Acceptance tests

- Backend/database inspection proves no recovery key or plaintext provider token is persisted.
- Wrong key, modified ciphertext, nonce/tag corruption, account-ID swap and schema downgrade all fail closed.
- Android and Windows produce mutually decryptable versioned test vectors.
- New device restores encrypted inventory and unlocks only after recovery-key entry.
- Concurrent refresh updates cannot overwrite a newer credential version.
- Provider auth failure pauses only the affected account and never deletes local originals.
- Logs, traces and crash paths are tested for token/key redaction.
