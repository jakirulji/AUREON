# ADR-0007 — Independent dual recovery for the provider credential vault

**Status:** Accepted owner requirement; implementation pending  
**Date:** 2026-11-08

## Decision summary

AUREON must not depend exclusively on Cloudflare or exclusively on a user-held key. The provider credential vault uses two independent ways to unwrap the same per-vault DEK:

- Manual Recovery Key: a random 256-bit key held by the owner, used locally on any compatible device to decrypt a portable encrypted Recovery Bundle. It is never sent to Cloudflare.
- Cloudflare recovery: a separate Worker Secret-derived wrapping key, used after Firebase identity verification and the recovery policy. It can recover the vault if the Manual Recovery Key is lost, while Cloudflare remains available.

The two wrapping keys are independent and produce separate wrapped-DEK envelopes. Neither is derived from the other.

## Manual Recovery Key export formats

AUREON must provide two deliberately different export formats:

### 1. Plain-text `.txt` export

- Export the exact random 256-bit Manual Recovery Key in a documented, checksummed, human-readable encoding (the encoding and checksum version must be fixed before implementation).
- The TXT file is plaintext. Anyone who obtains it can use the Manual Recovery Key with a matching encrypted Recovery Bundle. The UI must display a prominent warning before export and recommend offline storage in a physically secure location.
- Require recent device authentication and an explicit confirmation before writing or sharing the file. Never automatically upload it to AUREON, Cloudflare, analytics, logs or crash reports.
- Do not include provider credentials, DEK, Worker Secret, passphrase or plaintext vault data in this file.
- Offer a post-export verification step and clearly state that deleting the TXT file from a device does not guarantee secure erasure on flash storage or backups.

### 2. Password-encrypted `.key` export/import

- Provide an encrypted, portable `.key` container holding the Manual Recovery Key and only the non-secret metadata needed to validate its format and vault binding.
- The `.key` file must **not** be sufficient by itself to recover the key. Import requires a separate user-supplied encryption passphrase. The passphrase is not the AUREON account password and is never stored or transmitted.
- Derive the file-encryption key using Argon2id (version 1.3) with a fresh random salt and reviewed, versioned memory/time/parallelism parameters. Benchmark safe parameters on supported low/mid-range Android and Windows devices before fixing defaults. Do not use a fast hash or HKDF alone on a human-chosen passphrase.
- Encrypt the payload using AES-256-GCM with a fresh random 96-bit nonce. Authenticate the container header, format version, vault identifier, KDF parameters and algorithm identifiers as AAD. Reject wrong passphrases, tampering, unsupported versions, parameter abuse and vault/account mismatch before accepting the key.
- Use a documented binary container format with magic bytes, version, bounded lengths and strict parser limits. File extension is `.key`; extension alone is not a security boundary.
- Import flow: user selects/uploads the `.key` file, enters its passphrase locally, AUREON decrypts and validates it on-device, then uses the recovered Manual Recovery Key to open a separately available encrypted Recovery Bundle or cached encrypted vault snapshot. The passphrase and decrypted key must never be sent to a server.
- Allow the same `.key` file to be imported on Android and Windows. Publish cross-platform test vectors and verify byte-for-byte interoperability.
- Do not claim the `.key` file is safe if its passphrase is weak. Warn users to choose a long, unique passphrase and keep it separately from the USB drive/file.
- The encrypted `.key` file does not replace the encrypted Vault Recovery Bundle. The former protects the recovery key; the latter contains the encrypted vault ciphertext and wrapped-key envelopes.

## Recovery scenarios

| Situation | Expected path | Requirement |
|---|---|---|
| Cloudflare Worker/D1 unavailable | Manual key | User must have a current encrypted Recovery Bundle or a cached encrypted vault copy, plus the Manual Recovery Key or its imported `.key` file and passphrase |
| Manual Recovery Key lost | Cloudflare recovery | Firebase identity, verified email, step-up where available, cooldown, notification and audit |
| Worker Secret unavailable/lost | Manual key | Current encrypted Recovery Bundle and Manual Recovery Key must exist |
| `.key` file stolen without passphrase | No direct unlock | Argon2id-protected encrypted key container; security still depends on passphrase strength |
| `.key` file and passphrase both stolen | Manual path compromised | Revoke/rotate the Manual Recovery Key and rewrap the vault through a verified recovery process |
| Manual key lost and Cloudflare unavailable | No guaranteed recovery | Restore Cloudflare first or relink providers if recovery data cannot be obtained |
| Both recovery paths lost | Relink | Never claim an impossible cryptographic recovery |
| Recovery Bundle stale | Manual key opens that snapshot | Show timestamp; reconcile token versions and account inventory when backend returns |

## Portable encrypted Recovery Bundle

The bundle contains only encrypted vault records, wrapped-DEK envelopes, non-secret metadata, schema/algorithm versions and integrity/authentication data. It must never contain the Manual Recovery Key, Worker Secret, plaintext DEK, provider refresh tokens or access tokens.

The owner can export the bundle and store it outside Cloudflare (for example, an independent cloud provider or offline media). AUREON also caches encrypted vault snapshots on authorized devices. A bundle stored only in D1 does not provide Cloudflare-outage independence.

The bundle is versioned, account/vault-bound, integrity-checked and protected against tampering and downgrade. Its export timestamp and freshness are visible. Manual recovery of a stale snapshot may omit recently linked accounts or provider token rotations; it must never silently overwrite newer state.

## Security requirements

- Generate a cryptographically random 256-bit Manual Recovery Key. Never use a human-chosen password as the root.
- Derive the manual wrapping KEK with HKDF-SHA-256 and a unique salt/domain-separation label; encrypt the DEK with AES-256-GCM.
- Cloudflare uses a different high-entropy Worker Secret and independent salt/domain-separation label to wrap the same DEK into a separate envelope.
- Use unique nonces and authenticated metadata; use vetted cryptographic libraries/platform APIs.
- The manual key never enters Worker APIs, logs, telemetry, analytics, crash reports or support bundles.
- Cloudflare recovery validates Firebase token signature/issuer/audience/expiry and verified email, derives owner UID from the token, applies rate limits, one-time challenge, step-up, cooldown, notification, device/session revocation and audit. The client generates an ephemeral device public key; after policy approval the Worker re-wraps the DEK to that device public key and returns only the device-bound envelope, never a plaintext DEK in an API response.
- Email-only recovery is a weaker fallback; prefer passkey or trusted-device step-up.
- Keep E2E file-content keys in a separate client-controlled hierarchy. Neither recovery path can decrypt file content.
- Zeroize in-memory passphrases, decrypted Manual Recovery Keys and temporary plaintext buffers as soon as practical; disable clipboard history where platform APIs permit, and never log them. Do not claim reliable secure deletion from flash storage.

## Required verification

1. Manual recovery on a clean device while Worker and D1 endpoints are deliberately blocked.
2. Cloudflare recovery after deleting the local/manual key copy in a test account.
3. Export/import TXT and encrypted `.key` files; verify wrong-passphrase, tamper, truncation, wrong-vault and unsupported-version rejection.
4. Verify `.key` import on Android then Windows and Windows then Android using identical published test vectors.
5. Import of a current bundle and a stale bundle, with clear freshness/reconciliation behavior.
6. Wrong key, tampered bundle, wrong account, schema downgrade and corrupted envelope rejection.
7. Worker Secret rotation and recovery after a simulated deployment/secret outage.
8. Ensure passphrase and decrypted Manual Recovery Key never appear in network captures, logs, telemetry, analytics, crash reports or temporary exported artifacts.
9. Independent cryptographic/security review before production use.

## Availability limitation

The Manual Recovery Key alone cannot reconstruct encrypted vault ciphertext that is no longer available. The encrypted `.key` file protects only the Manual Recovery Key; it does not contain the vault. Cloudflare outage independence therefore requires a portable Recovery Bundle or a cached encrypted vault copy, stored outside Cloudflare. No system can guarantee recovery if both key paths and all ciphertext copies are lost.
