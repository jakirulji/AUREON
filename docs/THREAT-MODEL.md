# AUREON — Security Threat Model (A0)

**Status:** Initial threat-model draft; independent review required before production credentials or user data are accepted  
**Date:** 2026-11-07  
**Scope:** Android-first control plane, provider credential vault, file transfer and client-side E2E encryption

## 1. Security objectives

1. AUREON backend operators and database readers cannot decrypt E2E file content.
2. In the zero-cost-first mode, provider refresh credentials are stored only as client-encrypted envelopes; the backend cannot decrypt them.
3. The vault recovery key remains user-held and is never transmitted to the backend. A future separately consented KMS-backed mode requires a new threat review.
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
| Provider refresh token | Critical | User consent, KMS envelope encryption, broker-only decrypt, rotation and revocation |
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
5. Isolated credential-broker workload and managed KMS/HSM.
6. PostgreSQL and backup systems.
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
| T-05 | Database dump exposes provider refresh tokens | Long-term provider account compromise | KMS-wrapped envelopes; database alone cannot decrypt; key versioning and audit |
| T-06 | Ordinary API service or insider abuses KMS decrypt | Bulk provider account compromise | Separate credential-broker deployment/workload identity; broker-only KMS decrypt; allowlisted operations; per-user/account authorization; audit/alerting |
| T-07 | KMS outage or IAM denial causes unsafe fallback | Plaintext secret exposure | Fail closed; pause only affected account; never fall back to static local key or plaintext |
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
| T-18 | Abuse of inventory scan/KMS/transfer APIs | Cost spike or denial of service | Per-user quotas, page/concurrency bounds, backoff, budget alerts, KMS operation caps |
| T-19 | Logs, traces, crash reports or support bundle contain secrets | Broad secondary exposure | Structured allowlist logging, redaction tests, no request bodies/query secrets, retention controls |
| T-20 | Backup theft or restore to insecure environment | Persistent data and key exposure | Encrypted backups, restricted restore identities, restore drills, KMS region/key controls and audit |

## 5. Required isolation model

A normal API process must not have KMS decrypt permission for provider refresh credentials. The production credential broker must be a separately deployed workload with a distinct cloud workload identity and a narrowly scoped KMS policy.

The broker must:
- accept only authenticated internal requests tied to a user, provider account and approved operation;
- re-check account ownership, explicit vault consent, provider status and granted scopes;
- serialize refresh operations and enforce credential-version compare-and-swap;
- return refresh credentials only to provider SDK/HTTP code inside the broker;
- return only a short-lived, scope-limited access token to the authenticated native adapter when direct client-to-provider transfer is required;
- emit an audit event without token contents;
- fail closed on KMS, policy or audit failure.

This isolated broker is a deliberately small security boundary; the rest of the backend can remain a modular monolith. If the broker cannot be deployed with separate identity and audit controls, do not enable server-side refresh-token vaulting.

## 6. Security invariants

- No plaintext provider refresh token, OAuth code, PKCE verifier, E2E content key, recovery secret or KMS key material in source control, logs, telemetry, crash reports or ordinary database columns.
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
- KMS deny/failure, broker identity and audit-failure fail-closed tests.
- Credential refresh concurrency, lease expiry, stale commit and provider token-rotation tests against PostgreSQL.
- Access-token redaction tests across logs, traces, exceptions and crash paths.
- E2E encryption/decryption test vectors across Android and Windows; independent cryptographic review.
- Malicious archive/path/MIME/metadata tests.
- Upload ambiguity, duplicate reconciliation, network loss, process death, quota, auth expiry and original-preservation tests.
- Backup restore, key rotation, account revocation and incident-response tabletop exercises.

## 8. Residual risks and explicit limitations

- A rooted/compromised Android OS can observe data while the user opens or edits it; client-side encryption does not protect a compromised endpoint.
- Provider account compromise or provider-side data loss remains outside AUREON's control.
- Backend credential vaulting necessarily gives the isolated broker the ability to obtain provider access tokens within user-granted scopes. This is a deliberate availability/security trade-off for cross-device reconnection and requires independent review.
- Google restricted Drive scopes may require verification and security assessment; AUREON launch eligibility is not guaranteed.
- Android OEM battery policies can delay background work; uninterrupted transfer cannot be guaranteed.
- No architecture document substitutes for penetration testing, cryptographic review, privacy/legal review or incident-response readiness.


## 9. Zero-cost-first provider credential vault

The accepted current design is [ADR-0005](./adr/ADR-0005-ZERO-COST-CREDENTIAL-VAULT.md): the client encrypts provider refresh credentials with AES-256-GCM, per-account data keys and a user-held random recovery key. The backend stores ciphertext only and has no decrypt capability.

- A database dump or API-process compromise must not reveal provider refresh tokens.
- New-device restore requires the user to enter the recovery key once; loss of that key requires provider relinking.
- Android Keystore and Windows OS-protected storage protect the locally unlocked vault.
- Do not add a shared server-side environment master key as a substitute for managed KMS.
- The previous isolated KMS credential-broker design is deferred until a paid, owner-approved managed KMS/HSM deployment and independent review exist.
