# AUREON — Android Native OAuth and Credential Lifecycle

**Version:** 0.1 · **Date:** 2026-11-07 · **Status:** Engineering proposal; implementation not started

This document defines Android provider authorization and credential lifecycle. It complements the [Provider OAuth and Permission Matrix](./PROVIDER-OAUTH-MATRIX.md) and [A0 Engineering Blueprint](./A0-ENGINEERING-BLUEPRINT.md). Provider registrations, client IDs, redirect URIs, scopes and review requirements must be finalized for each provider.

## 1. Security and product invariants

1. AUREON Master Account authentication is separate from Google, Microsoft and Dropbox authorization.
2. Every connected provider account has an independent AUREON record and revocable credential.
3. OAuth credentials authorize provider API access; they are never E2E file-encryption keys.
4. Never collect provider passwords, OTPs, recovery codes or browser cookies.
5. Native OAuth uses Authorization Code + PKCE in an external user-agent. No embedded WebView login, implicit flow, password grant or client secret embedded in the APK.
6. Request least-privilege scopes incrementally. Persist actual granted scopes, not only requested scopes.
7. Refresh failure, revoked consent or missing scopes must not delete local originals, staging data, queued jobs or remote files.
8. Disconnecting removes/revokes authorization as supported; it never deletes remote content.
9. Tokens, authorization codes and session URLs must never appear in logs, crash reports, analytics, clipboard or error strings.
10. Never claim an account is connected or a transfer complete until verified.

## 2. Android authorization flow

### 2.1 Recommended sequence

Use IETF RFC 8252 and current OAuth security best practice:

1. User taps Connect on a named provider.
2. Create a short-lived authorization transaction containing cryptographically random state, PKCE verifier/challenge using S256, provider, exact redirect URI, requested scopes and creation time.
3. Persist the transaction before launching the browser. Protect the verifier; state is one-time and expires.
4. Launch the authorization URL in the system browser or compliant external authentication tab. Never collect credentials in an embedded WebView.
5. Receive the redirect through the exact registered mechanism. Prefer verified HTTPS App Links where supported; otherwise use a provider-supported registered private-use URI scheme.
6. Validate transaction existence, expiry, one-time use, provider, redirect URI and state. Reject duplicate, unsolicited, malformed or mismatched callbacks.
7. Exchange the authorization code using the PKCE verifier and public-client requirements. Never send an APK-embedded client secret.
8. Validate issuer, audience, nonce and ID-token signature/claims when OpenID Connect is used.
9. Fetch account identity from the provider's authoritative account endpoint. Bind to a stable provider subject, not only a mutable email or display name.
10. Persist credentials securely and record actual granted scopes. Show account identity and access boundary.
11. Delete the one-time transaction and verifier after success or terminal failure.

### 2.2 Callback hardening

- Exact redirect URI registration; no wildcard matching.
- Constant-time state comparison where applicable.
- One-time callback consumption and short transaction lifetime.
- Narrow Android intent filters; prefer verified App Links when supported.
- Never accept authorization codes in generic file/deep-link handlers.
- Never put access or refresh tokens in redirect URLs.
- Redact callback query parameters from logs and diagnostics.

### 2.3 App architecture boundary

Flutter calls a typed provider-authorization repository. Kotlin owns browser handoff, callback validation, PKCE transaction and secure credential access. Provider adapters own endpoints, scopes, account identity parsing and refresh semantics.

Never expose raw tokens to Flutter widgets or arbitrary MethodChannel calls. Flutter receives only safe state: internal account ID, provider, masked account label, granted-scope summary, connection state and safe timestamps.

## 3. Credential storage decision

### 3.1 Device-held baseline

**Recommended first implementation:** keep provider refresh credentials on the device that authorized them. This reduces the impact of an AUREON backend compromise and avoids silently creating a central vault of third-party credentials.

- Generate a random local encryption key and protect its key-encryption key with Android Keystore.
- Encrypt credential records at rest using authenticated encryption such as AES-GCM with unique nonces.
- Store ciphertext and non-secret metadata in the local encrypted store.
- Prefer hardware-backed Keystore protection when available, but query/report actual security level; never assume every phone has StrongBox or hardware-backed AES.
- Keep access tokens in memory for the shortest practical lifetime.
- Never store raw refresh tokens in SharedPreferences, plain SQLite, files, logs or Flutter preferences.
- On app data clear, uninstall, device loss or Keystore invalidation, mark provider authorization as reauth-required; preserve AUREON inventory and transfer metadata.

Android Keystore makes key extraction harder, but does not make a compromised or rooted running app invulnerable. A compromised app may still invoke permitted key operations. Do not promise absolute protection.

### 3.2 Cross-device restoration

A new device restores the AUREON Master Account inventory, provider labels, file catalog and sync state. Under the device-held baseline, it must re-authorize each provider account before provider operations. This is an intentional security boundary.

A later optional backend credential vault may be evaluated if seamless cross-device provider authorization is essential. It requires separate consent, envelope encryption backed by managed KMS, strict service identity, least-privilege access, audit logs, rotation, incident response and provider-terms review. Never enable it silently. E2E file-content keys remain client-controlled and separate.

### 3.3 Keystore notes

- Use Android Keystore for non-exportable wrapping/signing keys, not as a general-purpose database.
- Store encrypted token blobs in the encrypted local database; wrap the database/credential key with Keystore-protected material.
- Handle key invalidation, key loss, restore-to-new-device and OS/ROM changes as recoverable reauthorization states.
- StrongBox is optional; gracefully fall back when unsupported.
- Run cryptographic operations off the main thread.
- Use maintained platform APIs and reviewed libraries; no custom cryptography.

## 4. Token lifecycle

Each provider account has an independent state:

| State | Meaning |
|---|---|
| connecting | Authorization transaction pending |
| connected | Credential usable and required scopes present |
| permission_limited | Connected, but some requested scopes were not granted |
| refreshing | One refresh operation in progress |
| reauth_required | Refresh invalid/revoked/expired or interaction required |
| disconnected | User disconnected or authorization revoked |
| error | Unexpected provider/configuration failure |

### 4.1 Refresh rules

- Serialize refresh per provider account; never concurrently use the same rotating refresh token.
- Refresh shortly before access-token expiry, not on every API call.
- If the provider rotates refresh tokens, atomically persist the new token before considering refresh successful. Never overwrite a newer token with an older response.
- Treat invalid-grant, revoked consent, expiry and interaction-required as reauth-required; do not loop.
- Honor provider throttling and retry guidance.
- Do not assume offline access or refresh-token issuance unless the provider actually grants it.
- After process death during refresh, reconcile persisted state and provider semantics; do not blindly replay a possibly rotated token.
- Redact token-endpoint errors before logging.

### 4.2 Scope changes

- Store requested and actually granted scopes separately.
- Explain why a feature needs a missing scope before initiating new consent.
- Never silently request broader scopes during routine refresh.
- A scope downgrade becomes permission-limited or reauth-required according to provider response.
- Never infer full Google Drive access if only drive.file was granted.

## 5. Disconnect and relink

1. User selects a specific provider account and confirms disconnect.
2. Pause new jobs targeting it. Existing jobs become waiting-for-account and retain operation IDs, source references and staging data.
3. Attempt provider token revocation where supported and possible.
4. Remove local credential material and invalidate in-memory access tokens.
5. Mark the account disconnected in AUREON metadata; preserve file catalog and remote references for relinking/reconciliation.
6. Do not delete provider files, source originals, unrelated cache entries or the AUREON Master Account.
7. On reconnect, relink only after stable provider-subject verification. If identity cannot be proven, create a separate record and require explicit reconciliation.

If offline, disable local use immediately and record revocation-pending where safe. Explain that remote revocation cannot be guaranteed until the provider can be contacted.

## 6. Failure behavior

| Failure | Required result |
|---|---|
| User cancels browser login | Remain disconnected; no false connected record |
| Wrong, missing or expired state | Reject callback and discard transaction |
| Browser/app process killed | Expire or safely resume only the same valid transaction |
| Token exchange timeout | Reconcile safely; never expose code/token |
| Refresh token revoked/expired | Reauth required; preserve queue and local files |
| Required scope missing | Permission limited; block only unsupported operations |
| Keystore key invalidated | Reauthorize; do not wipe cloud inventory |
| Device lost | Revoke AUREON device session; provider credential is device-held unless separately revoked |
| Provider full or rate-limited | Keep job queued/paused; preserve source |
| Account disconnected during transfer | Persist checkpoint; resume after reauthorization and session validation |

## 7. Required security tests

- PKCE S256 generation and verifier/challenge matching.
- Reject state mismatch, replay, expiry, duplicate and wrong-provider callbacks.
- Exact redirect URI validation.
- No embedded WebView authorization path.
- No client secret in APK, resources, source maps, logs or CI artifacts.
- No token/code/session URL in logs, crash reports or analytics.
- Token ciphertext at rest and Keystore key non-exportability where supported.
- StrongBox absence fallback.
- Many refresh callers produce one refresh operation.
- Refresh rotation never allows an old token to overwrite a new token.
- Invalid-grant/revoked consent transitions to reauth-required without data loss.
- Missing scopes produce permission-limited, not false full access.
- Disconnect preserves remote files, source originals, transfer jobs and catalog.
- New-device login restores account inventory but requires provider reauthorization under device-held model.
- Rooted/custom-ROM/key-invalidation tests document realistic limitations.

## 8. Implementation gates

Do not begin production provider integration until provider registrations and exact redirect URIs exist; first-provider scopes and account types are approved; callback and PKCE tests pass; credential storage and refresh rotation are fault-tested; process-death recovery preserves transfer state; and the privacy notice explains device-held credentials and new-device reconnection.

## 9. Official references

- [IETF RFC 8252 — OAuth 2.0 for Native Apps](https://www.rfc-editor.org/rfc/rfc8252.html)
- [IETF RFC 9700 — Best Current Practice for OAuth 2.0 Security](https://www.rfc-editor.org/rfc/rfc9700.html)
- [Android Developers — Android Keystore system](https://developer.android.com/privacy-and-security/keystore)
- [Android Developers — Cryptography](https://developer.android.com/privacy-and-security/cryptography)
