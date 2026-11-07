# ADR-0004 — KMS, Hosting and Operational Deployment Boundary

**Status:** Architecture recommendation; provider/region selection intentionally open  
**Date:** 2026-11-07

## Decision

Keep the backend portable across managed cloud platforms, but require a production managed KMS/HSM service before enabling the provider credential vault. Do not run a self-managed production master key inside the application container, database, environment file or GitHub repository.

## Credential-vault envelope model

1. The credential broker is a separately deployed workload with its own cloud workload identity. The ordinary API/backend process has no KMS decrypt permission for provider refresh credentials.
2. Each credential is encrypted with an authenticated-encryption data key; the data key is wrapped by a managed KMS key. Store only ciphertext, wrapped key, algorithm/format version, nonce/tag, KMS key reference/version and lifecycle metadata.
3. Use a reviewed AEAD implementation and managed KMS SDK. Do not implement cryptographic primitives.
4. Decrypt only in broker memory for the shortest practical time. Redact provider tokens from exceptions, traces, request bodies, metrics and logs.
5. Every KMS decrypt/rewrap operation is attributable to a workload identity and correlated audit event.
6. KMS/network failure fails closed. Never fall back to plaintext, local static keys or a weaker cipher.
7. Rotation uses KMS key versioning and rewraps data keys without exposing provider tokens to ordinary application modules. Revocation and cryptographic destruction require an explicit retention policy and audit.
8. Production KMS keys and credentials are never present in GitHub Actions test environments. Tests use a fake KMS interface that cannot decrypt production data.

## E2E boundary

- The provider credential vault is not the E2E content-key vault.
- E2E file-content keys remain client-controlled and are never sent to the backend KMS for decryption.
- Backend access to provider refresh credentials grants API access within user-approved provider scopes, but does not grant the ability to decrypt client-encrypted file contents.
- Metadata exposure is separately minimized/encrypted according to the E2E and provider inventory design.

## Hosting requirements

The production host must provide:
- Managed PostgreSQL with encrypted storage, automated backups, point-in-time recovery and tested restore.
- Workload identity or short-lived service credentials to access KMS; no static KMS key in env variables.
- Private networking between app and database/KMS where available.
- TLS at every public boundary and modern cipher configuration.
- Secret manager for non-KMS operational credentials.
- Centralized redacted logs, metrics, tracing, alerting and security audit retention.
- Rate limiting/WAF or equivalent edge controls, DDoS controls and abuse monitoring.
- Documented incident response, breach notification, key rotation, backup restore and account deletion procedures.
- Explicit retention and data-region decisions before storing user metadata or provider credentials.

## Candidate regions

Singapore is a reasonable candidate to benchmark first for Bangladesh latency, but it is not selected. Compare Singapore with other provider-supported regions using:
- round-trip latency from Bangladesh,
- managed PostgreSQL/KMS availability,
- backup and cross-region recovery cost,
- data-transfer/egress charges,
- legal/data-residency obligations,
- service reliability and operational complexity.

Do not pick a region solely from latency. Keep account and provider metadata region policy explicit.

## Cost and capacity guardrails

- Model baseline monthly cost at low, expected and high usage before production provisioning.
- Separate database, compute, KMS operations, object storage, egress, logs, backups and email costs.
- Set hard budgets/alerts and rate limits for KMS operations and background scans.
- Never relay all provider file bytes through the backend by default; direct client-to-provider transfer remains preferred.
- Do not pool provider quotas or shard files to evade provider limits.

## Open decisions

- Hosting vendor and region.
- Managed PostgreSQL provider/version and backup retention.
- KMS/HSM vendor, key hierarchy, region and audit retention.
- Secret manager and deployment identity.
- Domain, email delivery and incident contact.
- Monthly budget ceiling and expected storage/transfer profile.

These are deployment-owner decisions. The architecture is designed to make them swappable; no production data should be stored until they are approved.

The credential broker is the deliberate security exception to the modular-monolith deployment: it must be isolated as a small separately deployed workload so that compromise of the general API process does not automatically grant KMS decrypt permission.
