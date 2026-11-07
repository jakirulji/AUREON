# ADR-0008 — Independent AUREON Metadata Backup and Exact-Layout Restore

**Status:** Accepted implementation baseline  
**Date:** 2026-11-08  
**Scope:** Android and Windows shared Dart metadata format; encrypted portable archive  
**Security boundary:** Separate from provider credential vault, Manual Recovery Keys and E2E file-content keys

## Context

AUREON user organization must remain recoverable even when all five Manual Recovery Keys and the encrypted `.key` export are lost. Re-linking a cloud provider can reconstruct provider-native files and folders, but it cannot reconstruct AUREON-only organization unless that organization has its own independent backup.

A metadata backup must restore the logical arrangement the user created in AUREON—not merely a flat list of file names.

## Decision

### Portable archive

- File extension: `.aureon-meta`.
- Format identifier: `AUREON-ENCRYPTED-METADATA-BACKUP`.
- Versioned JSON header + authenticated ciphertext payload.
- Argon2id KDF with fixed, versioned parameters: 64 MiB memory, 3 iterations, parallelism 2, 32-byte output.
- AES-256-GCM with a fresh random 16-byte salt and fresh 12-byte nonce per archive.
- Header (format/schema version, snapshot ID, generation, timestamp, KDF/cipher identifiers, parameters, salt and nonce) is authenticated as AAD.
- Strict parameter allow-list and archive-size cap before expensive KDF work. Unknown versions/parameters, truncation, wrong passphrase, tampering and header/payload mismatch fail closed.
- Passphrase is independent from the credential-vault keys and is never stored or transmitted by the archive codec.
- The user must keep this passphrase separately. Losing it means the encrypted metadata archive cannot be decrypted.

### Exact organization data

The encrypted snapshot preserves:

1. Stable AUREON logical folder IDs, names, nested child folders and exact sibling ordering.
2. File placement under each logical folder, per-folder file ordering, and stable provider identity tuple (provider, provider account subject/ID, provider object ID).
3. Original provider parent ID and provider version as reference facts, not as instructions to move provider objects.
4. Cross-account virtual-folder memberships. The same provider object may appear in multiple AUREON virtual folders without copying bytes.
5. User-created tags, favorites, custom labels, folder metadata, saved views, search/filter rules and organization preferences.
6. Snapshot schema version, snapshot ID, generation and UTC creation time.

Do not include OAuth passwords/tokens, access/refresh credentials, Manual Recovery Keys, the .key passphrase, Worker Secret, plaintext credential-vault DEK, E2E content keys, device-specific SAF URIs, Windows paths, local absolute paths or OS permission grants.

### Restore and conflict rules

- Restore is a merge keyed by stable AUREON folder ID and provider account subject + provider object ID.
- Backup layout and ordering are authoritative for matching backup folder IDs. Current-only folders are retained rather than silently discarded.
- If an ID exists in both current and backup state but its name/order differs, record a visible conflict. Do not silently discard the conflict.
- Provider APIs are authoritative for current provider object existence, names, parent relationships, versions, permissions and Trash state.
- Before a provider inventory is available, imported file references remain explicitly pending reconciliation. They are not marked live.
- After official OAuth re-link and complete provider re-index, match by immutable provider account subject and provider object ID. Replace mutable display facts with the current provider inventory record. Drop references confirmed absent from provider inventory; never recreate, move, rename or resurrect provider objects from metadata alone.
- A missing provider account or permanently deleted provider object is not restored by metadata import.
- Device-specific folders/permissions are reselected on each device.

## Implemented in current client branch

- Versioned nested metadata snapshot model and JSON validation.
- Nested AUREON folder organizer operations: create, rename, delete, move, file-reference add/remove, favorites, tags and explicit folder/file ordering.
- Device-local catalog is AES-256-GCM encrypted with a random device key held in platform secure storage; a two-slot catalog keeps a previous generation available after an interrupted write. Android app backup is disabled for device-bound secure-storage material.
- Portable `.aureon-meta` authenticated encryption/decryption using Argon2id + AES-256-GCM.
- Stable-ID conflict-aware merge planner and provider-inventory reconciliation input.
- Settings UI to export and import the encrypted archive through native file picker.
- Current virtual-folder memberships are included in the snapshot and restored to local catalog.
- Restore conflict details are exposed in the UI; imported provider references remain pending until provider re-index.
- Automated tests cover nested hierarchy/order round-trip, wrong passphrase rejection, merge behavior and provider object non-resurrection.

## Explicitly not yet implemented

- A complete user-facing nested AUREON file/folder organizer (the current app UI is still a preview and has only the virtual-folder MVP).
- Live provider OAuth/re-link and paginated provider inventory. Until that exists, imported provider references remain pending.
- Automatic encrypted metadata replication to an independent cloud destination or a multi-device metadata sync service. The current archive is portable and must be exported to user-controlled external storage (for example, offline drive or a user-selected cloud folder).
- Automatic background snapshots, delta journal, retention/version browsing and cross-device conflict UI.
- Security review and low/mid-range Android Argon2id performance benchmark.

The current local metadata catalog is not a substitute for an off-device backup. A portable archive must be exported and stored outside the device's failure domain.
