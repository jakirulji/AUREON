# AUREON Cloudflare Worker foundation

This TypeScript Worker is the first control-plane prototype for Firebase-authenticated vault snapshots and Cloudflare-assisted credential-vault recovery. It does not proxy provider file bytes.

## Routes

- GET /health/live — liveness.
- GET /health/ready — D1 and required configuration readiness.
- POST /v1/vault/envelope — accepts a 32-byte DEK over authenticated TLS and returns a Worker-Secret-wrapped AES-256-GCM envelope. The Worker can see the DEK during initial provisioning; this is an explicit server trust boundary, not zero-knowledge.
- GET /v1/vault/snapshot?vaultId=... — returns the authenticated owner's encrypted snapshot for restore.
- PUT /v1/vault/snapshot — stores validated encrypted credential records and wrapped-key envelopes. Key generation starts at 1 and advances by one only during key rotation. Snapshot updates within the same key generation require a strictly newer createdAtEpochMs; conditional D1 updates reject stale/concurrent writes. Encrypted snapshot JSON is capped at 900 KB to stay below the D1 row limit; larger account sets need a future chunked-record schema.
- POST /v1/vault/recovery/challenge — issues a short-lived, single-use challenge for the current vault generation.
- POST /v1/vault/recovery/rewrap — verifies Firebase identity and recent authentication, consumes the one-time challenge, unwraps the Worker envelope in memory, then returns only a P-256 ECDH + HKDF + AES-GCM device-bound envelope.

## Authentication and recovery controls

The Worker verifies RS256 Firebase ID tokens against Google's Secure Token JWK set and validates issuer, audience, expiry/signature, verified email and auth_time (maximum age: five minutes for sensitive recovery operations). Owner UID is always derived from the verified token subject. Challenge issuance is throttled to three per vault per ten minutes; successful recovery applies a thirty-minute per-vault cooldown. Snapshot updates and security audit rows use D1 transactional batches.

## Local development

Run npm install, npm test, npm run typecheck and npm run dry-run from this directory.

Create a D1 database, replace the placeholder database_id and Firebase project ID in wrangler.toml, then apply migrations:

- npx wrangler d1 create aureon-metadata
- npx wrangler d1 migrations apply aureon-metadata --remote
- npx wrangler secret put AUREON_VAULT_ROOT_SECRET_V1
- npx wrangler deploy

Generate each Worker root secret offline as 32 random bytes and encode it base64url. AUREON_VAULT_ACTIVE_ROOT_VERSION selects the active version. Versioned secrets allow old envelopes to remain decryptable during a planned migration. **Automated bulk root-secret rewrapping is not implemented yet; do not rotate the production active version while V1 envelopes exist.** Keep an encrypted offline emergency copy under owner control. Worker Secrets are not KMS/HSM; compromise of the Worker deployment/account can expose the server-assisted recovery capability.

## Explicitly incomplete release gates

- Flutter client integration for envelope provisioning, encrypted snapshot sync, ECDH device rewrap and local unwrap is not implemented. The current client bundle's Cloudflare envelope remains null until wired end-to-end.
- Real email notification and passkey/trusted-device step-up are not implemented. Challenge issuance is not phishing-resistant MFA.
- Cloudflare WAF/IP abuse controls and external rate-limit configuration remain required.
- Provider OAuth refresh/rotation and provider API broker are not implemented.
- D1 is the online generation authority, not an independent backup. Export/copy encrypted snapshots to an independent failure domain before production.
- Production deployment requires owner-created Firebase/Cloudflare accounts, MFA, reviewed D1 migrations, secret backup/rotation runbooks, privacy/retention policy and independent security review.
- Never store E2E file-content keys or file bytes in this service.
