# AUREON — Cross-Device Cloud Restore and Existing-Content Import

**Version:** 0.1 · **Date:** 2026-11-07 · **Status:** Product requirement and architecture proposal; implementation not started

This document records the required experience for restoring linked cloud accounts across devices and importing content that already exists in those accounts.

## 1. One-time provider linking, seamless AUREON sign-in

- User connects each Google Drive, Google Photos, OneDrive, Dropbox or other supported account to AUREON once.
- AUREON Master Account stores linked-provider inventory and the secure credential references needed to restore provider access on another authorized device.
- After signing into AUREON on a new device, AUREON restores the linked account list and attempts to establish provider API sessions without asking the user to manually add each account again.
- User should not routinely re-enter provider passwords.
- If the provider requires fresh interactive authentication (MFA, consent renewal, suspicious-login challenge, revoked/expired refresh token or conditional-access check), AUREON pauses only the affected account and asks the user to complete the provider's official challenge. User completes the challenge on the provider's official authorization page and may manually enter an email verification or authenticator code there. AUREON must not read Gmail, inspect authenticator apps, collect TOTP seeds or bypass MFA.
- AUREON must never scrape Gmail inboxes, read authenticator databases, capture OTPs automatically, collect provider passwords or bypass MFA. No Gmail mailbox-read scope is requested merely to retrieve a verification code.
- After successful challenge, securely update the credential vault and resume eligible queued operations.

## 2. Cross-device credential architecture

**Product direction:** a user-consented backend credential vault is required to meet the seamless cross-device provider-login requirement. Device-held-only refresh tokens are insufficient for the promised experience.

Proposed design:
- Provider refresh tokens are stored server-side only as authenticated encrypted envelopes using envelope encryption backed by a managed KMS/HSM-backed key service.
- Refresh tokens never leave the backend vault. Short-lived access tokens may be issued over TLS to the authenticated Kotlin/native provider adapter when direct provider API calls require them; keep them in native process memory only, never persist/log them or expose them to Flutter UI.
- Credential service is isolated from ordinary API modules, with dedicated service identity and least-privilege access.
- Decryption is permitted only for provider-token broker operations; tokens are never returned to Flutter UI or general client APIs.
- Bind encrypted credentials to immutable account ID, provider type and credential version as authenticated context.
- Maintain key versioning, rotation, access audit, anomaly detection, rate limits, secret redaction, backup/restore controls and incident response.
- Vault access requires a valid AUREON session and authorized device. Device revocation blocks future vault use.
- User explicitly consents to storing provider authorization credentials in AUREON's secure vault, with clear explanation of risk and cross-device benefit.
- E2E file-content keys and recovery secrets remain separate. The backend must never use the provider-token vault to decrypt file contents.
- If vault/KMS is unavailable, preserve credentials and local jobs; show a temporary service error rather than claiming accounts are ready.

**Security trade-off:** this improves convenience but increases the impact of a backend compromise. The vault is a critical security boundary, not an ordinary database column. It requires dedicated threat-model review and independent security testing before production.

## 3. MFA and reauthentication behavior

- Normal AUREON login restores provider connections silently when stored refresh credentials remain valid.
- MFA is not expected on every AUREON login. It occurs only when the provider requires it.
- Show provider name, account identity, reason/status where known, and an official Continue/Reconnect action.
- Complete challenges in the provider's official browser/app flow. If the provider displays a code-entry challenge, the user enters it in that official flow or a provider-supported handoff.
- AUREON does not ask for provider passwords or TOTP seeds.
- Do not ask the user to give AUREON Gmail credentials. If Google sends a code to Gmail, the user reads it and enters it into the provider's official challenge UI.
- After challenge success, atomically save any newly issued refresh token before marking the account connected.
- If challenge is cancelled or fails, mark only that provider account reauth-required; preserve other provider accounts and all pending jobs.

## 4. Existing Google Drive content import

The product requirement is to show existing files, not only files newly created through AUREON.

- Evaluate and complete Google restricted-scope verification for full Drive inventory (for example, drive.readonly for read-only inventory or drive if write/move operations are required). drive.file alone cannot enumerate an entire existing Drive.
- Verify current Google qualification, restricted-scope verification and security-assessment requirements before public launch. Backup/sync use cases may qualify, but Google determines eligibility.
- Use paginated files.list inventory and continue until no next-page token remains. Never report import complete after only the first page.
- Index My Drive, shared folders and shared drives only to the extent granted by the user's permissions and API capabilities.
- Preserve native folder IDs and parent relationships. Build a folder tree from parent IDs; do not flatten paths into names.
- Handle shortcuts, shared files, duplicate names, orphaned parents, trashed items and inaccessible items explicitly.
- Use provider object IDs as identity; never infer identity from filenames.
- Initial indexing is metadata-first. Do not download every file to the device. Content transfer occurs only when user requests it or a configured policy requires it.
- Provide import progress, resumable cursors, incremental sync, retry and reconciliation. Process death or token expiry must not unnecessarily restart a complete inventory.
- Existing cloud files remain in place. Import/index is non-destructive and never moves, renames or deletes originals by default.

### AUREON category classification

Show both original provider location and a derived AUREON category.

Categories may include Documents, Images, Videos, Audio, Archives, PDFs, Spreadsheets, Presentations, Code and Other.

- Derive categories primarily from provider MIME type and metadata; use extension only as fallback.
- Do not move files or alter the original folder hierarchy to create categories.
- A file may appear in a category view while retaining its original folder location.
- Preserve user-created tags separately from automatic categories.
- Ambiguous or unsupported types go to Other rather than being guessed.
- Classification is reversible and does not change provider-side content.

## 5. Google Photos content and album handling

Google Photos is not Google Drive and has a distinct API/product model.

- Represent Google Photos albums as albums, not filesystem folders.
- Represent media items as photos/videos with album membership only where the API provides it.
- Do not invent a folder hierarchy for Photos or claim all Photos library content is accessible through a normal Drive API integration.
- Google Photos API changes effective March 31, 2025: Picker API is the user-mediated way to select existing library media; Library API focuses on content created by the app.
- Picker lets the user select existing photos/videos for AUREON use. It is not a general background full-library crawler.
- AUREON may manage its own app-created Photos albums/media within supported Library API scopes.
- If selected media includes album/context metadata, preserve it. If the API does not expose full album hierarchy or membership, disclose the limitation rather than fabricating structure.
- Never promise full automatic import or complete album browsing of an existing Google Photos library unless Google provides a supported API path and the app passes applicable review.
- Ordinary image/video files stored in Google Drive folders use the Drive import path; that is separate from Google Photos.

## 6. Unified account and file UI

- AUREON Home shows all linked provider accounts and their connection/reauth state.
- Each file detail shows its actual provider and account identity.
- Unified browser may present provider content, but original provider location remains visible.
- Filters include provider, account, original folder, category, file type, modified date and offline availability.
- Do not merge separate provider accounts into a fake storage quota or use accounts to evade provider quotas.
- If a provider is reauth-required, cached metadata may remain browsable with a stale/offline indicator; provider operations remain blocked until reauthorization.
- Account linking is separate from content import. An account can be connected while its initial index is still running.

## 7. Data model additions to review

Before approving a migration, review these fields/entities:
- provider_accounts: stable provider subject, display identity, granted scopes, connection state, last token validation, reauth reason.
- provider_credentials: encrypted refresh-token envelope, KMS key version, credential version, expiry/rotation metadata; no plaintext tokens.
- oauth_transactions: one-time state hash, PKCE metadata, provider, device, expiry and consumed timestamp; never persist raw authorization code.
- provider_inventory_cursors: provider account, inventory scope, page cursor, last completed scan, incremental sync token and status.
- provider_items: provider object ID, parent ID, item kind, MIME type, size, modified time, provider version, trashed/shared/shortcut status and encrypted metadata where applicable.
- provider_album_memberships: album/media relation only where Photos API provides it.
- reauth_events: safe reason code, timestamps, device and correlation ID; no secrets or OTP values.

Review normalized schema, retention and encrypted metadata before changing V001. Never silently mutate a deployed migration; create a new migration after schema review.

## 8. Failure and safety rules

- Vault/KMS unavailable: preserve state and retry later; no credential loss.
- Provider refresh rejected: mark that account reauth-required; preserve jobs and source files.
- MFA cancelled: no false connected state; other accounts continue.
- Initial inventory interrupted: resume from a safe cursor; do not claim full inventory.
- Permission narrowed: show permission-limited inventory and block unsupported operations.
- Photos API cannot expose an album relation: show only supported metadata and disclose the limit.
- Duplicate names: distinguish by provider object ID and full parent path.
- Missing parent folder: show unresolved/orphaned location; do not silently re-parent.
- Indexing failure never deletes, moves or renames original cloud files.
- AUREON never reads Gmail to harvest OTPs and never stores authenticator seeds.

## 9. Release acceptance criteria

- Link multiple provider accounts once; restart app and verify all account records restore.
- Sign into AUREON on a second device and verify linked account inventory restores without manually adding providers again.
- With valid refresh tokens, provider access resumes without asking for passwords or MFA.
- Force refresh-token revocation/expiry and verify only the affected account requests provider reauthentication.
- Complete a provider MFA challenge manually; verify refreshed credentials persist and queued work resumes.
- Verify credentials are encrypted at rest, KMS access is least-privilege, audited and unavailable to ordinary API handlers.
- Import an existing Google Drive with nested folders and duplicate filenames; verify parent tree, categories, pagination and incremental sync.
- Interrupt Drive inventory mid-pagination; verify safe resume without losing/duplicating records.
- Verify existing Drive objects are not moved, renamed or deleted by import.
- Verify Google Photos Picker selects user-chosen existing media and AUREON does not claim unrestricted library enumeration.
- Verify Photos albums are represented as albums only where API provides the data.
- Verify ordinary image/video files inside Drive folders use Drive folder hierarchy, not Photos album semantics.

## 10. Official references

- [Google Drive API — List files](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/list)
- [Google Drive API — Choose scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- [Google Photos APIs — Overview](https://developers.google.com/photos/overview/about)
- [Google Photos APIs — Updates and Library API changes](https://developers.google.com/photos/support/updates)
- [Google Photos APIs — Authorization scopes](https://developers.google.com/photos/overview/authorization)
- [IETF RFC 9700 — OAuth 2.0 Security Best Current Practice](https://www.rfc-editor.org/rfc/rfc9700.html)
- [Android Developers — Android Keystore](https://developer.android.com/privacy-and-security/keystore)


## 11. Disaster recovery when every recovery key is lost

The owner requires a last-resort recovery path that does not depend on retaining any of the five Manual Recovery Keys or the encrypted `.key` export. If all manual keys are lost and Cloudflare-assisted credential-vault recovery is unavailable or intentionally not used, the user must still be able to reconnect provider accounts through each provider's official OAuth authorization flow and rebuild the AUREON file view without moving or deleting existing cloud content.

### Re-link and rebuild flow

1. The user signs into the AUREON Master Account, or creates a replacement AUREON account and explicitly claims/relinks provider accounts where ownership can be verified.
2. The user selects **Reconnect cloud accounts** and authorizes each Google Drive, OneDrive, Dropbox or other provider using its official OAuth flow. AUREON never asks for provider passwords or bypasses MFA.
3. AUREON identifies each provider account using the provider's stable subject/account ID and verifies the granted scopes. A matching provider identity can be associated with the user's new AUREON account only after successful provider authorization; email/display-name similarity alone is not sufficient.
4. AUREON performs a complete, paginated, metadata-first inventory scan, preserving provider object IDs, real parent IDs, folder hierarchy, shared/shortcut/trash states and provider versions. It resumes safely after interruption and reconciles changes since the previous scan.
5. AUREON rebuilds the unified file browser and derived categories from provider truth. Existing provider files remain where they are; re-link/import is read-only by default and must never duplicate, rename, move or delete provider originals.
6. AUREON restores prior AUREON-specific organization from the independent encrypted metadata backup described below. If no such backup exists, it reconstructs what it can from provider metadata and clearly identifies user-created organization that could not be recovered.

### Independent AUREON metadata backup

- Keep the AUREON organization/catalog backup logically and cryptographically separate from provider OAuth credentials, the five Manual Recovery Keys, the .key export and the provider credential-vault DEK.
- Back up the minimum metadata needed to reproduce the prior experience: stable provider account identity mappings; provider object IDs and parent relationships; AUREON virtual collections; user-created tags; favorites; pinned/recent views where opted in; custom sort/group settings; sync and offline policies; transfer/job checkpoints; and metadata for AUREON-managed aliases or virtual organization.
- Provider-native names, paths, hierarchy, sizes, MIME types, modified timestamps, trash status and permissions must be re-read from the provider where possible rather than trusted as stale backup facts.
- Keep a versioned, integrity-protected metadata snapshot in an independent backup location and cache an encrypted copy on authorized devices. Cloudflare D1 alone is not an independent backup if Cloudflare is unavailable.
- For sensitive metadata, use client-side authenticated encryption with a separate metadata key hierarchy. Do not reuse the provider credential-vault DEK, any Manual Recovery Key, the .key passphrase or E2E file-content keys. Define a recovery policy that permits restoring this organization backup after provider re-link without exposing provider credentials.
- Keep snapshots and an append-only change journal or equivalent versioned deltas so the last known organization can be reconstructed. Expose backup freshness, last successful snapshot, and any unsynced changes in Settings.
- Do not store device-specific filesystem handles, SAF tree URIs, Windows paths, local absolute paths or OS permission grants as portable metadata. Each device must reselect its local folder and regrant OS permissions.
- Metadata restore is a merge, not blind overwrite: match by stable provider account subject + provider object ID; detect deleted/replaced objects, duplicate identities, conflicts and stale versions; preserve provider truth and offer conflict resolution where needed.
- If the independent metadata backup is also lost, AUREON can still re-index provider files and rebuild original provider folder hierarchy, but cannot guarantee restoration of AUREON-only tags, favorites, virtual collections, custom organization or settings that existed only in the lost backup.

### Acceptance criteria

- Delete all five manual recovery keys and make the .key export unavailable in a test account; ensure official provider re-link still works.
- Reconnect a provider account and rebuild the complete file index from provider APIs without moving, renaming, duplicating or deleting existing cloud files.
- Restore a metadata snapshot on a clean Android or Windows device and reproduce AUREON-only organization against stable provider object IDs.
- Test missing, stale, corrupted and conflicting metadata snapshots; never silently replace newer provider state.
- Verify that no OAuth credential, recovery key, DEK, device-local path or OS permission grant appears in the metadata backup.
- Verify device-local folder bookmarks require fresh per-device permission grants after restore.
- When metadata backup is absent, show a precise recovery limitation while still offering provider re-link and re-index.
