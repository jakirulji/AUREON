# AUREON — Security Threat Model (A0)

**Status:** Initial threat-model draft; independent review required before production credentials or user data are accepted  
**Date:** 2026-11-07  
**Scope:** Android-first control plane, provider credential vault, file transfer and client-side E2E encryption

## 1. Security objectives

1. AUREON backend operators and database readers cannot decrypt E2E file content.
2. Provider refresh credentials are stored as encrypted envelopes in D1. A narrowly scoped Cloudflare Worker credential-broker can decrypt them after authorization; this is not zero-knowledge storage.
3. The Worker Secret is the wrapping root for the provider credential vault; it is not an HSM/KMS key. Recovery requires verified Firebase identity plus step-up policy, cooldown and audit. E2E file-content keys remain client-held.
4. Provider access tokens are short-lived, least-scope and delivered only to the authenticated native provider adapter when direct provider API access requires them.
5. One compromised provider account does not expose other provider accounts or Master Account sessions.
6. Local originals and the only verified remote copy are never silently deleted.
7. Imported provider metadata preserves provider hierarchy and is treated as untrusted input.
8. Transfer retries and process death cannot silently duplicate, corrupt or lose the only known-good copy.

## 2. Assets and security classification

| Asset | Sensitivity | Required protection |
|---|---|---|
| Passkey public credential IDs and account identity | High | Ownership checks, access control, audit, rate limiting |
| Passkey private keys | Critical | Remain in authenticator/platform; never uploaded |
| Recovery-code verifier | Critical | Salted/hashed storage, single-use, rotation, audit |
| AUREON session refresh token | Critical | Opaque random value, hashed server-side, rotation/reuse detection, device binding |
| Provider refresh token | Critical | AES-256-GCM envelope encryption in D1; Worker Secret-derived wrapping key; broker-only decrypt; rotation and revocation |
| Provider access token | Critical | Short lifetime, in-memory only, no logs/UI/disk |
| E2E content keys and recovery secret | Critical | Client-controlled; never enter backend or provider credential vault |
| Plaintext file content | Critical | Client process/staging only; encrypted before cloud upload |
| Local source/staging file | High | App sandbox, stable snapshot, explicit cleanup gate |
| File/folder names and provider metadata | High | Minimize, encrypt where feasible, strict owner isolation |
| OAuth code, state and PKCE verifier | Critical | One-time transaction, short TTL, protected verifier, redacted logs |
| Provider upload session URL/token | High | Treat as bearer secret; encrypt at rest, redact and expire |
| Provider quota/usage and transfer state | Medium | Owner isolation, integrity and privacy-safe diagnostics |

## 3. Trust boundaries

1. User authenticator and Android OS.
2. Flutter presentation layer.
3. Kotlin native domain/provider adapter and Room database.
4. AUREON public API and identity service.
5. Cloudflare Worker runtime and Worker Secret management boundary.
6. Cloudflare D1 and export/backup systems.
7. Provider OAuth authorization servers.
8. Provider file APIs and cloud storage.
9. External networks and system browser.

A public repository, CI runner, issue tracker, analytics service and support workflow are outside the secret trust boundary. No production secrets or personal data may enter them.

## 4. Threat register (STRIDE-oriented)

| ID | Threat | Impact | Required mitigation / test |
|---|---|---|---|
| T-01 | Phishing, credential stuffing or stolen AUREON session | Account takeover, provider access | Passkeys, rate limits, short sessions, device binding, rotation/reuse detection, new-device alert |
| T-02 | Recovery-code theft or social engineering | Account takeover | High-entropy single-use codes, hashed verifiers, step-up checks, notification and delayed recovery option |
| T-03 | OAuth login CSRF or account-link substitution | Attacker links their cloud account to victim's AUREON account | Random state, PKCE S256, exact redirect allowlist, initiating user/device binding, one-time transaction, verify provider subject |
| T-04 | OAuth authorization code/verifier leaked in logs | Provider account compromise | TLS, short TTL, one-time code exchange, no request-body/query logging, secret redaction |
| T-05 | D1 dump exposes provider refresh tokens | Long-term provider account compromise | AES-GCM envelopes; D1 alone has no wrapping secret; key versioning and audit |
| T-06 | Compromised Worker deployment or insider abuses Worker Secret | Bulk provider account compromise | Isolated broker code path, least privilege, reviewed deployments, one-time challenges, per-user/account authorization, audit/alerting; acknowledge Worker runtime can access secret |
| T-07 | Worker Secret unavailable or misconfigured | Credential recovery/refresh outage | Fail closed; pause affected account; preserve local unlocked sessions where safe; never fall back to plaintext |
| T-08 | Refresh race overwrites a newer rotated token | Account disconnect or token loss | Per-account lease, compare-and-swap credential version, stale-worker rejection, provider refresh fault tests |
| T-09 | Access token leaks through Flutter state, crash log or disk | Temporary provider data access | Deliver only to native adapter, memory-only, no logs/analytics/UI; short expiry |
| T-10 | Backend compromise attempts to decrypt E2E files | User file confidentiality loss | Content keys never sent to backend; encrypt client-side; independent E2E key hierarchy |
| T-11 | Lost/rooted device or malicious local app | Local files, tokens or cache exposed | Android Keystore, app sandbox, minimum permissions, device revocation, short-lived sessions; acknowledge rooted-device residual risk |
| T-12 | Malicious file name, MIME type, archive path or provider metadata | Path traversal, parser exploit, UI spoofing | Treat as untrusted; normalize paths, never trust MIME, sandbox parsers, size/depth limits, safe archive extraction |
| T-13 | Provider callback or file URL causes SSRF | Internal service access | Fixed provider endpoints, strict host allowlist, no arbitrary URL fetch, redirect validation, egress controls |
| T-14 | Lost/ambiguous upload response triggers blind retry | Duplicate or corrupt cloud objects | Persist operation ID/session first; reconcile remote session/object before retry; idempotency and conflict tests |
| T-15 | Upload failure incorrectly triggers local deletion | Permanent data loss | Original-preservation state machine; verify remote object and key metadata; explicit opt-in and OS permission |
| T-16 | Cross-user or cross-provider account ID substitution | Data disclosure or mutation | Composite ownership FKs, owner scoping in every query, negative integration tests |
| T-17 | Malicious provider response or compromised provider account | Wrong metadata or unexpected file state | Schema validation, provider account isolation, no automatic destructive action |
| T-18 | Abuse of inventory scan/recovery/transfer APIs | Resource exhaustion or account takeover | Per-user quotas, page/concurrency bounds, backoff, recovery rate limits and cooldown |
| T-19 | Logs, traces, crash reports or support bundle contain secrets | Broad secondary exposure | Structured allowlist logging, redaction tests, no request bodies/query secrets, retention controls |
| T-20 | D1 backup theft or restore without wrapping secret | Credential exposure or failed recovery | Encrypted exports, restricted access, restore drills, offline Worker Secret emergency copy and audit |

## 5. Required isolation model

The production Worker must isolate credential-broker code paths from ordinary API handlers. Cloudflare Worker Secrets are available to the deployed Worker runtime and are not an independent HSM boundary; a compromised Worker deployment can potentially use the wrapping root key. Use least privilege, deployment review, strict route separation, rate limits and audit.

The broker must:
- accept only authenticated internal requests tied to a user, provider account and approved operation;
- re-check Firebase identity, verified email where required, account ownership, explicit vault consent, provider status and granted scopes;
- serialize refresh operations and enforce credential-version compare-and-swap;
- return refresh credentials only to provider SDK/HTTP code inside the broker;
- return only a short-lived, scope-limited access token to the authenticated native adapter when direct client-to-provider transfer is required;
- emit an audit event without token contents;
- fail closed on secret availability, policy or audit failure.

This isolated broker is a deliberately small security boundary; the rest of the backend can remain a modular monolith. If the broker cannot be deployed with separate identity and audit controls, do not enable server-side refresh-token vaulting.

## 6. Security invariants

- No plaintext provider refresh token, OAuth code, PKCE verifier, E2E content key, recovery secret or Worker Secret material in source control, logs, telemetry, crash reports or ordinary database columns.
- No provider refresh token returned to Flutter or Android clients.
- No E2E content key or plaintext file content sent to the backend in the normal direct-transfer path.
- No account/provider identity derived from client-supplied user IDs without server ownership verification.
- No broad provider permission is requested without a clear user-facing reason and provider review.
- No local or remote deletion is triggered by upload success alone, account disconnect, cache cleanup, tombstone or sync conflict.
- No multiple-account quota pooling, sharding or bypass of provider limits.
- A security failure pauses the smallest affected scope and preserves known-good data.

## 7. Required security test evidence before A0 exit

- OAuth state/PKCE replay, redirect mismatch, code reuse and cross-device binding tests.
- Cross-user/cross-provider database isolation tests.
- Worker Secret unavailable/rotated, broker authorization and audit-failure fail-closed tests.
- Credential refresh concurrency, lease expiry, stale commit and provider token-rotation tests against PostgreSQL.
- Access-token redaction tests across logs, traces, exceptions and crash paths.
- E2E encryption/decryption test vectors across Android and Windows; independent cryptographic review.
- Malicious archive/path/MIME/metadata tests.
- Upload ambiguity, duplicate reconciliation, network loss, process death, quota, auth expiry and original-preservation tests.
- D1 export/restore, Worker Secret offline recovery and rotation, account revocation and incident-response tabletop exercises.

## 8. Residual risks and explicit limitations

- A rooted/compromised Android OS can observe data while the user opens or edits it; client-side encryption does not protect a compromised endpoint.
- Provider account compromise or provider-side data loss remains outside AUREON's control.
- Backend credential vaulting necessarily gives the isolated broker the ability to obtain provider access tokens within user-granted scopes. This is a deliberate availability/security trade-off for cross-device reconnection and requires independent review.
- Google restricted Drive scopes may require verification and security assessment; AUREON launch eligibility is not guaranteed.
- Android OEM battery policies can delay background work; uninterrupted transfer cannot be guaranteed.
- No architecture document substitutes for penetration testing, cryptographic review, privacy/legal review or incident-response readiness.


## 9. Zero-cost-first provider credential vault

The accepted direction is [ADR-0005](./adr/ADR-0005-ZERO-COST-CREDENTIAL-VAULT.md): provider credentials are AES-256-GCM encrypted in D1, with a per-vault DEK wrapped by a key derived from a Cloudflare Worker Secret. The Worker credential-broker can decrypt after recovery/operation policy checks. This is not zero-knowledge storage and is not HSM-backed.

- A D1 dump alone must not reveal provider refresh tokens. A compromised Worker runtime/deployment with access to the Worker Secret can potentially decrypt them.
- New-device recovery uses verified Firebase identity, step-up policy, cooldown and audit; email-only recovery is a weaker fallback. Loss of the Worker Secret and its offline emergency copy can require provider relinking.
- Android Keystore and Windows OS-protected storage protect the locally unlocked vault.
- Do not describe Worker Secrets as KMS/HSM. Protect the Worker account, secret provisioning and deployment pipeline as critical trust boundaries.
- Independent security review is mandatory before enabling production server-assisted credential recovery.


## 10. Independent dual-recovery controls

- The provider credential vault DEK has two independent wrapped envelopes: one protected by a user-held random 256-bit Manual Recovery Key and one protected by a separate Cloudflare Worker Secret-derived KEK.
- Manual Recovery Key material must never be transmitted to Cloudflare or persisted in server-side storage. Manual unwrap occurs locally on the client.
- Cloudflare outage recovery requires a current encrypted Recovery Bundle or cached encrypted vault snapshot outside the Cloudflare control plane. The Manual Recovery Key by itself cannot recreate missing ciphertext.
- The portable bundle contains encrypted credential records, wrapped DEK envelopes, non-secret metadata and version/integrity data only. It must not contain plaintext credentials, DEK, Manual Recovery Key or Worker Secret.
- Cloudflare recovery remains a server trust boundary. Verify Firebase identity, verified email, recent reauthentication, step-up where available, one-time challenge, cooldown, notification, rate limits, device/session revocation and audit.
- Test both paths independently: manual-key recovery with Worker/D1 unreachable; Cloudflare recovery when manual key is unavailable; stale-bundle reconciliation; wrong-key/tamper/downgrade rejection; secret rotation and loss.
- E2E file-content keys remain separate and client-controlled; neither provider-vault recovery path can decrypt file contents.
