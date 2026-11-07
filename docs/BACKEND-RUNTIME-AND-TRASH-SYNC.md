# AUREON backend runtime wiring (A0)

This document describes the current runnable backend boundary. It is not a production deployment approval.

## Runtime configuration

The Ktor module wires PostgreSQL-backed session authentication and the provider Trash repository only when all of these environment variables are configured:

- AUREON_DATABASE_URL: PostgreSQL JDBC URL, using TLS in hosted environments.
- AUREON_DATABASE_USER: least-privilege database role.
- AUREON_DATABASE_PASSWORD: injected from a deployment secret manager; never committed to Git.

Without database configuration, the service deliberately keeps the deny-all session authenticator and reports readiness as unavailable. It does not accept a hard-coded development bearer token.

Apply V001, V002, V003 and V004 migrations through the controlled migration workflow before enabling Trash routes. The app must not run migrations itself.

## Master Account session contract

Clients send only the opaque AUREON session bearer token. The backend computes SHA-256 and looks up sessions.token_hash; it also checks:

- session not revoked and not expired;
- owning user status is active;
- bound device status is active.

The raw bearer token is never stored in PostgreSQL. Session issuance, rotation, passkey authentication and device registration are separate auth workflows and are not yet implemented as a complete product flow.

## Provider credential broker boundary

ProviderAccessTokenBroker is intentionally fail-closed. The production implementation must live in a separately isolated workload and:

1. Resolve the user's explicitly consented provider account and required scopes.
2. Acquire a refresh lease using the PostgreSQL compare-and-swap repository.
3. Decrypt the refresh envelope only through managed KMS/HSM workload identity.
4. Refresh/rotate the provider token and persist only a newly encrypted envelope.
5. Pass a short-lived access token into a scoped callback; never return or log refresh tokens.
6. Mark only the affected account reauth_required when provider policy demands a new consent/MFA challenge.

No provider credential broker implementation, KMS vendor binding, refresh-token exchange, or hosted service is configured in this repository yet.

## Trash sync safety gate

The current /v1/trash/items endpoints are metadata synchronization primitives. Provider outcome references supplied by a client are not cryptographic proof that Google Drive changed state. Production enablement requires a backend Trash coordinator that obtains provider access through the isolated broker, performs the provider operation server-side, verifies the resulting provider state, then records the receipt. Do not expose restore or permanent-delete operations as live UI actions until this gate is met.

Device-local SAF/Win32 Trash remains local-only. Cross-device sync applies only to provider-backed objects with stable provider account/item IDs.

## Required owner/deployment inputs

- Hosting vendor and region, monthly budget and billing owner.
- Managed PostgreSQL and managed KMS/HSM service, IAM/workload identity, rotation and incident-response ownership.
- Google OAuth production client registration, approved scopes, consent screen and verification/security assessment where required.
- Public HTTPS API domain and callback domain.
- Explicit owner approval for the backend credential vault and provider account reconnection behavior.

Until these are supplied and the production security review passes, CI is the only validated environment.
