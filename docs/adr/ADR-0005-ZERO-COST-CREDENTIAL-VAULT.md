# ADR-0005 — Zero-cost credential vault with server-assisted recovery

**Status:** Accepted owner direction; dual recovery clarified by ADR-0007; implementation and security review pending  
**Date:** 2026-11-08

## Context

The owner requires a no-payment-card platform and wants cross-device restoration of linked cloud-provider credentials. The owner explicitly requires two independent recovery paths: user-held manual recovery material that remains usable if Cloudflare is unavailable, and a Cloudflare-assisted recovery path if all manual keys are lost.

## Decision

- Firebase Authentication Spark is the Master Account identity provider, using email/password and verified email. SMS is out of scope.
- Cloudflare Workers is the API and server-assisted credential-vault recovery runtime; Cloudflare D1 stores metadata and encrypted vault envelopes.
- Provider credential records use AES-256-GCM with a random per-vault DEK.
- The same DEK is wrapped independently through two recovery paths:
  1. **Manual path:** generate five independent random 256-bit Manual Recovery Keys. Any one active key derives its own manual KEK using HKDF-SHA-256 and a unique per-key/per-vault salt. Each key gets its own DEK-wrapping envelope. The five keys are exported together in one plaintext `AUREON-Recovery-Keys.txt` file and in one password-encrypted `AUREON-Recovery.key` file. The TXT contains plaintext keys and requires explicit warning; the .key file contains all five keys encrypted with an Argon2id-derived key and AES-256-GCM. The .key passphrase is local-only and is never stored or transmitted.
  2. **Cloudflare path:** a distinct high-entropy Worker Secret-derived KEK wraps the same DEK into a separate server envelope. The Worker may unwrap only after authenticated recovery policy checks. This is not KMS/HSM and is not zero-knowledge.
- The five manual keys and Cloudflare wrapping hierarchy are cryptographically independent. Never derive one from another, store raw keys in D1, or use a Manual Recovery Key as a Worker Secret.
- Any one valid manual key can recover the credential vault locally when an encrypted Recovery Bundle or cached encrypted vault snapshot is available. All five keys are not required together.
- If one manual key is lost, another active key can be used to rotate/revoke it. If all five are lost, Cloudflare recovery may be used while its identity, Worker Secret, D1 envelope and recovery service remain available.
- Revoking a key must account for old portable bundles. For suspected compromise, rotate the vault DEK, re-encrypt credential records, advance the vault generation and rewrap remaining/new recovery slots; simply deleting a key slot from the current database is insufficient.
- The client can decrypt the credential vault locally after manual-key recovery and use provider refresh tokens directly with official provider OAuth/token endpoints where provider policy and native client security permit. Do not require a live Worker decrypt call after a successful manual recovery.
- Cloudflare recovery validates Firebase identity and applies recent reauthentication, step-up where available, cooldown, notification, audit, device/session revocation and rate limits.
- E2E file-content keys remain in a separate client-controlled hierarchy. Neither credential-vault recovery path may decrypt E2E file content.
- File bytes continue to flow directly between device and provider APIs; they must not pass through Workers or D1 in the normal transfer path.

## Manual key file portability

The owner-facing format is exactly two recovery-key export files:
- One plaintext TXT file containing all five independently generated Recovery Keys, with labels/IDs and checksums.
- One encrypted `.key` file containing the same five keys, protected by a separate user-supplied passphrase using Argon2id and AES-256-GCM.

Importing the single .key file decrypts the five keys locally; any one active key can then unlock a separately available encrypted Vault Recovery Bundle. The .key file does not contain the vault ciphertext. The TXT file is plaintext and must be handled as highly sensitive material. Android and Windows must share the same versioned format and cross-platform test vectors. Full export, import, rotation and revocation requirements are in ADR-0007.

## Manual recovery bundle and Cloudflare independence

- Provide an encrypted, portable Vault Recovery Bundle export/import. It contains the encrypted credential-vault records, five manual wrapped-DEK envelopes, the Cloudflare wrapped-DEK envelope, salts/nonces, algorithm and schema versions, key-version identifiers, and non-secret account/provider identifiers required to interpret the bundle.
- The bundle must not contain any of the five Manual Recovery Keys, Worker Secret, plaintext DEK, provider refresh tokens or access tokens.
- A bundle must be authenticated, versioned, integrity checked and bound to the AUREON account/vault ID. Import must reject tampering, downgrade, wrong-owner and unsupported-schema cases.
- The bundle can be stored by the owner outside Cloudflare (for example, an encrypted file in an independent storage location or offline media). AUREON must not assume that a bundle stored only in D1 remains available during a Cloudflare outage.
- Cache the latest encrypted vault envelope locally on each authorized device. Keep local copies protected by Android Keystore or Windows DPAPI/CNG.
- If Cloudflare Workers or D1 is unavailable, an owner with any one active Manual Recovery Key and a current Recovery Bundle can open the vault on another device without contacting Cloudflare. If the bundle is stale, it may not contain the latest provider-account additions or token rotations; show its export timestamp and require reconciliation when service returns.
- If Cloudflare is unavailable and no current bundle or other copy of encrypted vault data exists, manual keys alone cannot reconstruct missing ciphertext. Explain this limitation in the UI.
- If all Manual Recovery Keys are lost, the Cloudflare path can recover only while the Worker Secret, D1 envelope, identity service and recovery policy remain available.
- If the Worker Secret and its protected offline emergency copy are lost, the Cloudflare path is unavailable. Any one active Manual Recovery Key plus a current Recovery Bundle remains the independent recovery route.
- If both recovery paths are lost, or the encrypted vault data itself is unavailable, affected provider accounts must be relinked.

## Cryptographic requirements

1. Generate a random per-vault DEK using platform/vetted cryptographic APIs.
2. Encrypt each credential record with AES-256-GCM, fresh random 96-bit nonce per encryption under a given key, and AAD binding vault ID, owner UID, provider account ID, credential version and schema version.
3. For each of the five manual keys, derive a separate KEK with HKDF-SHA-256 from that key, a unique random salt and explicit domain-separation label; wrap the same DEK with AES-256-GCM using a unique nonce.
4. Cloudflare wrapping: derive a separate KEK from a high-entropy Worker Secret with a different salt/domain-separation label; wrap the same DEK in a separate envelope with a unique nonce.
5. Do not use a human-chosen password as a manual root key. Each of the five keys is generated randomly. The .key file passphrase is only for encrypting the export container and must use Argon2id, not HKDF alone.
6. Display/export the five keys once per recovery-set generation, provide offline-storage guidance, then require a successful verification challenge before completing setup.
7. Do not send any Manual Recovery Key, manual KEK or plaintext DEK to Worker APIs, analytics, crash reports, logs or support bundles.
8. Version both wrapping paths independently. Rotation must preserve the ability to unwrap old envelopes until all vaults are safely rewrapped and verified; compromised key revocation requires a new vault generation and DEK re-encryption.
9. Add cross-platform deterministic test vectors and fuzz tests for envelope parsing, AAD mismatch, nonce handling, tampering, wrong-key, downgrade and import/export.
10. Never hand-roll cryptographic primitives. Independent cryptographic review is mandatory before production use.

## Cloudflare security and recovery policy

- Validate Firebase ID tokens (signature, issuer, audience, expiry); derive owner UID from verified token, never client-supplied UID.
- Require verified email, recent reauthentication and one-time challenge for recovery. Prefer passkey or an already trusted device as step-up. If email-only fallback is offered, clearly label it weaker and apply a longer cooldown.
- Notify existing devices and the account email, rate-limit attempts, audit without secrets, revoke lost sessions/devices and fail closed if audit persistence fails.
- Do not expose a generic decrypt endpoint. Restrict unwrap to broker operations tied to a user, vault and approved purpose.
- Worker Secret is not HSM/KMS. A compromised Worker deployment/account may be able to unwrap server envelopes and access provider credentials.

## Consequences

**Benefits**
- Cloudflare outage does not prevent manual recovery when the encrypted bundle is available.
- Loss of all Manual Recovery Keys does not automatically require provider relinking if the Cloudflare recovery path remains healthy.
- Database-only compromise does not expose provider credentials without either recovery authority.
- E2E file-content keys remain separate and client-controlled.

**Limitations**
- Manual Recovery Keys without encrypted vault ciphertext are insufficient. Keep an up-to-date encrypted Recovery Bundle outside Cloudflare.
- Cloudflare recovery is not hardware-backed and creates a server-side trust boundary.
- Email account compromise can undermine email-assisted recovery; step-up and cooldown reduce but do not eliminate this risk.
- Cloudflare Free quotas/outages can pause cloud-assisted recovery and metadata sync.
- No free-tier service guarantees permanent $0 operation or uninterrupted availability.

## Production gates

- Implement and test five independent manual wrapping envelopes, Cloudflare envelope and portable Recovery Bundle.
- Test manual recovery with Workers/D1 completely unreachable, using each of the five keys independently.
- Test Cloudflare recovery after all Manual Recovery Keys are unavailable.
- Test both export files, wrong passphrase, tampering, stale bundle behavior and cross-platform import.
- Test key revocation/rotation against old exported bundle copies and verify old generations are rejected after migration.
- Test Worker Secret rotation, loss, restore and offline emergency procedure.
- Complete independent cryptographic/security review and Android/Windows integration tests before production credentials are stored.
- No paid plan, paid domain, billing upgrade or other charge without explicit owner approval.
