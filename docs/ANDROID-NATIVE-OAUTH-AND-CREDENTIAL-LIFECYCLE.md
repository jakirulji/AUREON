# AUREON — Android Native OAuth and Credential Lifecycle

**Version:** 0.2 · **Date:** 2026-11-07 · **Status:** Engineering proposal; implementation not started

This document defines Android provider authorization and credential lifecycle. It complements the [Provider OAuth and Permission Matrix](./PROVIDER-OAUTH-MATRIX.md), [Cloud Account Restore and Legacy Import](./CLOUD-ACCOUNT-RESTORE-AND-LEGACY-IMPORT.md), and [A0 Engineering Blueprint](./A0-ENGINEERING-BLUEPRINT.md). Provider registrations, client IDs, redirect URIs, scopes and review requirements must be finalized for each provider.

## 1. Security and product invariants

1. AUREON Master Account authentication is separate from Google, Microsoft and Dropbox authorization.
2. Each linked provider account has an independent AUREON record, credential lifecycle and reauthorization state.
3. Provider OAuth credentials authorize provider API access; they are never E2E file-encryption keys.
4. Never collect provider passwords, OTPs, recovery codes, TOTP seeds or browser cookies. The user completes provider login and any MFA challenge on the provider's official page.
5. Native authorization uses Authorization Code + PKCE in an external user-agent. No embedded WebView login, implicit flow, password grant or client secret embedded in the APK.
6. Request least-privilege scopes incrementally. Persist actual granted scopes, not only requested scopes.
7. Refresh failure, revoked consent or missing scopes must not delete local originals, staging data, queued jobs, catalog records or remote files.
8. Disconnecting removes/revokes authorization as supported; it never deletes remote content.
9. Tokens, authorization codes, PKCE verifiers and upload-session URLs must never appear in logs, crash reports, analytics, clipboard or error strings.
10. Never claim an account is connected or a transfer complete until verified.
11. Cross-device provider restoration is a product requirement. Device-held-only refresh credentials do not satisfy it and are not the target architecture.

## 2. Android authorization flow

### 2.1 Provider-neutral sequence

1. User taps Connect on a named provider and sees the requested access boundary and vault-consent explanation.
2. AUREON creates a short-lived, one-time OAuth transaction with cryptographically random state, PKCE S256, provider, exact redirect URI, requested scopes, initiating device and expiry.
3. Launch the provider authorization URL in the system browser or compliant external authentication tab. The provider owns password and MFA entry.
4. Validate callback transaction, expiry, one-time use, provider, exact redirect URI and state. Reject duplicate, unsolicited, malformed or mismatched callbacks.
5. Complete Authorization Code + PKCE exchange using the provider-approved client type and redirect pattern. Never embed a confidential client secret in the APK.
6. Validate issuer, audience, nonce and ID-token signature/claims when OpenID Connect is used.
7. Fetch provider account identity from its authoritative endpoint. Bind to a stable provider subject, not only mutable email/display name.
8. Store only the provider credentials actually issued and consented to. Record actual granted scopes and show the connected account identity.
9. Consume the OAuth transaction. Never persist a raw authorization code.

### 2.2 Vault-compatible callback patterns

The backend credential vault is the target for cross-device restoration. Prefer a backend-controlled HTTPS callback and server-side code exchange when the provider supports the required confidential-client/PKCE configuration. The backend stores the PKCE verifier only as a short-lived encrypted transaction secret, exchanges the code, and immediately consumes the transaction.

If a provider requires a native-app redirect/public-client exchange, the Android app may complete the PKCE exchange using the provider-approved public-client flow. In that case, tokens may exist briefly in app process memory and must be sent directly over authenticated TLS to the AUREON credential broker for vaulting. They must never enter Flutter UI state, persistent plaintext storage, logs, analytics or generic application APIs. This provider-specific alternative requires an explicit security review before implementation.

Do not assume one callback pattern works for every provider. Record the selected pattern and evidence in the provider OAuth matrix.

### 2.3 Callback hardening

- Exact redirect URI registration; no wildcard matching.
- Constant-time state comparison where applicable.
- One-time callback consumption and short transaction lifetime.
- Narrow Android intent filters; prefer verified App Links when supported.
- Never accept authorization codes in generic file/deep-link handlers.
- Never put access or refresh tokens in redirect URLs.
- Redact callback query parameters from logs and diagnostics.

### 2.4 Flutter/Kotlin/backend boundary

Flutter calls a typed provider-authorization repository. Kotlin owns browser handoff, Android callback delivery and platform-specific secure operations. AUREON backend owns OAuth transaction coordination and the credential-vault broker where the selected provider flow permits it.

Never expose raw provider tokens to Flutter widgets or arbitrary MethodChannel calls. Flutter receives only safe state: internal account ID, provider, masked account label, granted-scope summary, connection state, reauth state and safe timestamps. Because direct client-to-provider transfers and metadata calls may require bearer authorization, the credential broker may issue a short-lived access token to the authenticated Kotlin provider adapter over TLS for a specific operation. The token stays in native process memory, is never persisted, logged or returned to Flutter UI, and expires quickly. Refresh tokens are never returned to any client.

## 3. Credential storage decision

### 3.1 Required target: user-consented backend credential vault

The user requires each cloud account to be linked once and automatically restored on another device after AUREON Master Account login. A device-held-only refresh-token model cannot meet this requirement. The target architecture is therefore a user-consented backend credential vault, subject to the security gates below.

- Store refresh credentials only as authenticated encrypted envelopes. No plaintext refresh token in PostgreSQL, logs, queues, analytics, backups or support exports.
- Use envelope encryption: a data-encryption key protects the credential payload with an approved AEAD; a managed KMS/HSM key wraps the data key. Persist only ciphertext/envelope, algorithm and non-secret KMS key reference/version metadata.
- Keep raw KMS key material outside the application database and source repository. Use a dedicated workload identity and narrowly scoped decrypt permission.
- Separate vault service from general API handlers. Only the credential broker may request decrypt/refresh operations; ordinary file/catalog services must not.
- Enforce per-account refresh serialization and atomic refresh-token rotation. A stale worker must never overwrite a newer credential version.
- Audit every vault read/decrypt, refresh, rotation, reauthorization, disconnect and administrative action. Audit payloads contain identifiers and outcomes, never token values.
- Apply key rotation, credential-envelope versioning, backup/restore controls, incident response, access review and independent security testing.
- Obtain explicit, revocable user consent describing that provider refresh credentials are stored encrypted by AUREON to restore linked accounts across devices.
- Review each provider's terms, OAuth verification requirements, restricted-scope assessment and data handling rules before enabling vault storage.
- Do not claim that encryption makes a server-side vault immune to backend compromise. The vault increases AUREON's security responsibility.

The database migration defines an envelope representation and refresh coordination metadata; it does not provision KMS, approve the threat model or enable production credential storage.

### 3.2 Separation from E2E content keys

Provider OAuth credentials and E2E file-content keys are separate trust domains:

- The backend vault may hold provider refresh credentials under the explicit consent and security model above.
- File DEKs, recovery secrets and the user-controlled E2E key hierarchy remain client-controlled. They must not be derived from OAuth tokens or stored in the provider credential vault.
- AUREON Master Account login restores account inventory and authorization status; it does not by itself prove that a new device can decrypt E2E file content. The separate E2E recovery flow must succeed before encrypted content is declared accessible.
- Android Keystore may protect local session material, cached credential handles and locally cached E2E key envelopes. It is not the cross-device source of truth for provider refresh credentials.

### 3.3 Temporary/fallback device-held mode

A device-held-only mode may be used temporarily for a provider only if the user is clearly told that automatic cross-device provider reconnection is not yet available for that provider. It is not an acceptable final substitute for the requested cross-device experience.

If used:
- Generate a random local encryption key and protect its key-encryption key with Android Keystore.
- Encrypt local credential records with authenticated encryption and unique nonces.
- Never store raw refresh tokens in SharedPreferences, plain SQLite, files, logs or Flutter preferences.
- On app data clear, uninstall, device loss or Keystore invalidation, mark that device reauth-required; preserve AUREON inventory and transfer metadata.

Android Keystore makes key extraction harder, but does not make a compromised or rooted running app invulnerable. Do not promise absolute protection.

## 4. Token lifecycle

Each provider account has an independent state:

| State | Meaning |
|---|---|
| connecting | Authorization transaction pending |
| connected | Vault credential is usable and required scopes are present |
| permission_limited | Connected, but some requested scopes were not granted |
| refreshing | One credential-broker refresh operation is in progress |
| reauth_required | Refresh invalid/revoked/expired or provider interaction required |
| disconnected | User disconnected or authorization revoked |
| error | Unexpected provider/configuration failure |

### 4.1 Cross-device restore and refresh

1. New device signs in to the AUREON Master Account and registers its device session.
2. Backend returns provider account inventory, safe labels, granted-scope summaries and connection states; it never returns stored refresh tokens.
3. The credential broker checks each linked account independently. If a valid refresh credential exists, it refreshes/validates provider access as needed and makes the account available without asking the user to re-enter provider credentials.
4. If the provider requires interaction, the broker marks only that account reauth-required and returns a safe challenge state. The user completes the official provider authorization/MFA page manually.
5. Other connected accounts and unrelated transfers continue. Jobs targeting the affected account wait without losing operation IDs, checkpoints, source references or staging files.
6. A successful reauthorization atomically replaces the credential envelope and resumes eligible work after session reconciliation.

AUREON must not read Gmail, scrape authenticator apps, collect OTPs/TOTP seeds, or bypass MFA. MFA is requested only when the provider's policy requires it; it is not required on every AUREON login.

### 4.2 Refresh and rotation rules

- Serialize refresh per provider account using a lease/lock plus credential row version.
- Refresh shortly before access-token expiry, not on every API call.
- If the provider rotates refresh tokens, atomically persist the new encrypted envelope and increment credential version before reporting success.
- Compare-and-swap on credential version; stale workers cannot overwrite a newer token.
- A lease expiry after worker crash requires provider-specific reconciliation. Never blindly replay a possibly rotated token.
- Treat invalid-grant, revoked consent, expiry and interaction-required as reauth-required; do not loop.
- Honor provider throttling and retry guidance.
- Do not assume offline access or refresh-token issuance unless the provider actually grants it.
- Redact token-endpoint errors before logging.

### 4.3 Scope changes

- Store requested and actually granted scopes separately.
- Explain why a feature needs a missing scope before initiating new consent.
- Never silently request broader scopes during routine refresh.
- A scope downgrade becomes permission-limited or reauth-required according to provider response.
- Never infer full Google Drive access if only drive.file was granted.

## 5. OAuth transaction and secret handling

- Store only a hash of OAuth state for lookup/validation; never store raw state beyond the active request context.
- Protect any server-held PKCE verifier as a short-lived encrypted transaction secret; delete it on success, cancellation or expiry.
- Never persist raw authorization codes. Exchange them immediately and consume the transaction once.
- Keep refresh tokens exclusively in the backend vault. The broker may return a short-lived access token to the authenticated native provider adapter when direct provider API access requires it; scope it to the granted provider permissions, keep it in Kotlin process memory only, never persist/log it, and never expose it to Flutter widgets. Do not return refresh tokens to clients.
- Do not put provider credentials, codes, PKCE verifiers or session URLs in outbox payloads, generic audit details, error messages or telemetry.
- Enforce short transaction TTL, replay rejection, rate limits, callback allowlists and CSRF/state validation.

## 6. Disconnect and relink

1. User selects a specific provider account and confirms disconnect.
2. Pause new jobs targeting it. Existing jobs become waiting-for-account and retain operation IDs, source references and staging data.
3. Attempt provider token revocation where supported and possible.
4. Revoke/delete the backend credential envelope and invalidate in-memory access tokens. Record an audited result.
5. Mark the account disconnected in AUREON metadata; preserve file catalog and remote references for relinking/reconciliation.
6. Do not delete provider files, source originals, unrelated cache entries or the AUREON Master Account.
7. On reconnect, relink only after stable provider-subject verification. If identity cannot be proven, create a separate record and require explicit reconciliation.

If offline, disable local use immediately and record revocation-pending where safe. Explain that remote revocation cannot be guaranteed until the provider can be contacted.

## 7. Failure behavior

| Failure | Required result |
|---|---|
| User cancels browser login | Remain disconnected; no false connected record |
| Wrong, missing or expired state | Reject callback and discard transaction |
| Browser/app process killed | Expire or safely resume only the same valid transaction |
| Token exchange timeout | Reconcile safely; never expose code/token |
| Refresh token revoked/expired | Only that account becomes reauth-required; preserve jobs and originals |
| Required scope missing | Permission limited; block only unsupported operations |
| KMS unavailable | Fail closed; do not fall back to plaintext or delete credentials |
| KMS key disabled/destroyed | Mark vault unavailable, alert operators and preserve account/catalog state |
| Refresh worker crashes during rotation | Reconcile credential version and provider semantics; never blind overwrite |
| New-device restore | Restore account inventory; only provider-challenged accounts require official reauthorization |
| Provider full or rate-limited | Keep job queued/paused; preserve source |
| Account disconnected during transfer | Persist checkpoint; resume after reauthorization and session validation |

## 8. Required security tests

- PKCE S256 generation and verifier/challenge matching.
- Reject state mismatch, replay, expiry, duplicate and wrong-provider callbacks.
- Exact redirect URI validation and callback-mode validation.
- No embedded WebView authorization path.
- No client secret in APK, resources, source maps, logs or CI artifacts.
- No token/code/verifier/session URL in logs, crash reports, analytics or outbox.
- Credential envelope authenticated-encryption tamper rejection.
- KMS permission boundary: only credential broker identity can decrypt.
- KMS unavailable/rotation/version mismatch fails closed.
- Concurrent refresh callers produce one effective refresh operation.
- Refresh rotation never allows an old token to overwrite a new token.
- Invalid-grant/revoked consent transitions only the affected account to reauth-required.
- Missing scopes produce permission-limited, not false full access.
- New-device login restores provider inventory without returning refresh tokens.
- User revokes vault consent: credential broker stops use and performs the documented revocation/deletion workflow.
- Disconnect preserves remote files, source originals, transfer jobs and catalog.
- Rooted/custom-ROM and local Keystore tests document realistic limitations for local caches.

## 9. Implementation gates

Do not enable production vaulting until provider registrations and callback patterns exist; exact scopes and provider terms are reviewed; explicit consent UX and privacy disclosures are approved; KMS/HSM and service identity are provisioned; threat model and independent security review pass; credential envelope and refresh-rotation fault tests pass; audit/incident response and backup/restore procedures exist; and cross-device recovery tests pass.

Until these gates pass, the vault remains a design target, not a production feature. Do not claim automatic provider reconnection is implemented.

## 10. Official references

- [IETF RFC 8252 — OAuth 2.0 for Native Apps](https://www.rfc-editor.org/rfc/rfc8252.html)
- [IETF RFC 9700 — Best Current Practice for OAuth 2.0 Security](https://www.rfc-editor.org/rfc/rfc9700.html)
- [Android Developers — Android Keystore system](https://developer.android.com/privacy-and-security/keystore)
- [Android Developers — Cryptography](https://developer.android.com/privacy-and-security/cryptography)
