# ADR-0005 — Zero-cost credential vault with server-assisted recovery

**Status:** Accepted owner direction; dual recovery clarified by ADR-0007; implementation and security review pending  
**Date:** 2026-11-08

## Context

The owner requires a no-payment-card platform and wants cross-device restoration of linked cloud-provider credentials. The owner explicitly requires two independent recovery paths: a manually held recovery key that remains usable if Cloudflare is unavailable, and a Cloudflare-assisted recovery path if the manual key is lost.

The earlier single Worker-Secret-wrapped design was too Cloudflare-dependent. A Worker outage alone should not prevent a user from opening a locally available or exported encrypted vault bundle with the manual key.

## Decision

- Firebase Authentication Spark is the Master Account identity provider, using email/password and verified email. SMS is out of scope.
- Cloudflare Workers is the API and server-assisted credential-vault recovery runtime; Cloudflare D1 stores metadata and encrypted vault envelopes.
- Provider credential records use AES-256-GCM with a random per-vault DEK.
- The same DEK is wrapped independently through two recovery paths:
  1. **Manual path:** a user-held high-entropy random 256-bit Manual Recovery Key derives a manual KEK using HKDF-SHA-256 and a per-vault random salt. The client wraps the DEK and stores the manual wrapped-DEK envelope with the encrypted vault. The Manual Recovery Key is never uploaded, transmitted to Cloudflare, or stored by AUREON.
  2. **Cloudflare path:** a distinct high-entropy Worker Secret-derived KEK wraps the same DEK into a separate server envelope. The Worker may unwrap only after authenticated recovery policy checks. This is not KMS/HSM and is not zero-knowledge.
- The two KEK hierarchies are cryptographically independent. Never derive one from the other, store either raw key in D1, or use the Manual Recovery Key as a Worker Secret.
- The client can decrypt the credential vault locally after manual-key recovery and use provider refresh tokens directly with official provider OAuth/token endpoints where provider policy and native client security permit. Do not require a live Worker decrypt call after a successful manual recovery.
- The Cloudflare path can restore the vault when the Manual Recovery Key is lost, subject to verified Firebase identity, recent reauthentication, step-up factor where available, cooldown, notification, audit, device/session revocation and rate limits.
- E2E file-content keys remain in a separate client-controlled hierarchy. Neither credential-vault recovery path may decrypt E2E file content.
- File bytes continue to flow directly between device and provider APIs; they must not pass through Workers or D1 in the normal transfer path.

## Manual recovery bundle and Cloudflare independence

- Provide an encrypted, portable Vault Recovery Bundle export/import. It contains the encrypted credential-vault records, both wrapped-DEK envelopes, salts/nonces, algorithm and schema versions, key-version identifiers, and non-secret account/provider identifiers required to interpret the bundle.
- The bundle must not contain the Manual Recovery Key, Worker Secret, plaintext DEK, provider refresh tokens or access tokens.
- A bundle must be authenticated, versioned, integrity checked and bound to the AUREON account/vault ID. Import must reject tampering, downgrade, wrong-owner and unsupported-schema cases.
- The bundle can be stored by the owner outside Cloudflare (for example, an encrypted file in an independent storage location or offline media). AUREON must not assume that a bundle stored only in D1 remains available during a Cloudflare outage.
- Cache the latest encrypted vault envelope locally on each authorized device. Keep local copies protected by Android Keystore or Windows DPAPI/CNG.
- If Cloudflare Workers or D1 is unavailable, an owner with the Manual Recovery Key and a current Recovery Bundle can open the vault on another device without contacting Cloudflare. If the bundle is stale, it may not contain the latest provider-account additions or token rotations; show its export timestamp and require reconciliation when service returns.
- If Cloudflare is unavailable and no current bundle or other copy of encrypted vault data exists, the Manual Recovery Key alone cannot reconstruct missing ciphertext. Explain this limitation in the UI.
- If the Manual Recovery Key is lost, the Cloudflare path can recover only while the Worker Secret, D1 envelope, identity service and recovery policy remain available.
- If the Worker Secret and its protected offline emergency copy are lost, the Cloudflare path is unavailable. The Manual Recovery Key plus a current Recovery Bundle remains the independent recovery route.
- If both recovery factors are lost, or the encrypted vault data itself is unavailable, affected provider accounts must be relinked.

## Cryptographic requirements

1. Generate a random per-vault DEK using platform/vetted cryptographic APIs.
2. Encrypt each credential record with AES-256-GCM, fresh random 96-bit nonce per encryption under a given key, and AAD binding vault ID, owner UID, provider account ID, credential version and schema version.
3. Manual wrapping: derive KEK with HKDF-SHA-256 from a random 256-bit Manual Recovery Key, unique random per-vault salt and explicit domain-separation label; wrap DEK with AES-256-GCM using a unique nonce.
4. Cloudflare wrapping: derive a separate KEK from a high-entropy Worker Secret with a different salt/domain-separation label; wrap the same DEK in a separate envelope with a unique nonce.
5. Use a vetted mnemonic/encoding only to display and transcribe the random Manual Recovery Key; do not use a human-chosen password as the root key. Show the key once, provide copy/export and offline-storage guidance, then require a successful verification challenge before completing setup.
6. Do not send the Manual Recovery Key, manual KEK or plaintext DEK to Worker APIs, analytics, crash reports, logs or support bundles.
7. Version both wrapping paths independently. Rotation must preserve the ability to unwrap old envelopes until all vaults are safely rewrapped and verified.
8. Add cross-platform deterministic test vectors and fuzz tests for envelope parsing, AAD mismatch, nonce handling, tampering, wrong-key, downgrade and import/export.
9. Never hand-roll cryptographic primitives. Independent cryptographic review is mandatory before production use.

## Cloudflare security and recovery policy

- Validate Firebase ID tokens (signature, issuer, audience, expiry); derive owner UID from verified token, never client-supplied UID.
- Require verified email, recent reauthentication and one-time challenge for recovery. Prefer passkey or an already trusted device as step-up. If email-only fallback is offered, clearly label it weaker and apply a longer cooldown.
- Notify existing devices and the account email, rate-limit attempts, audit without secrets, revoke lost sessions/devices and fail closed if audit persistence fails.
- Do not expose a generic decrypt endpoint. Restrict unwrap to broker operations tied to a user, vault and approved purpose.
- Worker Secret is not HSM/KMS. A compromised Worker deployment/account may be able to unwrap server envelopes and access provider credentials.

## Consequences

**Benefits**
- Cloudflare outage does not prevent manual recovery when the encrypted bundle is available.
- Loss of the Manual Recovery Key does not automatically require provider relinking if the Cloudflare recovery path remains healthy.
- Database-only compromise does not expose provider credentials without either recovery authority.
- E2E file-content keys remain separate and client-controlled.

**Limitations**
- Manual Recovery Key without encrypted vault ciphertext is insufficient. Keep an up-to-date encrypted Recovery Bundle outside Cloudflare.
- Cloudflare recovery is not hardware-backed and creates a server-side trust boundary.
- Email account compromise can undermine email-assisted recovery; step-up and cooldown reduce but do not eliminate this risk.
- Cloudflare Free quotas/outages can pause cloud-assisted recovery and metadata sync.
- No free-tier service guarantees permanent $0 operation or uninterrupted availability.

## Production gates

- Implement and test both independent wrapping envelopes and the portable Recovery Bundle.
- Test manual recovery with Workers/D1 completely unreachable.
- Test Cloudflare recovery after the Manual Recovery Key is unavailable.
- Test stale bundle behavior and reconciliation after provider token rotation/account addition.
- Test Worker Secret rotation, loss, restore and offline emergency procedure.
- Complete independent cryptographic/security review and Android/Windows integration tests before production credentials are stored.
- No paid plan, paid domain, billing upgrade or other charge without explicit owner approval.
