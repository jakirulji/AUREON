# AUREON — zero-cost-first deployment and owner actions

**Status:** No cloud resources have been purchased or provisioned. This document is an implementation plan, not evidence of a live deployment.  
**Cost policy:** No paid service, billing upgrade, paid domain, paid storage or paid KMS may be enabled without explicit owner approval.

## 1. Chosen zero-cost-first security model

See [ADR-0005 — Zero-cost-first credential vault](./adr/ADR-0005-ZERO-COST-CREDENTIAL-VAULT.md).

- Provider refresh credentials are encrypted on the client using a user-held random recovery key. The backend stores opaque ciphertext only and cannot decrypt it.
- A new device restores encrypted provider inventory after Master Account login and asks for the recovery key once to unlock the vault.
- Android Keystore and Windows OS-protected storage protect the locally unlocked vault key.
- E2E file-content keys remain separate from provider OAuth credential keys.
- No KMS, HSM or server-side plaintext credential vault is required for this phase.
- If the recovery key is lost, affected cloud accounts must be linked again. There is no hidden server recovery bypass.

This is the deliberate zero-cost trade-off. Do not describe this mode as a KMS-backed vault.

## 2. Transfer and network architecture

**File bytes must not pass through AUREON's backend by default.**

- Android/Windows native provider adapters upload/download directly to each provider's official API.
- Use provider-native resumable sessions (Google Drive resumable upload, Microsoft Graph upload sessions, Dropbox upload sessions).
- Persist session IDs/URLs as secrets in OS-protected local storage; redact them from logs.
- Resume after process death, network switch, VPN switch, temporary DNS failure and provider throttling.
- Use bounded retries with exponential backoff and jitter; honor Retry-After and reconcile ambiguous outcomes before retrying.
- Keep local originals on every failure. No cleanup unless remote verification succeeds, explicit cleanup opt-in exists and OS permission is granted.
- Never route file bytes through Cloud Run, Cloudflare Workers, Neon or an AUREON relay in the normal path.

AUREON cannot guarantee that every ISP, VPN endpoint or provider edge will always be reachable. It can avoid adding its own file-relay bottleneck and make transfers recoverable across network changes. Do not promise VPN bypass or geographic censorship circumvention.

## 3. Candidate free-tier services and honest limits

| Component | Candidate | What it is suitable for | Hard limitation / policy |
|---|---|---|---|
| API runtime | Google Cloud Run | Low-volume Ktor metadata/session API staging | Free compute/request allowance is region/usage dependent; outbound internet data transfer can be billed. Singapore is Tier 2 pricing. Requires billing setup. No automatic deployment until owner provisions a project. |
| Database | Neon Free PostgreSQL | Development/staging metadata and test data | 100 CU-hours/project/month, 1 GB/project, 5 GB public network transfer/project/month; compute suspends at quota. Never make direct uploads depend on it. |
| Edge/DNS | Cloudflare Free, optional | DNS, basic edge protection and static assets if a domain is already owned | Does not make Ktor run on Workers. Do not proxy provider file bytes. D1 has hard free read/write limits and is not a drop-in PostgreSQL replacement. |
| Secret Manager | None required for provider tokens in zero-cost mode | Keep only non-user operational secrets out of source control if a host is later approved | Never put user refresh tokens or vault recovery keys in GitHub Actions secrets or a shared deployment secret. |
| KMS/HSM | Deferred | Optional future server-assisted vault mode | Not generally free. Do not create or depend on a KMS key in the zero-cost phase. |

Free-tier limits are not service-level guarantees. Neon can suspend compute after quota exhaustion; Cloud Run networking, logs and other usage can incur charges. Budget alerts are not hard spending caps. Therefore this plan does not claim that a hosted backend can be guaranteed to cost exactly $0 under all traffic.

## 4. Region and Bangladesh/VPN behavior

- Benchmark API latency from Bangladesh to Cloud Run Singapore and Mumbai before selecting a region. Do not assume one is always faster across every ISP/VPN.
- Keep API and database in the same nearby region where available to avoid cross-region database latency and transfer costs.
- Provider file transfers connect directly to Google/Microsoft/Dropbox endpoints from the user's current network. Backend region does not carry file bytes.
- Implement DNS/TLS error classification, connection timeouts, resumable upload/download, exponential backoff, Retry-After, and pause/resume after network changes.
- A VPN can change the route and provider's perceived region; AUREON must not hard-code a VPN exit location or promise that a provider will accept every VPN endpoint.
- No region, DNS provider or CDN can guarantee reachability from every Bangladesh ISP or VPN. Validate with the owner's actual ISP and VPNs before release.
- Do not deploy multi-region failover in the free phase; it introduces additional cost and operational complexity.

## 5. Deployment gate — no provisioning yet

The repository currently has a Ktor/PostgreSQL runtime prototype and CI tests, not a hosted production service. A safe deployment still requires:
1. A cloud account controlled by the owner and explicit approval for the provider/region.
2. A spending cap and billing alerts, acknowledging that alerts are not hard caps.
3. Neon account/project and a private PostgreSQL connection string supplied only through the host's secure secret facility.
4. A Cloud Run project/service identity using GitHub OIDC Workload Identity Federation (no downloaded service-account JSON key).
5. A public HTTPS API endpoint and OAuth callback design.
6. Controlled V001–V004 migrations and backup/restore tests.
7. Real staging tests from Bangladesh networks and at least one VPN route.
8. Security review of Master Account sessions, provider OAuth, client-side vault recovery and account isolation.

Do not provision resources or create billing charges until the owner completes those account-side actions and approves the exact region and spend ceiling. Do not request passwords, OTP seeds, recovery codes, provider refresh tokens or cloud private keys in chat.

## 6. What is not production-ready

- Master Account passkey registration/recovery and complete session issuance/rotation.
- Android/Windows client-side credential vault implementation and cross-platform cryptographic test vectors.
- Production provider OAuth app verification and full Drive scope approval.
- Live direct provider transfer and VPN/ISP network matrix.
- Hosted API/database deployment, automated backups and restore drill.
- Server-side provider Trash coordinator and backend-confirmed provider receipts.
- Independent cryptographic, privacy and penetration testing.

Do not enable production destructive Trash/restore/purge actions until the backend executes provider mutations and verifies the result itself.

## 7. Cost and data-safety guardrails

- No paid plan upgrades, KMS/HSM creation, VPS, domain purchase or object-storage package without explicit owner approval.
- If a free API/database quota is exhausted, metadata sync or account inventory may pause; queue locally and resume later. Do not lose transfer checkpoints or local originals.
- Drive upload/download must continue to use provider APIs directly when the provider account and local client remain authorized, independent of AUREON database quota.
- Do not use multiple provider accounts to pool quotas or bypass provider limits.
- Do not automatically delete local originals or remote objects.
- CI must never upload interim APK/EXE artifacts; final packages are produced once the agreed feature scope is complete.
