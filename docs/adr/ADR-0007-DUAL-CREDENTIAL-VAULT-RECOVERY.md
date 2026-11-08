# ADR-0007 — Independent dual recovery for the provider credential vault

**Status:** Accepted owner requirement; implementation pending  
**Date:** 2026-11-08

## Decision summary

AUREON must not depend exclusively on Cloudflare or exclusively on user-held recovery material. The provider credential vault uses two independent recovery paths:

- **Manual recovery:** five independently generated, high-entropy Recovery Keys. Any one valid, active key can unwrap the same per-vault DEK locally on a compatible device. All five keys are exported together in one plaintext TXT file and, separately, in one password-encrypted `.key` file.
- **Cloudflare recovery:** a separate Worker Secret-derived wrapping key, used after Firebase identity verification and the recovery policy. It can recover the vault if all manual keys are unavailable, while Cloudflare remains available.

The five manual keys are independent random secrets, not five fragments of one secret and not a threshold/Shamir scheme. Each has a distinct key ID and its own DEK-wrapping envelope. The five wrapping keys and Cloudflare wrapping key are independent; none is derived from another.

## Manual Recovery Key export formats

AUREON must generate exactly five independent random 256-bit Manual Recovery Keys per recovery set. Each key is separately registered as an active recovery slot capable of unwrapping the same per-vault DEK.

### 1. One plaintext TXT file containing all five keys

- Export all five keys together in one human-readable file named `AUREON-Recovery-Keys.txt` (or a versioned equivalent).
- Include a clear key label/ID for each entry, encoding/version information, and per-key checksum to detect transcription errors. The file contains exactly five active recovery keys from the current recovery set.
- The TXT file is plaintext. Anyone who obtains it can use any one listed active key with a matching encrypted Recovery Bundle. Display a prominent warning before export and recommend storing it offline in a physically secure location.
- Require recent device authentication and explicit confirmation before writing or sharing the file. Never automatically upload it to AUREON, Cloudflare, analytics, logs or crash reports.
- Do not include provider credentials, DEK, Worker Secret, .key passphrase or plaintext vault data.
- Provide a verification step that asks the user to confirm selected characters/words from the exported set without exposing keys to telemetry. Explain that deleting the TXT file does not guarantee secure erasure from flash storage or backups.

### 2. One password-encrypted .key file containing all five keys

- Export exactly one portable encrypted container, named `AUREON-Recovery.key` (or a versioned equivalent), containing all five Manual Recovery Keys plus only the non-secret metadata needed to validate format, vault binding, key IDs and recovery-set version.
- Import exactly one `.key` file. The user supplies a separate encryption passphrase locally. The file alone must not reveal any key. The passphrase is not the AUREON account password and is never stored or transmitted.
- Derive the file-encryption key using Argon2id (version 1.3) with a fresh random salt and reviewed, versioned memory/time/parallelism parameters. Benchmark safe parameters on supported low/mid-range Android and Windows devices before fixing defaults. Do not use a fast hash or HKDF alone on a human-chosen passphrase.
- Encrypt the payload using AES-256-GCM with a fresh random 96-bit nonce. Authenticate the container header, format version, vault identifier, KDF parameters, recovery-set version, key IDs and algorithm identifiers as AAD. Reject wrong passphrases, tampering, unsupported versions, parameter abuse and vault/account mismatch before accepting the keys.
- Use a documented binary container format with magic bytes, version, bounded lengths and strict parser limits. File extension is not a security boundary.
- Import flow: user selects the `.key` file, enters its passphrase locally, AUREON decrypts and validates all five keys on-device, then uses one selected active key to open a separately available encrypted Recovery Bundle or cached encrypted vault snapshot. The passphrase and decrypted keys must never be sent to a server.
- Allow the same single `.key` file to be imported on Android and Windows. Publish cross-platform test vectors and verify byte-for-byte interoperability.
- Warn users that security depends on passphrase strength. Recommend a long, unique passphrase stored separately from the USB drive and `.key` file.
- The encrypted `.key` file does not replace the encrypted Vault Recovery Bundle. The former protects all five recovery keys; the latter contains encrypted vault ciphertext and wrapped-key envelopes.

## Recovery behavior and key lifecycle

- Any one of the five active manual keys is sufficient for local recovery; all five are not required simultaneously.
- Each key has a unique ID and status. AUREON may record which key ID was used, but must never log the key or its derived KEK.
- Support replacing/revoking an individual lost key and generating a replacement while preserving other valid recovery slots.
- **Security caveat:** removing a key slot only from the current server copy does not revoke copies in old exported bundles. If a key is suspected compromised, rotate the vault DEK, re-encrypt the credential records, create fresh wrapping envelopes for the remaining/new recovery keys and Cloudflare path, advance the vault generation, and reject older generations after verified migration. Do not claim immediate revocation while old ciphertext generations remain accepted.
- Re-export both recovery files after a recovery-set change. Clearly show the export generation and last-export time; old TXT/.key files may contain revoked keys and must be securely taken out of use.

## Recovery scenarios

| Situation | Expected path | Requirement |
|---|---|---|
| Cloudflare Worker/D1 unavailable | Any one active manual key | User must have a current encrypted Recovery Bundle or cached encrypted vault copy, plus the TXT key or imported .key file and (for .key) its passphrase |
| One manual key lost | Another active manual key | Revoke/replace the lost key; regenerate both export files |
| All manual keys lost | Cloudflare recovery | Firebase identity, verified email, step-up where available, cooldown, notification and audit |
| Worker Secret unavailable/lost | Manual recovery | Current encrypted Recovery Bundle and at least one active manual key must exist |
| .key file stolen without passphrase | No direct unlock | Argon2id-protected encrypted key container; security still depends on passphrase strength |
| .key file and passphrase both stolen | Manual path compromised | Rotate vault generation/DEK and all affected envelopes; do not rely only on deleting a slot from the live database |
| All manual keys lost and Cloudflare unavailable | No guaranteed recovery | Restore Cloudflare first or relink providers if recovery data cannot be obtained |
| Recovery Bundle stale | Manual key opens that snapshot | Show timestamp/generation; reconcile token versions and account inventory when backend returns |

## Portable encrypted Recovery Bundle

The bundle contains only encrypted vault records, wrapped-DEK envelopes (five manual-key envelopes and one Cloudflare envelope), non-secret metadata, schema/algorithm versions and integrity/authentication data. It must never contain any of the five Manual Recovery Keys, Worker Secret, plaintext DEK, provider refresh tokens or access tokens.

The owner can export the bundle and store it outside Cloudflare (for example, an independent cloud provider or offline media). AUREON also caches encrypted vault snapshots on authorized devices. A bundle stored only in D1 does not provide Cloudflare-outage independence.

The bundle is versioned, account/vault-bound, integrity-checked and protected against tampering and downgrade. Its export timestamp and vault generation are visible. Manual recovery of a stale snapshot may omit recently linked accounts or provider token rotations; it must never silently overwrite newer state.

## Security requirements

- Generate five cryptographically random 256-bit Manual Recovery Keys. Never use human-chosen passwords as root keys.
- Derive each manual wrapping KEK with HKDF-SHA-256 using that key's unique salt and a distinct domain-separation label; encrypt the same DEK into a separate AES-256-GCM envelope for each key.
- Cloudflare uses a different high-entropy Worker Secret and independent salt/domain-separation label to wrap the same DEK into a separate envelope.
- Use unique nonces and authenticated metadata; use vetted cryptographic libraries/platform APIs.
- Manual keys never enter Worker APIs, logs, telemetry, analytics, crash reports or support bundles.
- Cloudflare recovery validates Firebase token signature/issuer/audience/expiry and verified email, derives owner UID from the token, applies rate limits, one-time challenge, step-up, cooldown, notification, device/session revocation and audit. The client generates an ephemeral device public key; after policy approval the Worker re-wraps the DEK to that device public key and returns only the device-bound envelope, never a plaintext DEK in an API response.
- Email-only recovery is a weaker fallback; prefer passkey or trusted-device step-up.
- Keep E2E file-content keys in a separate client-controlled hierarchy. Neither recovery path can decrypt file content.
- Zeroize in-memory passphrases, decrypted Manual Recovery Keys and temporary plaintext buffers as soon as practical; disable clipboard history where platform APIs permit, and never log them. Do not claim reliable secure deletion from flash storage.

## Cloudflare Worker foundation (2026-11-08)

A TypeScript Cloudflare Worker prototype now exists at `backend/cloudflare-worker/` with a D1 migration and validation workflow. It verifies Firebase RS256 ID tokens against Google's Secure Token JWK set, derives owner UID from the verified subject, requires verified email, and enforces a five-minute `auth_time` window for sensitive recovery routes. It supports Worker-Secret HKDF-SHA-256/AES-256-GCM DEK wrapping, encrypted snapshot storage with monotonic generation checks, single-use short-lived recovery challenges, a per-vault challenge throttle/cooldown, audit records, and P-256 ECDH/HKDF/AES-GCM device-bound DEK rewrapping.

This is a backend foundation, not an integrated recovery product. The Worker currently receives the DEK over authenticated TLS during initial envelope creation, so the Worker runtime can access it in memory; this trust boundary is explicit and is not zero-knowledge or HSM-backed. The Flutter client does not yet provision/sync the Cloudflare envelope or unwrap the device-bound response. Email notification, passkey/trusted-device step-up, Cloudflare WAF/IP rate limiting, provider OAuth broker/refresh, independent backup replication, and security review remain open. No production account, D1 database, Worker Secret or deployment has been provisioned.

## Required verification

1. Manual recovery on a clean device while Worker and D1 endpoints are deliberately blocked, using any one of the five keys.
2. Cloudflare recovery after all local/manual key copies are unavailable in a test account.
3. Export/import one TXT file containing five keys and one encrypted .key file containing the same five keys; verify wrong-passphrase, tamper, truncation, wrong-vault and unsupported-version rejection.
4. Verify .key import on Android then Windows and Windows then Android using identical published test vectors.
5. Verify each of the five keys independently unlocks the same valid vault generation; verify revoked keys and old generations fail after completed rotation.
6. Import of a current bundle and a stale bundle, with clear freshness/reconciliation behavior.
7. Wrong key, tampered bundle, wrong account, schema downgrade and corrupted envelope rejection.
8. Worker Secret rotation and recovery after a simulated deployment/secret outage.
9. Ensure passphrase and decrypted Manual Recovery Keys never appear in network captures, logs, telemetry, analytics, crash reports or temporary exported artifacts.
10. Independent cryptographic/security review before production use.

## Availability limitation

Any manual key alone cannot reconstruct encrypted vault ciphertext that is no longer available. The encrypted `.key` file protects all five Manual Recovery Keys; it does not contain the vault. Cloudflare outage independence therefore requires a portable Recovery Bundle or a cached encrypted vault copy, stored outside Cloudflare. No system can guarantee recovery if all active key paths and all ciphertext copies are lost.


## Disaster recovery after all manual keys are lost

Losing all five Manual Recovery Keys and the `.key` export must not make the user's original cloud files inaccessible. AUREON must provide a separate **provider re-link and re-index** path:

- The user can authorize each cloud provider again through its official OAuth flow, including provider MFA where required. AUREON never requests provider passwords or bypasses MFA.
- Provider identity must be matched by stable provider subject/account ID after successful authorization, not by email/display-name similarity alone.
- AUREON rebuilds the file inventory from provider APIs using paginated metadata-first scans, preserving provider object IDs and actual parent relationships. This reconstructs the provider's original folder tree and current file list without moving, renaming, duplicating or deleting originals.
- This path restores access to files that remain in the provider account. It does not recover provider objects that the user/provider has permanently deleted, nor does it restore encrypted file contents if their separate E2E content keys have been lost.
- AUREON-specific organization (user tags, favorites, virtual collections, custom organization, sync preferences and related settings) must be backed up independently of the credential vault and all five manual keys. Use a separate versioned, integrity-protected metadata backup and separate client-controlled metadata key hierarchy. Never reuse the credential-vault DEK, Manual Recovery Keys, `.key` passphrase or E2E file-content keys.
- Store an encrypted metadata snapshot outside the Cloudflare-only failure domain and cache one on authorized devices. Use stable provider account subject + provider object ID for reconciliation. Metadata restore is a merge, never a blind overwrite of provider truth.
- Do not back up device-specific SAF URIs, Windows paths, local folder handles or OS permission grants as portable state; the user must reselect/re-authorize local folders on each device.
- If the metadata backup is missing, re-link and re-index still restores current provider files and original provider hierarchy, but AUREON cannot guarantee restoration of AUREON-only tags, favorites, virtual collections or custom settings that existed only in the lost metadata.
- Provider OAuth re-link is independent of manual recovery. If the user also loses access to the provider's own account, AUREON cannot bypass the provider's account recovery process.

This is a disaster-recovery path, not a way to recover the old provider credential vault or E2E content keys. The product must explain these distinctions in the recovery UI.


## Recovery generation rotation workflow

Manual-key rotation is a two-phase client operation:

1. The currently active bundle and device DEK are authenticated; all credential records are decrypted only in process memory.
2. A new generation is created with a fresh random DEK and five independently generated 256-bit manual keys. Every credential record is re-encrypted under the new DEK, and five new wrapping envelopes are created.
3. The user must export the new plaintext TXT, encrypted .key, and encrypted Vault Recovery Bundle before commit. If any export is cancelled, the current generation remains active.
4. Commit writes and verifies the new device DEK and bundle, then removes the previous generation's device-local DEK.
5. The UI switches to the new generation only after commit succeeds.

This is not remote revocation of offline exports. An old .key plus its old encrypted bundle remains capable of recovering that historical snapshot. AUREON cannot invalidate offline copies without a trusted online generation registry or a server-side policy anchor. Once Cloudflare generation enforcement is deployed, old generations must be rejected for current account restoration while historical exports remain clearly labeled as historical snapshots.

The current Flutter implementation is a local prototype: it does not yet have a server-side monotonic generation registry, Cloudflare envelope refresh, or provider OAuth credential synchronization. Do not describe local rotation as global revocation.
