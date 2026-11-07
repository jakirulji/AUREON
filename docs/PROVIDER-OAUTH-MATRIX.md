# AUREON — Provider OAuth and Permission Matrix

**Version:** 0.1 · **Date:** 2026-11-07 · **Status:** Research-backed proposal; not a provider approval or production configuration

This document translates AUREON's initial provider scope strategy into a least-privilege proposal. It is not a substitute for provider app review, current endpoint-specific permission checks, legal review, or live OAuth testing. Re-check provider documentation before each production release because scope classifications and verification requirements can change.

## Product constraints

- Use user-delegated authorization for personal cloud accounts. Do not request app-only tenant-wide access for a consumer file manager.
- Use Authorization Code + PKCE for native public clients where supported. Validate OAuth `state`, redirect URI, issuer and nonce where applicable.
- Request scopes incrementally when a feature is first used, rather than requesting every permission at first launch.
- Show the provider, account identity, requested access and connected/disconnected status clearly.
- Never collect provider passwords, OTPs, recovery codes or user session cookies.
- Never treat a granted write scope as permission for automatic deletion. Product-level deletion policy remains stricter than provider capability.
- Keep provider tokens separate from E2E file-content keys. Token vaulting remains an explicit, separately reviewed decision.

## Initial scope matrix

| Provider | Intended access model | Proposed minimum starting scopes | Important limitation / review |
|---|---|---|---|
| Google Drive | OAuth user-delegated | `drive.file`; add `drive.metadata.readonly` only if required and approved | `drive.file` is per-file access: app-created, opened by the app, or explicitly shared/selected. It does not provide unrestricted inventory of a user's entire existing Drive. `drive`, `drive.readonly`, and metadata-wide scopes are restricted; broader access can trigger Google verification and, where restricted-scope data is stored/transmitted server-side, a security assessment. |
| OneDrive personal/work | Microsoft Graph delegated | `Files.ReadWrite` for full user file operations; add `offline_access`, `openid`, `profile`, `email` only as required by the chosen identity/token flow | `Files.ReadWrite` is the least-privileged permission for upload/replace endpoints and covers read/create/update/delete of the signed-in user's files. Avoid `Files.ReadWrite.All` and application permissions for the consumer baseline. Deletion is still technically possible with the granted permission; AUREON must block automatic delete in its own policy layer. |
| Dropbox | Scoped OAuth, Full Dropbox only if full-account browsing is a core requirement | `files.metadata.read`, `files.content.read`, `files.content.write`; `account_info.read` for account identity if required | App Folder access is narrower but confines AUREON to its app folder. Full Dropbox access is needed for whole-account file management. Dropbox's `files.content.write` supports write operations including delete endpoints; app logic must still prohibit automatic deletion. Avoid sharing scopes unless sharing features are explicitly introduced. |

## Provider-specific decisions

### Google Drive

**Preferred product strategy:** start with `drive.file` and a user-mediated Google Picker/file-selection flow for selected-file workflows. This is the narrower permission path and aligns with per-file consent.

**Critical product trade-off:** a conventional unified browser that silently indexes every existing file and folder in a user's Drive cannot be delivered with `drive.file` alone. If full-drive browsing, global search, or automatic migration of arbitrary existing files is non-negotiable, the product must evaluate the required restricted scopes (likely `drive` or a combination of read/metadata scopes), Google's verification process, qualification requirements, and security assessment obligations before committing to that feature.

Do not label a `drive.file`-connected account as having full-drive access. The UI must disclose the actual access boundary.

### Microsoft OneDrive

Use delegated Microsoft Graph permissions. The endpoint-specific least-privileged permission for simple content upload/replace is `Files.ReadWrite`. Do not default to application permissions or tenant-wide `Files.ReadWrite.All`.

A future enterprise/SharePoint feature may need a separate permission model and admin-consent flow. Do not silently expand the consumer app's permissions to support it.

### Dropbox

Choose the Dropbox app access type based on the promised product behavior:
- **App Folder:** narrow access; only the app's dedicated folder.
- **Full Dropbox:** needed for a general file manager over the user's existing Dropbox content.

For a full file browser, start with metadata read + content read + content write. Do not request `sharing.read` or `sharing.write` until link/share management is a shipped feature.

## Cross-provider authorization lifecycle

1. User chooses Connect Provider and sees the provider's identity/consent screen.
2. Client creates a short-lived OAuth transaction with random state and PKCE verifier/challenge.
3. Redirect callback is validated; authorization code is exchanged through the correct public-client flow.
4. Client records granted scopes and provider account subject. It must not assume the requested scopes were all granted.
5. Tokens are stored in platform secure storage on device unless a separately approved backend vault is enabled with explicit consent.
6. Refresh is serialized per account; handle rotation, invalid_grant, revoked consent, expired refresh tokens, conditional access and provider throttling.
7. If refresh fails, mark account `reauth_required`; preserve local originals, staging data and transfer queue. Do not claim cloud sync is complete.
8. Disconnect revokes tokens where supported and removes local credentials. It does not delete remote files.
9. Scope expansion is a new consent transaction with an explanation of why the additional access is needed.

## AUREON safety policy overrides

Provider scopes may technically permit destructive operations. AUREON's product rules remain:
- No automatic deletion of source originals.
- No automatic remote deletion as a side effect of disconnect, tombstone, cache eviction, migration or account relink.
- A remote delete feature, if ever added, must be explicit, separately confirmed, audited and guarded against deleting the only verified copy.
- A provider permission failure or quota error must preserve local data and queue state.
- Never use multiple provider accounts to evade provider quotas or pool storage limits.

## Decisions still open before provider implementation

1. Whether AUREON's Google Drive baseline accepts the restricted-scope verification/security-assessment cost to support whole-drive browsing, or launches with Picker-based per-file access.
2. Whether Dropbox's first release promises App Folder-only or Full Dropbox.
3. Whether OneDrive personal and work/school accounts are both in the first provider release.
4. Native OAuth redirect strategy and exact supported account types for each provider.
5. Whether tokens remain device-held or a backend credential vault is ever offered.
6. Provider app registration ownership, consent-screen branding, verification submissions and production redirect domains.

## Official references

- [Google Drive API — Choose Drive API scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- [Google OAuth 2.0 scopes reference](https://developers.google.com/identity/protocols/oauth2/scopes)
- [Microsoft Graph — Permissions overview](https://learn.microsoft.com/en-us/graph/permissions-overview)
- [Microsoft Graph — Permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference)
- [Microsoft Graph — Upload or replace driveItem content](https://learn.microsoft.com/en-us/graph/api/driveitem-put-content?view=graph-rest-1.0)
- [Dropbox API — Quick start and scopes](https://docs.dropboxapi.com/dropbox-api/docs/get-started/quick-start)
- [Dropbox API — OAuth and permissions](https://docs.dropboxapi.com/dropbox-api/docs/oauth)
