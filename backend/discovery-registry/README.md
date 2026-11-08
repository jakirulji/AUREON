# AUREON Discovery Registry

This is the small shared bootstrap directory. It stores only public Firebase client configuration, the user's Worker origin, a SHA-256 hash of the opaque Account Recovery ID, and the Firebase issuer/UID ownership binding. It is not a user-data backend.

## Free-tier deployment

1. Create one Cloudflare D1 database named `aureon-discovery-registry` in the maintainer-owned Cloudflare account.
2. Replace the placeholder `database_id` in `wrangler.toml` with that database's ID.
3. Configure a Cloudflare Rate Limiting binding named `REGISTRY_RATE_LIMITER` for this Worker (start with 60 requests per minute per client IP). The Worker deliberately fails closed when the binding is absent.
4. From this directory, run `npm install`, `npx wrangler d1 migrations apply aureon-discovery-registry --remote`, then `npx wrangler deploy`.
5. Build AUREON with `--dart-define=AUREON_DISCOVERY_REGISTRY_URL=https://<your-worker>.workers.dev`.

No paid domain or paid plan is required for the initial target. Do not enable billing or automatic plan upgrades. Monitor Workers requests, D1 rows read/written and storage; quota exhaustion must not disable already cached devices.

## API

- `POST /v1/profiles/lookup`: public lookup by opaque Account Recovery ID; returns only public bootstrap configuration.
- `POST /v1/profiles`: register or update a profile; requires a verified Firebase ID token. Updates require the expected profile version.
- `POST /v1/profiles/verify`: after new-device Firebase login, verifies that token issuer + UID match the profile binding.
- `DELETE /v1/profiles`: removes the profile after Firebase identity verification.

All normal account, vault, provider, file and metadata traffic must go directly to the user's own Worker. Never add passwords, tokens, Worker secrets, provider credentials, vault keys, file contents or file metadata to this registry.

The registry has not been deployed by this repository change. Configure the D1 database and rate-limit binding only in the owner-controlled Cloudflare account. Keep deployment credentials out of the repository and app.
