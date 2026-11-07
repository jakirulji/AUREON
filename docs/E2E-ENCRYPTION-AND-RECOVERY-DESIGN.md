# AUREON — E2E Encryption and Recovery Design

**Version:** 0.1 · **Date:** 2026-11-07 · **Status:** Cryptographic design proposal; not approved for production

This document defines a reviewable direction for client-side file encryption, key wrapping and recovery. It deliberately does not invent a custom cryptographic construction. A cryptography review and cross-platform test vectors are mandatory before implementation.

## 1. Security goals and non-goals

### Goals
- Cloud providers and the AUREON backend should not receive plaintext file contents or plaintext file-content keys in the normal architecture.
- Each file version gets an independent random data-encryption key (DEK).
- File encryption is authenticated, streaming-capable and suitable for large files on low/mid-range Android devices.
- A newly authorized device can decrypt files only after obtaining a valid user-controlled recovery/key envelope.
- Key loss must be explained honestly; account login alone must not silently bypass E2E protection.
- Upload retries must reuse the exact staged ciphertext rather than re-encrypting a changed source under a new stream.

### Non-goals
- Hiding all metadata from cloud providers (object size, ciphertext length, timing and provider account remain visible).
- Protecting plaintext while a legitimately authorized device is unlocked and actively displaying it.
- Recovering files if every user-controlled key/recovery method is lost.
- Claiming that root/custom ROM compromise is fully prevented.

## 2. Recommended file-encryption primitive

### Candidate: Google Tink Streaming AEAD

Evaluate Tink's Java/Android Streaming AEAD with AES-GCM-HKDF. It is designed for large files/streams, authenticates segments and their positions, and avoids loading an entire file into memory. Tink documents AES128_GCM_HKDF_1MB as its general default; AUREON should benchmark both the 128-bit and 256-bit variants before selecting one. If the product requirement remains AES-256, AES256_GCM_HKDF_1MB is the candidate, subject to verified library support, performance and cross-platform interoperability.

Why this is preferable to a hand-built chunk format:
- Per-segment authentication and position binding are already part of the construction.
- Segments cannot be silently reordered or transplanted between ciphertext streams.
- It is designed for streaming large content.
- Java and C++ implementations exist in Tink's supported primitive matrix, which is relevant to Android-first and later Windows support.

Important constraints:
- Associated data is authenticated, not encrypted. Never put a filename, email, provider name or other sensitive metadata in AAD.
- An existing stream cannot be modified or appended in place; re-encrypt the entire file version.
- A partial plaintext segment may be available after that segment authenticates, but AUREON must write to a temporary destination and must not expose/promote the final file until the entire stream and final verification succeed.
- The exact Tink version, Android minimum API compatibility, C++ interoperability, keyset format and license must be checked in a build spike before dependency approval.

## 3. Key hierarchy

Use envelope encryption with separate keys for content, account recovery and device protection.

### 3.1 Per-version data key

1. Generate a cryptographically random DEK for each file version.
2. Encrypt that version's content with the selected Streaming AEAD primitive.
3. Wrap the DEK using one or more independent key-encryption keys (KEKs).
4. Store only wrapped DEK envelopes and algorithm/format identifiers with the encrypted object metadata.
5. Never reuse a DEK for a different file version.

A metadata-only rename may update encrypted metadata without re-encrypting file bytes if the design permits; content changes always create a new version and new DEK.

### 3.2 User recovery key

Generate a high-entropy recovery secret on the client during secure setup. It must be independent of the AUREON account password and provider credentials.

- Show the recovery material once during setup and require the user to confirm they have saved it.
- Provide a printable/exportable recovery kit with clear warnings and no automatic cloud upload of plaintext recovery material.
- Derive a recovery KEK from the recovery secret using a vetted password/KDF implementation and versioned parameters, or use a random recovery key directly. The exact KDF and encoding format require review and test vectors.
- Wrap the account key-encryption root or the per-file DEKs under the recovery KEK.
- Store only the encrypted key envelope and KDF parameters/salt in AUREON metadata.
- Never transmit the recovery secret or plaintext KEK to the AUREON backend.

A human-memorable passphrase is not equivalent to a high-entropy random recovery secret. If a passphrase option is offered, use a memory-hard KDF such as Argon2id with reviewed parameters, unique salt and rate-limited local attempts. Do not use a fast hash such as SHA-256 directly as a password KDF.

### 3.3 Device protection

Each device generates its own non-exportable Android Keystore wrapping key where supported. A local copy of the account key material or file DEK envelope may be wrapped for that device so routine access does not require the recovery secret every time.

- Hardware-backed/StrongBox use is opportunistic and must be detected, not assumed.
- Device key invalidation means that device may need recovery-key unlock or provider/account reauthorization; it must not destroy the cloud copy.
- Device revocation removes the device's authorization to obtain new key envelopes. It cannot make a previously compromised device forget plaintext or keys it already copied.
- The backend stores public device identity and encrypted envelopes only; it must not store device private keys.

### 3.4 New-device recovery

1. Sign in to the AUREON Master Account and restore file catalog and encrypted key-envelope metadata.
2. Ask the user for the recovery secret or import the recovery kit.
3. Derive/unwrap the recovery KEK locally.
4. Authenticate and decrypt the account key envelope locally.
5. Re-wrap required key material to the new device's Keystore key.
6. Verify by decrypting a small known encrypted test object or selected file before reporting recovery complete.
7. If recovery fails, preserve encrypted cloud objects and show a clear recovery error. Never silently generate a new key and imply old files remain decryptable.

Account password reset and E2E key recovery are separate operations. Email access or support intervention must not bypass the recovery secret.

## 4. Metadata and authenticated context

Encrypt sensitive file metadata client-side where practical, including original filename, folder names, MIME type, user tags and descriptive metadata.

The backend may need a minimal opaque catalog envelope and operational fields such as random object IDs, encrypted payload size, timestamps, provider account reference and transfer state. Document exactly which fields remain visible.

Associated data may bind ciphertext to immutable, non-secret identifiers such as:
- AUREON random file ID,
- immutable file-version ID,
- encryption format version,
- purpose/domain separator.

Do not bind mutable provider object IDs, paths or account labels unless the migration/relink semantics are fully defined. Do not place sensitive values in AAD because AAD is visible.

Prevent ciphertext/key-envelope swapping across users, files and versions by authenticating the relevant immutable identifiers and checking ownership server-side.

## 5. Upload and download integration

### Upload

1. Read a stable source snapshot or copy it to app-private staging.
2. Generate a new per-version DEK and encrypt the source stream into a durable ciphertext staging file.
3. Finalize and flush the ciphertext staging file; compute its SHA-256 fingerprint and byte length.
4. Persist the encrypted key envelope, format version, source fingerprint and ciphertext fingerprint.
5. Upload the exact staged ciphertext using the provider's resumable API.
6. Resume from provider-acknowledged ciphertext offsets/parts. Do not restart encryption or produce a different ciphertext for the same upload operation.
7. Verify remote size and provider checksum/read-back where supported.
8. Mark the canonical cloud object verified only after required checks succeed.
9. Preserve the original source by default. Any optional cleanup remains subject to the separate deletion-safety policy.

### Download

1. Download the exact ciphertext version to a temporary file; range resume must be validator-bound.
2. Verify ciphertext size and available provider integrity checks.
3. Unwrap the DEK locally and decrypt into a separate temporary destination.
4. Authenticate every segment; fail closed on any tag, ordering, truncation or format error.
5. Verify full-stream completion and expected plaintext fingerprint if one is stored in an authenticated encrypted manifest.
6. Atomically promote the plaintext destination where platform semantics permit.
7. On any failure, remove only the incomplete temporary plaintext output; never delete the verified remote ciphertext or user's pre-existing destination.

## 6. Format and versioning

Every encrypted object must carry a versioned, parseable header/manifest containing only required non-secret fields:
- format version and primitive identifier,
- key-envelope version and wrapping algorithm,
- stream parameters and segment size,
- random file ID and immutable version ID,
- ciphertext length and integrity metadata,
- wrapped DEK envelope reference/data.

Do not make undocumented changes to cryptographic parameters. New formats require migration tests and backward-compatible readers for supported versions. Unknown versions must fail safely without attempting heuristic decryption.

## 7. Threat model and limits

| Threat | Mitigation | Residual limitation |
|---|---|---|
| Cloud provider reads stored object | Client-side encryption | Provider sees ciphertext size and access patterns |
| AUREON backend/database compromise | No plaintext DEKs/content; encrypted envelopes only | Account/catalog metadata may still leak |
| Stolen locked device | Keystore protections, optional user-auth requirement, device revocation | Rooted/unlocked device risk remains |
| Malicious ciphertext modification | Streaming AEAD authentication | Do not expose incomplete plaintext |
| Cross-file/version ciphertext swap | Authenticated immutable IDs and ownership checks | Correct ID lifecycle is critical |
| Lost device | Recovery secret and device revocation | Recovery secret must be preserved |
| Lost recovery secret | No backdoor; explicit unrecoverable state | Data may become permanently inaccessible |
| Malicious app/build/dependency | Reproducible CI, dependency review, signing controls | Supply-chain risk cannot be eliminated |
| Rollback to older valid ciphertext | Version/manifest monotonicity and authenticated catalog state | Offline rollback detection needs a trusted checkpoint |

## 8. Required cryptographic tests

- Published Tink test vectors and known-answer tests.
- Android Java ↔ future Windows C++ interoperability using identical ciphertext and key envelopes.
- Empty file, tiny file, multi-segment file, large file and boundary-size cases.
- Truncate, bit-flip, reorder, duplicate and cross-file segment substitution must fail.
- Wrong DEK, wrong recovery secret, corrupted envelope and unknown format version must fail closed.
- Process death during encryption must leave no completed ciphertext record.
- Process death during upload resumes the exact staged ciphertext.
- Process death during decrypt leaves only a temporary incomplete output, never a promoted final file.
- Recovery on a second device restores the same file content and verifies its hash.
- Device-key invalidation does not destroy recovery envelope or cloud data.
- No plaintext DEK, recovery secret or file content in logs, database columns, crash reports or analytics.
- Benchmark CPU, memory, battery and throughput on representative low/mid-range Android devices, including 6 GB RAM devices.

## 9. Decisions still open

1. Final primitive and AES-128 vs AES-256 selection after benchmark and security review.
2. Exact Tink Android/C++ versions, license and interoperability spike.
3. Recovery secret format, entropy, encoding and user experience.
4. KDF choice/parameters if human passphrases are supported.
5. Whether the account root key wraps per-file DEKs or each DEK has independent recovery/device envelopes.
6. Metadata fields visible to the backend and cloud provider.
7. Key rotation, recovery-kit rotation and device-revocation semantics.
8. How to detect catalog rollback across offline devices.

## 10. Official references

- [Google Tink — Streaming AEAD](https://developers.google.com/tink/streaming-aead)
- [Google Tink — Encrypt large files or data streams](https://developers.google.com/tink/encrypt-large-files-or-data-streams)
- [Google Tink — Java and Android setup](https://developers.google.com/tink/setup/java)
- [Google Tink — Supported key types](https://developers.google.com/tink/supported-key-types)
- [Android Developers — Android Keystore system](https://developer.android.com/privacy-and-security/keystore)
