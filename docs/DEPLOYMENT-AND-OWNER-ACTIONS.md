# AUREON — deployment plan and owner actions

**Status:** Planning only. No cloud resources have been purchased or provisioned.
**Decision rule:** Do not create paid resources until the owner approves the vendor, region, monthly cap and billing owner.

## 1. What AUREON will need for a real multi-device service

| Component | Purpose | Required before |
|---|---|---|
| HTTPS API runtime | Master Account sessions, device registration, account inventory, sync APIs and transfer coordination | Private end-to-end test |
| Managed PostgreSQL | Users, devices, sessions, provider-account metadata, sync cursors and job state | Persistent hosted test |
| Managed KMS/HSM | Envelope encryption for provider refresh credentials and key rotation | Any production provider-token storage |
| Secret manager + workload identity | Keep DB credentials, OAuth client secrets and service credentials out of GitHub/source code | Any hosted environment |
| Object storage (optional initially) | AUREON-owned encrypted backups/objects, if/when product scope requires it | Only before AUREON-owned object storage |
| Domain + TLS | Stable API and OAuth callback URLs | Provider OAuth production testing |
| Monitoring, backups and alerts | Detect outages, failed jobs, credential refresh failures and restore database after incident | Any persistent hosted environment |

AUREON should not proxy every Drive byte through the API by default. Prefer direct client-to-provider transfer where provider APIs and the security design allow it. This keeps backend bandwidth costs down.

## 2. Recommended deployment shape

Use a small managed container/API runtime, managed PostgreSQL, managed KMS and secret manager. Keep the provider credential broker in a separate workload with its own workload identity and least-privilege access to the vault/KMS.

**Initial vendor shortlist:**
- Google Cloud: Cloud Run + Cloud SQL for PostgreSQL + Cloud KMS + Secret Manager. Natural fit for the first Google Drive integration, but confirm regional availability and total monthly minimums first.
- AWS: ECS/Fargate or App Runner + RDS PostgreSQL + KMS + Secrets Manager. Strong alternative if pricing/region/operational fit is better.
- Azure: Container Apps + Azure Database for PostgreSQL + Key Vault. Viable if Windows/Azure ecosystem becomes the main operational preference.

Do not choose a provider solely because its API has a free tier. Database, KMS, backups, egress, logging and minimum instance settings can create ongoing charges.

## 3. Region and availability

Benchmark Singapore first for Bangladesh latency, then compare the actual supported regions and prices. Do not assume every service (especially managed PostgreSQL and KMS) is available in the same region. Keep the database and API close together to avoid cross-region latency and data-transfer charges. Region selection must also account for privacy/legal obligations and backup location.

## 4. Cost-control strategy

- Start with a development/staging environment, not production-sized capacity.
- Use scale-to-zero API compute where suitable; database costs may remain while provisioned.
- Set budget alerts before enabling paid resources. Alerts are not hard spending caps.
- Limit log retention and avoid logging file names, tokens or personal content.
- Use encrypted automated database backups and test restoration.
- Avoid a self-managed VPS for the production credential vault: it shifts patching, key protection, database backup and incident response onto the project owner.
- Do not purchase object storage until AUREON-owned backup/object-storage functionality actually requires it.

No reliable monthly figure is committed here. Pricing depends on region, database size/availability, backup retention, KMS operations, logs, traffic and support tier; calculate a live estimate after the owner sets a monthly cap.

## 5. Owner decisions needed before provisioning

The owner needs to provide/approve only these decisions:
1. Cloud billing owner: who can create and pay for the cloud account? Use an account controlled by the project owner, with MFA and recovery methods.
2. Preferred vendor: Google Cloud is the first candidate; AWS is the fallback. The owner may choose another provider.
3. Region: Singapore is the first latency candidate, subject to service availability and privacy/legal review.
4. Monthly budget cap in USD (or BDT) for development initially, and a separate production cap later.
5. Whether the owner approves a backend-held, encrypted provider refresh-token vault for the explicit purpose of reconnecting linked Drive accounts across devices. This is separate from AUREON's end-to-end file-content encryption.
6. A domain name, only when OAuth callback and stable API endpoint work begins. Do not buy a domain yet unless the owner already has one.

Never send passwords, OTP seeds, recovery codes, OAuth client secrets, refresh tokens, private keys or billing credentials in chat or commit them to GitHub. Use the cloud provider's secure console/secret manager and grant the minimum required access.

## 6. What the owner does NOT need to do now

- Do not buy a VPS, database, KMS plan, domain or object-storage package yet.
- Do not create Google OAuth production credentials until the OAuth scope and consent design is finalized.
- Do not share Google account passwords or authenticator codes with the developer.
- Do not install interim APK/EXE builds; the project policy is to produce distributable packages only at the final packaging stage.

## 7. Engineering gates before production

1. Complete Master Account sign-in, recovery, device registration and session issuance/rotation.
2. Implement the isolated credential broker with managed KMS/HSM and provider refresh-token rotation.
3. Move provider Trash, restore and purge operations behind a backend coordinator. The server must execute the provider mutation, verify provider state and record its own receipt; a client-supplied reference is not proof.
4. Wire the app to the real authenticated API and account inventory; keep device-local SAF/Windows Recycle Bin Trash separate.
5. Complete Google OAuth verification/scope review, privacy notice, retention/backup policy and independent security review.
6. Deploy staging, run real Google Drive end-to-end tests, then approve production.
7. Only after the complete product slice passes: create final APK and Windows package, test on the Redmi device and Windows laptop, and publish release outputs. Interim CI runs must not upload APK/EXE artifacts.
