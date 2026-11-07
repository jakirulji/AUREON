# AUREON — Privacy and Data Governance Baseline

**Status:** Internal design draft; not a public privacy policy or legal advice  
**Date:** 2026-11-07

## 1. Purpose and launch constraint

This document defines the minimum data-governance rules required before AUREON stores production account credentials, provider metadata or transfer state. It is not a substitute for jurisdiction-specific legal review, a published privacy notice, terms of service or provider approval.

No production user data should be accepted until the operator, legal entity, applicable jurisdictions, hosting region, subprocessors, retention periods and user-rights process are identified and approved.

## 2. Data inventory

| Data category | Examples | Intended processing | Default handling |
|---|---|---|---|
| Master Account | Passkey public credential, verified email, account ID | Authentication, recovery and security notices | Minimize; never store passkey private keys |
| Device registry | Device ID, public key, platform, last-seen | Session binding, revocation and device restore | Retain only while device/account is active plus defined security period |
| Provider identity | Provider, provider subject, masked account label, granted scopes | Connect and restore provider accounts | Store only required identifiers; encrypt sensitive metadata |
| Provider authorization | Refresh token, expiry, scopes, status | Silent reconnect and provider API authorization | Explicit consent; KMS-wrapped envelope; broker-only decrypt |
| File inventory metadata | Provider item IDs, parent IDs, MIME type, size, encrypted name/path envelope | Unified file browser, search and sync | Metadata-first; encrypt names/paths where feasible; no default full-content download |
| File content | User documents, photos and archives | Client-side encryption, upload/download | E2E encrypted before provider upload; backend does not receive plaintext in normal path |
| Transfer operations | Operation ID, provider session, offsets, retries, status | Resume, reconcile and report progress | Minimize; encrypt provider session secrets; redact logs |
| Cache and staging | Offline copies, source snapshots, temporary chunks | Offline access and resumable transfer | App-private storage where possible; user controls cache; cleanup safety rules |
| Diagnostics | Error codes, performance counters, app version | Reliability and support | Allowlist fields; no file names, content, access tokens or raw URLs by default |
| Security audit | Login, device revocation, vault consent, KMS access | Fraud detection and incident response | Append-only controls, limited access, documented retention |

## 3. Purpose limitation and consent

- Explain provider, account identity, scopes, purpose and cross-device credential storage before OAuth consent.
- Provider refresh-token vaulting requires a separate explicit AUREON consent. Provider OAuth consent alone is not silently treated as consent to AUREON server-side vaulting.
- Scope expansion requires a new consent event and clear explanation.
- Do not read Gmail, authenticator applications, SMS, browser cookies or provider passwords to satisfy MFA.
- Do not use cloud account content for advertising, model training or unrelated analytics.
- Do not use multiple provider accounts to pool quotas or evade provider limits.

## 4. Encryption and access boundaries

- File content is encrypted client-side before upload; backend operators and KMS cannot decrypt E2E file content.
- Provider refresh credentials are encrypted separately under a managed KMS/HSM envelope and accessible only to the isolated credential-broker workload.
- E2E content keys and provider OAuth credentials are different key domains.
- TLS protects network traffic; database encryption-at-rest and backup encryption are also required.
- Filenames, folder names, provider IDs and usage metadata may remain visible to the provider and/or limited AUREON control-plane services depending on the chosen metadata-encryption mode. The published privacy notice must describe this precisely rather than claiming that all metadata is E2E encrypted.

## 5. Retention and deletion rules

Retention periods are not yet selected. Before launch, define a schedule for each category in section 2, including backups and audit logs.

Mandatory product behavior:
- Disconnecting a provider revokes/removes AUREON authorization where supported; it does not delete remote provider files.
- Deleting an AUREON account removes or schedules removal of account identity, sessions, provider credential envelopes, device registry and AUREON metadata according to the approved retention/legal-hold policy.
- Provider originals are never deleted as an account-deletion side effect unless the user separately requests and confirms a provider-side deletion flow.
- Backups expire under a documented rotation schedule; deletion from primary storage must not be represented as immediate physical erasure from immutable backups.
- Recovery-code verifiers, session hashes, OAuth transaction records and KMS audit events each need explicit retention periods.
- Cache cleanup must never delete the only source original, a staging snapshot required for a transfer, or a canonical remote object.

## 6. Subprocessors and international transfers

Maintain a public subprocessor register before launch. It must list the actual providers used for:
- application hosting and compute,
- managed PostgreSQL and backups,
- managed KMS/HSM and audit logging,
- email delivery,
- observability and crash reporting,
- customer support and payment processing if introduced.

Select data regions only after latency, service availability, cost, applicable law and cross-border transfer requirements are assessed. Singapore is a candidate for latency benchmarking from Bangladesh, not a selected or legally approved region.

## 7. User rights and support process

Define and test a process for:
- access/export of AUREON-held account and metadata,
- correction of account/profile details,
- provider disconnect and credential revocation,
- account deletion and backup expiry,
- correction of inaccurate inventory state,
- security incident reporting and account recovery.

Support staff must not request provider passwords, OTPs, recovery codes, passkey private keys, E2E recovery secrets or plaintext provider tokens. Support tools must not have KMS decrypt permission.

## 8. Provider-specific compliance gates

### Google Drive
- Restricted scopes require Google's verification process.
- If restricted-scope data is stored on or transmitted through AUREON servers, complete the applicable security assessment before production access.
- The product must clearly distinguish per-file drive.file access from full-library access.
- AUREON must not promise a full Drive inventory unless the granted scope and provider approval actually permit it.

### Google Photos
- Treat Google Photos as a distinct product/API surface.
- Use user-mediated Picker flows for existing library media where required by current API policy.
- Do not promise unrestricted background enumeration or fabricated folder hierarchy.

### Other providers
- Re-check each provider's data-use, OAuth, storage, caching, deletion, branding and review terms before launch.

## 9. Open legal and operational decisions

- Legal entity/operator and applicable jurisdictions.
- Public privacy policy, terms of service and cookie/website notice if applicable.
- Data controller/processor roles and DPA requirements.
- Retention periods, backup expiry and legal hold.
- Hosting/KMS provider, region and subprocessors.
- Incident contact, breach response and notification timelines.
- Support access controls and user-rights request workflow.
- Google restricted-scope verification/security-assessment eligibility and cost.

A0 may document these requirements, but only the project owner and qualified legal/security reviewers can approve the actual public policy and compliance posture.
