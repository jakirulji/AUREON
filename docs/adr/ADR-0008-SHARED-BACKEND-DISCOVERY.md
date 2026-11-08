# ADR-0008 — Free shared backend discovery, user-owned infrastructure

**Status:** Accepted owner direction; implementation not yet started  
**Date:** 2026-11-08

## Context

AUREON must not provide a developer-hosted default Firebase project, Cloudflare Worker, D1 database, storage bucket, or shared account backend. Every user owns and configures their own Firebase project and Cloudflare account/Worker/D1. However, a user installing AUREON on a new device must be able to discover the backend configuration associated with their Master Account without manually configuring Firebase and Cloudflare again.

Firebase authentication cannot begin until the client knows which Firebase project to contact. Therefore a small bootstrap/discovery service is required if the user is to log in from an otherwise unconfigured device.

## Decision

Build a minimal, free-tier shared **Backend Discovery Registry**. It is strictly a directory/bootstrap service, not an AUREON account backend.

The registry may store only:
- A random, opaque AUREON Discovery ID (at least 128 bits of CSPRNG entropy).
- Firebase public client configuration needed to initialize Firebase Auth (project ID, API key, auth domain, app ID and only other public SDK fields required by the platform).
- The user's Cloudflare Worker base URL and a non-secret backend/profile version.
- The Firebase issuer/project identity and UID binding needed to prevent unauthorized profile replacement.
- Minimal timestamps/version metadata for update and migration control.

It must never store:
- Firebase passwords, refresh tokens, ID tokens, service-account private keys or admin credentials.
- Cloudflare API tokens, Global API Keys, Worker Secrets or D1 credentials.
- Provider OAuth access/refresh tokens, vault DEKs, Manual Recovery Keys, .key passphrases, E2E file keys, files, file metadata or account backup contents.

The shared service is allowed to see discovery requests and the opaque ID, but must not proxy normal app traffic. All authentication, vault, file, metadata, sync and recovery operations continue directly against the user's own Firebase/Cloudflare infrastructure.

## First-device registration

1. User configures their own Firebase and Cloudflare backend in AUREON.
2. AUREON validates Firebase Auth and the user's own Worker/D1 endpoints.
3. User creates/verifies a Master Account in that Firebase project.
4. The client generates a cryptographically random Discovery ID and shows it in Account settings with copy/export/QR options. It is not a password or recovery key; it is only a non-guessable locator.
5. After email verification, the client registers the locator and public backend configuration with the shared registry using a Firebase ID token.
6. The registry verifies the Firebase RS256 token signature, issuer, audience, expiry, subject and verified-email claim using Google's public JWKs. It binds the entry to the verified Firebase issuer/project plus UID. It never accepts a client-supplied UID as proof of ownership.
7. A registry update is accepted only when the authenticated Firebase issuer+UID matches the existing record. Rebinding to a different Firebase project/account requires an explicit migration flow with proof of control of the old and new identities; never overwrite on email similarity alone.

## New-device login flow

1. First-launch screen presents:
   - **Configure Firebase & Cloudflare** for first-time setup.
   - **Already configured? Log in to your Master Account** for existing users.
   - Optional **Local Only** mode.
2. The existing-user path asks for the AUREON Discovery ID (or scans its QR) before showing/starting Master Account sign-in. This is a locator, not backend configuration and not a secret. It is required because a Firebase project cannot be discovered from Firebase credentials without first knowing the project.
3. The client requests the public backend profile using the opaque locator. Unknown IDs and malformed requests receive generic responses; responses do not reveal email, display name, UID, provider accounts or account existence beyond the locator lookup result.
4. The app initializes Firebase Auth using the returned public Firebase configuration and displays the Master Account login screen.
5. After successful Firebase authentication, the client confirms that the returned ID token issuer/project and UID match the registry binding. If they do not match, login is blocked and the user is directed to the account/backend migration process.
6. Only after identity binding is verified does the app connect to the user's Worker URL and restore account-linked settings/inventory. All sensitive data is fetched from the user's own backend, never from the discovery registry.

If the product later decides to support login using email alone, that requires a separately reviewed privacy-preserving account lookup design. Do not index raw email addresses or use plain SHA-256 email hashes (they are vulnerable to dictionary enumeration). Do not silently weaken the locator requirement.

## Security and privacy

- The Discovery ID is a locator, not an authenticator. Firebase credentials and verified identity remain the authentication mechanism.
- Use at least 128 bits of randomness; never derive IDs from email, UID, phone number or other predictable values.
- Registry write/update/delete operations require a verified Firebase ID token and owner binding checks. Apply strict schema validation, body-size limits, replay protection/version checks, rate limiting, abuse controls and audit events that contain no credentials or tokens.
- Disable request-body/header logging for auth/discovery endpoints; redact authorization headers and all identifiers where possible. Keep retention minimal.
- Return only public Firebase client configuration and Worker URL. Firebase API keys are public client identifiers, not service-account secrets; enforce Firebase Auth, UID authorization, App Check where supported, and secure backend authorization independently.
- Treat Worker URL as an endpoint, not a credential. Never return or accept Cloudflare deployment credentials in the app.
- Add account deletion/unregister, locator rotation, backend URL update, and migration operations with proof-of-control and clear confirmation.
- Discovery outage must not damage or lock already configured installations: saved local profile may continue to be used. A new device may be unable to bootstrap until the registry recovers.
- The registry is not a recovery authority and cannot recover a forgotten Firebase password, lost provider account, lost vault keys or missing encrypted backup.

## Free-tier hosting

Initial implementation target: Cloudflare Workers Free + one D1 database, deployed by the AUREON maintainer. No paid domain is required; use the default workers.dev hostname. The registry stores only a small mapping record and performs a small number of indexed reads/writes.

Current documented Workers Free limit: 100,000 requests/day. Current D1 Free limits: 5 million rows read/day, 100,000 rows written/day, 5 GB total account storage, and 500 MB per database. When D1 daily limits are exceeded, queries fail until reset; when Workers daily request limits are exceeded, requests fail. See:
- https://developers.cloudflare.com/workers/platform/limits/
- https://developers.cloudflare.com/d1/platform/pricing/
- https://developers.cloudflare.com/d1/reference/faq/

This is a $0 initial deployment target, not a guarantee of unlimited capacity or permanent zero cost. Cloudflare may change free-tier terms, and abuse or unexpectedly high adoption can exhaust quotas. Do not enable automatic billing or upgrade to a paid plan. Add conservative rate limits, quotas, monitoring, alert thresholds and graceful failure. Never create additional accounts or databases to evade limits.

## Failure behavior and limits

- If discovery is down or quota-exhausted, already configured devices continue using their locally saved public backend profile; only new-device bootstrap and profile changes are affected.
- Do not cache passwords, refresh tokens or Firebase ID tokens in the registry.
- A lost Discovery ID cannot be guessed from email. Provide an explicit recovery/rotation procedure using an already authenticated device or a user-held exported profile/QR. If no authenticated device or exported locator remains, manual backend setup/relink is required.
- If the user changes Firebase projects, the Firebase identity namespace changes. A matching email does not prove the same Master Account. Require explicit old-account proof plus new-account proof and treat data migration as a separate operation.
- Shared discovery service request quota is consumed by all users' discovery lookups and updates. This is separate from each user's Firebase/Cloudflare quotas, but it is still a small shared dependency owned by AUREON.
- No claim of zero single point of failure: publish a portable profile export/import fallback and preserve local saved configuration on devices that have already completed setup.

## Required tests before production

1. First registration with a user-owned Firebase project and Worker URL; verify no owner/developer Firebase or Cloudflare backend is used.
2. New-device bootstrap using only the AUREON Discovery ID; confirm Firebase config and Worker URL are discovered, then login is validated against issuer+UID.
3. Wrong Firebase project, wrong UID, unverified email, expired token, forged token, replayed update and unauthorized URL replacement are rejected.
4. Unknown locator responses do not disclose email, UID, provider inventory or other personal data.
5. Registry database inspection confirms no passwords, tokens, Worker secrets, provider credentials, vault keys or file metadata are stored.
6. Worker/D1 outage and quota exhaustion preserve existing configured-device operation and fail closed for unverified bootstrap.
7. Locator rotation, account deletion, Firebase project migration and profile export/import are tested.
8. Security review of discovery enumeration, abuse/rate limiting, token validation, privacy logging and cross-account binding before production.

## Product wording

Use: **“Already configured? Enter your AUREON Discovery ID to find your backend and log in.”**

Do not promise “login with email only” until a secure email-to-project discovery design has been reviewed and implemented.
