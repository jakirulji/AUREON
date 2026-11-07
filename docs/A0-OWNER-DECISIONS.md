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

**Recommendation:** passkey-first sign-in, one-time offline recovery codes, device-bound rotating sessions. Offer password fallback only if the product owner decides it is needed for users who cannot use passkeys. Email alone must not unlock provider refresh credentials or E2E file keys.

**Owner decision:** Approve passkey-first as the default; decide later whether password fallback is required before public launch.

## 3. Provider OAuth callback and credential vault

**Recommendation:** backend HTTPS callback, backend-held PKCE verifier protected as a short-lived transaction, provider refresh token stored in a user-consented isolated credential broker using managed KMS/HSM. No provider passwords, OTP harvesting or Gmail/Authenticator access.

**Owner decision:** approve the product behavior and separate vault consent UX. This approval does not replace Google app verification, provider terms review or independent security testing.

## 4. Hosting, KMS and monthly budget

**Recommendation:** managed PostgreSQL 18, managed KMS/HSM, secret manager, workload identity, encrypted backups and a separately deployed credential broker. Benchmark Singapore first for latency from Bangladesh, but do not select it without cost and legal review.

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
- Separate credential-broker workload identity for KMS decrypt.
- Room-owned Android local database with Pigeon boundary.
- Transfer Coordinator plus provider-native upload/download adapters.
- No automatic deletion of local originals.
- Metadata-first Drive inventory preserving parent IDs.
- Google Photos albums remain distinct from Drive folders.
- No quota pooling or file sharding to evade provider limits.
