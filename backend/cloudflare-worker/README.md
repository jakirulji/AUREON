# AUREON Cloudflare Worker foundation

This Worker is the first deployable control-plane slice for Firebase-authenticated vault snapshots and Cloudflare-assisted credential-vault recovery. It never proxies provider file bytes.

## Implemented routes

- GET /health/live — liveness.
- GET /health/ready — D1 and required configuration readiness.
- POST /v1/vault/envelope — accepts a 32-byte DEK over authenticated TLS and returns a Worker-Secret-wrapped AES-256-GCM envelope. The Worker can see the DEK during initial provisioning; this is an explicit server trust boundary, not zero-knowledge.
- GET /v1/vault/snapshot?vaultId=... — returns the authenticated owner's encrypted snapshot for restore.\n- PUT /v1/vault/snapshot — stores validated encrypted credential records and wrapped-key envelopes. Generation starts at 1 and advances exactly one generation; D1 conditional update rejects stale/concurrent writes.
- POST /v1/vault/recovery/challenge — issues a short-lived, single-use challenge for the current vault generation.
- POST /v1/vault/recovery/rewrap — verifies Firebase identity and recent authentication, consumes the one-time challenge, unwraps the Worker envelope in memory, then returns only a P-256 ECDH + HKDF + AES-GCM device-bound envelope.

## Firebase token checks

The Worker verifies RS256 Firebase ID tokens against Google's Secure Token JWK set and validates issuer, audience, expiry/signature, verified email and auth_time (maximum age: five minutes for sensitive recovery operations). The owner UID always comes from the verified token subject.

## Local development

Run npm install, npm test, npm run typecheck and npm run dry-run from this directory.

Create a D1 database, replace the placeholder database_id and Firebase project ID in wrangler.toml, then apply migrations:

- npx wrangler d1 create aureon-metadata
- npx wrangler d1 migrations apply aureon-metadata --remote
- npx wrangler secret put AUREON_VAULT_ROOT_SECRET_V1
- npx wrangler deploy

Generate each versioned Worker root secret offline as 32 random bytes and encode it base64url. AUREON_VAULT_ACTIVE_ROOT_VERSION selects the current version; during rotation provision V2 and switch the active version to 2 while retaining V1 until all V1 envelopes are rewrapped and verified. The active version is selected by AUREON_VAULT_ACTIVE_ROOT_VERSION. During rotation, provision V2 and switch the active version to 2 while retaining V1 until all V1 envelopes have been rewrapped and verified. Keep an encrypted offline emergency copy under owner control. Never commit it or send it through chat. A Worker Secret is not KMS/HSM; compromise of the Worker deployment/account can expose the server-assisted recovery capability.

## Security limitations / release gates

- Recovery challenge is currently bound to a recently reauthenticated, verified Firebase session. Real email notification and passkey/trusted-device step-up integration are not implemented. Do not present challenge issuance as phishing-resistant MFA.
- Per-vault challenge throttling and a post-recovery cooldown are implemented. Cloudflare WAF/IP rate limiting and abuse testing remain required.
- Provider OAuth token refresh/rotation and provider API broker are not implemented.
- Flutter client integration for envelope provisioning, snapshot sync, ECDH device rewrap and decrypt is not implemented. The current client bundle's Cloudflare envelope remains null until wired end-to-end.
- D1 is the online generation authority, not an independent backup. Export/copy the encrypted bundle to an independent failure domain before production.
- Production deployment requires owner-created Firebase/Cloudflare accounts, MFA, reviewed D1 migrations, secret backup/rotation runbooks, privacy/retention policy and independent security review.
- Never store E2E file-content keys or file bytes in this service.
