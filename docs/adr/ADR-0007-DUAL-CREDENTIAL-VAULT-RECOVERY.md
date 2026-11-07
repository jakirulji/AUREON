# ADR-0007 — Independent dual recovery for the provider credential vault

**Status:** Accepted owner requirement; implementation pending  
**Date:** 2026-11-08

## Decision summary

AUREON must not depend exclusively on Cloudflare or exclusively on a user-held key. The provider credential vault uses two independent ways to unwrap the same per-vault DEK:

- Manual Recovery Key: a random 256-bit key held by the owner, used locally on any compatible device to decrypt a portable encrypted Recovery Bundle. It is never sent to Cloudflare.
- Cloudflare recovery: a separate Worker Secret-derived wrapping key, used after Firebase identity verification and the recovery policy. It can recover the vault if the Manual Recovery Key is lost, while Cloudflare remains available.

The two wrapping keys are independent and produce separate wrapped-DEK envelopes. Neither is derived from the other.

## Recovery scenarios

| Situation | Expected path | Requirement |
|---|---|---|
| Cloudflare Worker/D1 unavailable | Manual key | User must have a current encrypted Recovery Bundle or a cached encrypted vault copy |
| Manual Recovery Key lost | Cloudflare recovery | Firebase identity, verified email, step-up where available, cooldown, notification and audit |
| Worker Secret unavailable/lost | Manual key | Current encrypted Recovery Bundle and Manual Recovery Key must exist |
| Manual key lost and Cloudflare unavailable | No guaranteed recovery | Restore Cloudflare first or relink providers if recovery data cannot be obtained |
| Both recovery paths lost | Relink | Never claim an impossible cryptographic recovery |
| Recovery Bundle stale | Manual key opens that snapshot | Show timestamp; reconcile token versions and account inventory when backend returns |

## Portable encrypted Recovery Bundle

The bundle contains only encrypted vault records, wrapped-DEK envelopes, non-secret metadata, schema/algorithm versions and integrity/authentication data. It must never contain the Manual Recovery Key, Worker Secret, plaintext DEK, provider refresh tokens or access tokens.

The owner can export the bundle and store it outside Cloudflare (for example, an independent cloud provider or offline media). AUREON also caches encrypted vault snapshots on authorized devices. A bundle stored only in D1 does not provide Cloudflare-outage independence.

The bundle is versioned, account/vault-bound, integrity-checked and protected against tampering and downgrade. Its export timestamp and freshness are visible. Manual recovery of a stale snapshot may omit recently linked accounts or provider token rotations; it must never silently overwrite newer state.

## Security requirements

- Generate a cryptographically random 256-bit Manual Recovery Key. Never use a human-chosen password as the root.
- Derive the manual wrapping KEK with HKDF-SHA-256 and a unique salt/domain-separation label; encrypt the DEK with AES-256-GCM.
- Cloudflare uses a different high-entropy Worker Secret and independent salt/domain-separation label to wrap the same DEK into a separate envelope.
- Use unique nonces and authenticated metadata; use vetted cryptographic libraries/platform APIs.
- The manual key never enters Worker APIs, logs, telemetry, analytics, crash reports or support bundles.
- Cloudflare recovery validates Firebase token signature/issuer/audience/expiry and verified email, derives owner UID from the token, applies rate limits, one-time challenge, step-up, cooldown, notification, device/session revocation and audit. The client generates an ephemeral device public key; after policy approval the Worker re-wraps the DEK to that device public key and returns only the device-bound envelope, never a plaintext DEK in an API response.
- Email-only recovery is a weaker fallback; prefer passkey or trusted-device step-up.
- Keep E2E file-content keys in a separate client-controlled hierarchy. Neither recovery path can decrypt file content.

## Required verification

1. Manual recovery on a clean device while Worker and D1 endpoints are deliberately blocked.
2. Cloudflare recovery after deleting the local/manual key copy in a test account.
3. Import of a current bundle and a stale bundle, with clear freshness/reconciliation behavior.
4. Wrong key, tampered bundle, wrong account, schema downgrade and corrupted envelope rejection.
5. Worker Secret rotation and recovery after a simulated deployment/secret outage.
6. Cross-platform Android/Windows cryptographic test vectors and independent security review.

## Availability limitation

The Manual Recovery Key alone cannot reconstruct encrypted vault ciphertext that is no longer available. Cloudflare outage independence therefore requires a portable Recovery Bundle or a cached encrypted vault copy stored outside Cloudflare. No system can guarantee recovery if both key paths and all ciphertext copies are lost.
