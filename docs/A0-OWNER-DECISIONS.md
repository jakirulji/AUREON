# AUREON — A0 Owner Decisions Required

**Status:** Recommendations prepared; owner approval required before A1 production implementation  
**Date:** 2026-11-07

This list separates engineering work that can be completed in the repository from decisions that require the project owner's product, budget, account or legal authority. No choice below is silently treated as approved.

## 1. Google Drive launch permission mode

**Requirement already established:** index existing Drive files and folders, preserve real hierarchy and expose virtual categories without moving or renaming originals.

| Mode | Access | Trade-off |
|---|---|---|
| A — Full-library read + AUREON-managed writes | drive.readonly + drive.file | Reads/downloads all existing Drive files; writes limited to AUREON-created/opened/selected files. Restricted-scope verification and security assessment still apply to drive.readonly. |
| B — Full file-manager access | drive | Reads and writes arbitrary existing Drive items, but is a broad restricted scope with higher verification, assessment and user-trust burden. Product must still block automatic deletion. |
| C — Per-file access only | drive.file | Narrowest scope but cannot meet the existing full-library inventory requirement. |

**Recommendation:** Mode A for the first release. It meets existing-file discovery and read/download needs while limiting write scope. Add Mode B only if moving/renaming/uploading into arbitrary pre-existing folders is a confirmed launch requirement and Google approves the scope.

**Owner decision:** Approve Mode A for A1, or explicitly request Mode B.

## 2. Master Account sign-in and recovery

**Accepted direction:** Firebase Spark Email/Password with verified email for Master Account sign-in; SMS excluded. Add passkeys/trusted-device step-up where feasible. Email-only recovery is a weaker fallback and must include cooldown, notifications, rate limits and device/session revocation. Email recovery can restore only the provider credential vault, never E2E file-content keys.

**Owner decision:** Approve passkey-first as the default; decide later whether password fallback is required before public launch.

## 3. Provider OAuth callback and credential vault

**Accepted direction:** provider credentials stored as AES-256-GCM encrypted envelopes in Cloudflare D1; a narrowly scoped Cloudflare Worker broker unwraps the per-vault DEK using a Worker Secret-derived key after authorization. This is not HSM/KMS and grants the Worker runtime a real decryption capability. No provider passwords, OTP harvesting or Gmail/Authenticator access.

**Owner decision:** approve the product behavior and separate vault consent UX. This approval does not replace Google app verification, provider terms review or independent security testing.

## 4. Hosting and zero-cost platform

**Accepted direction:** Firebase Authentication Spark + Cloudflare Workers + Cloudflare D1, initially using provider default domains and no purchased custom domain. This avoids OCI payment-card onboarding but has hard free-tier quotas and is not a permanent availability or $0 guarantee. Worker Secrets are not KMS/HSM.

**Owner decisions required:**
- Preferred cloud vendor (AWS, Google Cloud, Azure or another provider).
- Maximum monthly budget for development and production.
- Whether Singapore is an acceptable candidate region.
- Who owns the cloud billing account and incident/security contact.

No paid cloud resources should be provisioned without explicit approval.

## 5. Android support baseline

**Recommendation:** minimum API 26, prototype compile/target API 36, Room 2.8.5, WorkManager 2.12.0, Pigeon 29.1.1. Raise target API to 37 when the stable SDK package is published and release policy/device validation supports it. These are engineering candidate pins; Android build/prototype and release-time SDK policy checks remain required.

**Owner decision:** no immediate decision required unless broader support for older Android versions is a product priority.

## 6. E2E encryption and recovery

**Recommendation:** keep file-content keys client-controlled and separate from provider credentials. Do not claim production E2E readiness until the protocol, recovery workflow, Android/Windows test vectors and independent cryptographic review are complete.

**Owner decision:** approve the user experience for recovery-key backup/recovery and accept that losing all recovery material may make encrypted content unrecoverable. Security review remains mandatory.

## 7. Privacy, legal and operational ownership

**Owner decisions required:**
- Legal entity/operator and launch jurisdictions.
- Public support email and incident contact.
- Actual retention periods and backup expiry.
- Public privacy notice and terms after the real infrastructure/subprocessors are selected.
- Whether AUREON will be an individual project or a commercial service at launch.

Do not publish a generic privacy policy as if these details were already known.

## 8. What does not require a decision now

The following are already recommended or validated and should not be reopened without evidence:
- PostgreSQL 18 schema baseline and additive migration strategy.
- Kotlin/Ktor modular-monolith backend starting point.
- Isolated credential-broker code path within Cloudflare Worker, with explicit acknowledgement that Worker Secret is not HSM/KMS.
- Room-owned Android local database with Pigeon boundary.
- Transfer Coordinator plus provider-native upload/download adapters.
- No automatic deletion of local originals.
- Metadata-first Drive inventory preserving parent IDs.
- Google Photos albums remain distinct from Drive folders.
- No quota pooling or file sharding to evade provider limits.


## Cloudflare Worker implementation status (2026-11-08)

- A TypeScript Worker/D1 foundation is committed under `backend/cloudflare-worker/`; it is not deployed.
- Firebase RS256 token verification, verified-email checks, recent-auth checks on sensitive routes, encrypted snapshot validation, monotonic generation CAS, challenge throttling/cooldown, audit persistence and device-bound envelope rewrapping are implemented as prototype code.
- The Worker Secret is a server-side trust boundary, not KMS/HSM. Initial envelope provisioning sends the DEK to the Worker over TLS so it can create the server envelope; the Worker can access that DEK in memory.
- Client integration, passkey/trusted-device step-up, email notifications, WAF/IP abuse controls, provider OAuth broker, external backup replication and independent security review remain incomplete.
- Owner provisioning remains required: Firebase project, Cloudflare account, D1 database, Firebase project ID, and Worker Secret configured privately. Never send secrets through chat.

## Dual recovery requirement — owner-approved (2026-11-08)

- The owner requires two independent recovery paths for the provider credential vault: a manually held random recovery key and a Cloudflare-assisted recovery path.
- Either path should be sufficient to unwrap the same vault DEK, provided the encrypted vault ciphertext is available.
- The manual key must never be sent to Cloudflare. It must work locally on a compatible device using an encrypted portable Recovery Bundle or cached encrypted vault snapshot.
- Cloudflare recovery should remain available if the manual key is lost, using Firebase verified identity and recovery policy.
- The encrypted Recovery Bundle must be exportable and storable outside Cloudflare. A bundle stored only in D1 is not an independent fallback.
- The two recovery KEK hierarchies must be cryptographically independent. E2E file-content keys remain separate and client-controlled.
- Recovery must be tested under Cloudflare outage and manual-key-loss scenarios before production.

## Provider re-link and organization disaster recovery — owner requirement (2026-11-08)

- Even if all five Manual Recovery Keys and the encrypted .key export are lost, the user must be able to reconnect cloud providers through official OAuth and rebuild the current file index from provider APIs.
- Re-indexing must preserve the provider's actual folder hierarchy and must not move, rename, duplicate or delete existing provider files.
- AUREON-only organization (tags, favorites, virtual collections, custom views/sort, sync preferences and other user-created metadata) must have an independent encrypted backup, separate from provider credentials and all recovery-key material.
- The independent metadata backup must be available outside the Cloudflare-only failure domain and cached encrypted on authorized devices. It must not contain provider tokens, recovery keys, DEKs, E2E content keys or device-specific filesystem permissions/paths.
- Restore is a conflict-aware merge keyed by stable provider account subject + provider object ID. Provider state remains authoritative for current files and folder hierarchy.
- If the metadata backup is also lost, provider re-link can still restore current provider files and original provider folder structure, but AUREON-only organization cannot be guaranteed. Device-local folders and OS permissions must be selected again on each device.
