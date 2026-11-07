# AUREON — zero-cost-first deployment and owner actions

**Status:** Architecture direction accepted; no cloud resources have been provisioned and no production service is deployed.  
**Cost policy:** No paid plan, billing upgrade, custom domain, paid storage or other charge without explicit owner approval.

## 1. Selected no-card platform direction

- **Identity:** Firebase Authentication Spark, Email/Password with email verification. SMS verification is excluded.
- **API runtime:** Cloudflare Workers, using the free `workers.dev` hostname initially.
- **Metadata database:** Cloudflare D1.
- **Credential-vault recovery:** a Cloudflare Worker Secret-derived wrapping key, used only by the isolated credential-broker path.
- **Domain:** no purchased custom domain required for initial development and staging.
- **Files:** Android/Windows clients continue direct transfers to official provider APIs. File payloads do not transit Workers or D1.

This is a candidate personal-use zero-cost deployment, not a guarantee of permanent free operation, unlimited capacity or uninterrupted availability. Free quotas and product terms can change.

## 2. Security boundary and recovery

Provider refresh credentials are encrypted using AES-256-GCM. A random per-vault DEK encrypts credential records; a key derived from the Worker Secret wraps the DEK. D1 stores only encrypted envelopes and non-secret metadata.

The Worker runtime can access its configured Secret. Therefore:
- This is **not** HSM/KMS and must not be described as hardware-backed key isolation.
- A compromised Worker deployment or Cloudflare account could potentially expose all credential vaults protected by the secret.
- Restrict the decrypt path, validate Firebase identity and verified email, enforce ownership and scope checks, rate-limit, audit and fail closed.
- Email verification is a recovery signal, not strong proof if the email account itself is compromised. Add passkey/trusted-device step-up where possible, a cooldown, notifications and lost-device/session revocation.
- Keep E2E file-content keys client-controlled and cryptographically separate. Email recovery must never decrypt file content.
- Keep an owner-controlled offline emergency copy of the Worker Secret under a separate secure procedure. Never place it in GitHub, chat, source code, D1 or CI logs. If the secret and its emergency copy are both lost, affected provider accounts may need relinking.
- Version and rotate the secret carefully. Do not delete old key versions until all envelopes have been rewrapped and tested.

## 3. Important backend migration

The existing AUREON backend prototype is Ktor + PostgreSQL. It cannot be deployed unchanged as a Cloudflare Worker and D1 is not a drop-in PostgreSQL replacement.

Required work before switching clients:
1. Implement a TypeScript Cloudflare Worker API.
2. Design D1 tables and migrations for users, devices/sessions, provider inventory, encrypted vault envelopes, recovery challenges, audit events and transfer/Trash metadata.
3. Port and test session/authentication, ownership isolation, provider OAuth transaction handling, credential broker and provider Trash coordination.
4. Preserve API contracts where practical; document deliberate differences.
5. Add integration tests for Firebase JWT validation, cross-user isolation, secret unavailability, recovery abuse, cooldown, secret rotation, D1 restore and provider token refresh.
6. Keep the existing Ktor/PostgreSQL prototype until the Worker implementation passes contract and security tests. Do not delete working code prematurely.

## 4. Free-tier limitations and safe behavior

- Workers and D1 have hard plan quotas and platform limits. On quota exhaustion, API/metadata/recovery operations may be throttled or paused.
- Firebase Spark has email verification limits and abuse controls. No SMS is planned.
- A free plan is not an SLA. Design local job persistence and retry so metadata outages do not lose transfer checkpoints or local originals.
- Already authorized direct provider transfers should continue independently of AUREON's metadata API when technically possible.
- Keep bounded request sizes, pagination, concurrency and per-user rate limits.
- Do not relay file bytes through Workers; Worker request/body limits and CPU/runtime quotas make it unsuitable as a file-transfer engine.
- No region failover or paid backup service is assumed in the free phase. D1 export/restore and Worker Secret emergency recovery must be tested.

## 5. Owner actions — no secrets in chat

1. Create/confirm an owner-controlled Firebase project on Spark; do not upgrade to Blaze.
2. Create/confirm an owner-controlled Cloudflare account; protect it with MFA.
3. Do not purchase a domain or enable paid services.
4. Do not paste passwords, API keys, Firebase service-account private keys, Worker Secrets, OAuth client secrets, provider refresh tokens or recovery codes into chat or GitHub.
5. When accounts are ready, report only that they are ready. We can then guide creation of the Firebase web app/auth settings and Cloudflare Worker/D1 resources.

No cloud resources have been created by this repository change.

## 6. Transfer and network architecture

- Android/Windows native provider adapters upload/download directly to each provider's official API.
- Use provider-native resumable sessions (Google Drive resumable upload, Microsoft Graph upload sessions, Dropbox upload sessions).
- Persist session IDs/URLs as secrets in OS-protected local storage; redact them from logs.
- Resume after process death, network switch, VPN switch, temporary DNS failure and provider throttling.
- Use bounded retries with exponential backoff and jitter; honor Retry-After and reconcile ambiguous outcomes before retrying.
- Keep local originals on every failure. No cleanup unless remote verification succeeds, explicit cleanup opt-in exists and OS permission is granted.
- Never route file bytes through Cloudflare Workers, D1 or an AUREON relay in the normal path.
- AUREON cannot guarantee every ISP/VPN route or provider edge will always be reachable.

## 7. What is not production-ready

- Complete Master Account login/session lifecycle and Firebase integration.
- Worker API and D1 schema/migrations; current Ktor/PostgreSQL code is not yet ported.
- Worker Secret provisioning, broker isolation, recovery policy and key-rotation/restore drills.
- Android/Windows credential-vault clients and cross-platform cryptographic test vectors.
- Production provider OAuth app verification and full Drive scope approval.
- Live direct provider transfer and VPN/ISP network matrix.
- Independent cryptographic, privacy and penetration testing.
- Production provider Trash coordinator and backend-confirmed provider receipts.

Do not enable production credential recovery or destructive Trash/restore/purge actions until the relevant backend execution, ownership checks, receipts and security review are complete.

## 8. Cost and data-safety guardrails

- No paid plan upgrades, paid domain, VPS, paid storage or other charge without explicit owner approval.
- If a free API/database quota is exhausted, metadata sync or account inventory may pause; queue locally and resume later. Do not lose transfer checkpoints or local originals.
- Drive upload/download must continue to use provider APIs directly when the provider account and local client remain authorized, independent of AUREON database quota.
- Do not use multiple provider accounts to pool quotas or bypass provider limits.
- Do not automatically delete local originals or remote objects.
- CI must never upload interim APK/EXE artifacts; final packages are produced once the agreed feature scope is complete.


## 9. Independent dual-recovery procedure

The provider credential vault must have two independent recovery paths:

1. **Manual recovery:** user-held random 256-bit Manual Recovery Key decrypts the local encrypted vault snapshot/portable Recovery Bundle. The key is never transmitted to Cloudflare. This must work while Worker and D1 endpoints are unreachable.
2. **Cloudflare recovery:** Worker Secret-derived key unwraps a separate envelope after Firebase identity and recovery policy checks. This is the alternate route if the Manual Recovery Key is lost.

A portable Recovery Bundle must be exportable and storable outside Cloudflare. It contains encrypted vault data, wrapped DEK envelopes and non-secret version/identity metadata only; never plaintext credentials, DEK, Manual Recovery Key or Worker Secret. Display bundle timestamp/freshness and reconcile stale token/account state before accepting it as current.

The Manual Recovery Key alone cannot reconstruct unavailable ciphertext. If the bundle is stored only in D1, it is not an independent Cloudflare-outage backup. Cache encrypted vault snapshots on authorized devices and provide explicit export/import.

Test matrix before production:
- Cloudflare Worker/D1 blocked + manual key + current bundle => vault opens on clean device.
- Manual key unavailable + Cloudflare healthy => verified Cloudflare recovery works.
- Worker Secret lost + manual key + current bundle => manual recovery works.
- Both paths or all ciphertext copies lost => provider relinking required; no false recovery promise.
- Stale bundle import never silently overwrites newer server/device state.
