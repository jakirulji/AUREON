# AUREON owner setup — Firebase + Cloudflare free-tier foundation

This guide is for the project owner. Do not send passwords, service-account JSON, Worker root secrets, private keys, recovery keys or recovery passphrases in chat or GitHub issues.

## 1. Firebase Authentication (Spark)

1. Create a Firebase project under an owner-controlled Google account with MFA enabled.
2. Keep the project on the no-cost Spark plan. Do not enable billing solely for AUREON setup.
3. Open Authentication → Sign-in method and enable Email/Password. Do not enable SMS/phone authentication.
4. Open Project settings → General and copy:
   - Firebase Project ID
   - Web API Key
   - Auth domain
   - App ID
5. The Web API Key is public client configuration, not a service-account secret. Do not use a service-account key in the app. Restrict the API key to Firebase Authentication / Identity Toolkit and Secure Token APIs where the Google Cloud console permits; verify restrictions do not block Android/Windows native requests.
6. Email verification is required by the Worker. Configure the Firebase verification email template and sender settings in Firebase. Check the spam folder during initial tests.

The Flutter app uses Firebase Identity Toolkit and Secure Token REST endpoints directly so the same email/password flow works on Android and Windows without a Firebase native plugin dependency. Passwords are sent only to Firebase over HTTPS and are not persisted by AUREON. The rotating refresh token is stored using flutter_secure_storage (Android Keystore-backed storage / Windows DPAPI-backed storage); ID tokens remain in memory. Signing out clears this device's local refresh token. It does not revoke the Firebase refresh token server-side.

## 2. Configure a local or CI app build

Pass these compile-time values:

- AUREON_FIREBASE_API_KEY — Firebase Web API Key
- AUREON_FIREBASE_PROJECT_ID — Firebase Project ID
- AUREON_FIREBASE_AUTH_DOMAIN — Firebase Auth domain
- AUREON_FIREBASE_APP_ID — Firebase app ID
- AUREON_DISCOVERY_REGISTRY_URL — shared bootstrap registry URL (once deployed)
- AUREON_CLOUDFLARE_API_URL — deployed Worker URL, for example https://aureon-api.your-subdomain.workers.dev

Example local build command (replace values locally; never commit them into source):

~~~bash
flutter build apk --release \
  --dart-define=AUREON_FIREBASE_API_KEY="$AUREON_FIREBASE_API_KEY" \
  --dart-define=AUREON_FIREBASE_PROJECT_ID="$AUREON_FIREBASE_PROJECT_ID" \
  --dart-define=AUREON_FIREBASE_AUTH_DOMAIN="$AUREON_FIREBASE_AUTH_DOMAIN" \\
  --dart-define=AUREON_FIREBASE_APP_ID="$AUREON_FIREBASE_APP_ID" \\
  --dart-define=AUREON_DISCOVERY_REGISTRY_URL="$AUREON_DISCOVERY_REGISTRY_URL" \\
  --dart-define=AUREON_CLOUDFLARE_API_URL="$AUREON_CLOUDFLARE_API_URL"
~~~

On the first configured device, the user signs in, verifies the email, then selects **Create / register Discovery ID**. AUREON generates a random 256-bit locator and registers only public Firebase config + the user's Worker origin. Keep the ID for new devices. On a new device, enter that ID first; AUREON discovers and caches the profile, then verifies Firebase issuer + UID after sign-in. Later launches use the local profile cache and secure refresh token; they do not call the shared registry again. Sign-out clears the local refresh token but deliberately preserves the public backend profile.

The current CI preview intentionally builds with no owner configuration. Account and Cloudflare actions remain disabled in that preview; a green preview build does not mean the live service has been configured.

For GitHub Actions release builds, add these public configuration values as repository Actions variables (the Firebase API key and project ID are public configuration; the Worker URL is also not a secret). Wire them into the final release workflow's --dart-define arguments only when the release workflow is prepared. Do not put the Worker root secret or Firebase service-account credentials into Dart defines.

## 3. Cloudflare Workers + D1 (no paid domain required)

1. Create an owner-controlled Cloudflare account and enable MFA.
2. Use the default workers.dev subdomain initially. No custom domain is required.
3. Create the D1 database:

~~~bash
cd backend/cloudflare-worker
npm ci
npx wrangler d1 create aureon-metadata
~~~

4. Copy the returned database ID into wrangler.toml in place of the all-zero placeholder.
5. Replace REPLACE_WITH_FIREBASE_PROJECT_ID in wrangler.toml with the exact Firebase Project ID.
6. Generate a random 32-byte Worker root secret locally and encode it as unpadded base64url. For example, with Node.js:

~~~bash
node -e "console.log(require('node:crypto').randomBytes(32).toString('base64url'))"
~~~

7. Set the secret directly through Wrangler. The CLI prompts for the value; do not paste it into source files or chat:

~~~bash
npx wrangler secret put AUREON_VAULT_ROOT_SECRET_V1
~~~

8. Apply migrations and deploy:

~~~bash
npx wrangler d1 migrations apply aureon-metadata --remote
npx wrangler deploy
~~~

9. Open /health/ready on the deployed Worker. It must return HTTP 200 and {"ready":true} before enabling the app's Cloudflare URL.

The wrangler.toml database ID and Firebase project ID are placeholders until the owner configures them. Do not deploy while either placeholder remains.

## 4. Shared Discovery Registry (maintainer-owned, free-tier target)

The Registry is separate from every user's Firebase/Cloudflare backend. It stores only an opaque Discovery ID hash, public Firebase client configuration, Worker origin, and Firebase issuer/UID binding. It never stores passwords, tokens, Worker secrets, provider credentials, vault keys, files or file metadata.

1. In the maintainer-owned Cloudflare account, create one D1 database named `aureon-discovery-registry`.
2. Set its database ID in `backend/discovery-registry/wrangler.toml`.
3. Configure a Cloudflare Rate Limiting binding named `REGISTRY_RATE_LIMITER` (initial target 60 requests/minute/IP). The Worker fails closed if it is absent.
4. From `backend/discovery-registry`, install dependencies, apply the remote migration and deploy the Worker. See its README for exact commands.
5. Set `AUREON_DISCOVERY_REGISTRY_URL` to that Worker URL in the app build.

This is not deployed by a GitHub code change. Do not activate billing or a paid plan. Existing devices use the cached public profile and secure refresh token if the Registry is unavailable; new-device bootstrap waits until it returns. A local cache is configuration, not an authenticator: new-device login is blocked unless the Firebase token issuer and UID match the registry binding.

## 5. Recovery secret custody and production cautions

- Keep an offline emergency copy of the Worker root secret under owner control. Cloudflare Worker Secrets are not an HSM/KMS; the Worker runtime can access the secret.
- Never rotate AUREON_VAULT_ACTIVE_ROOT_VERSION to V2 while V1 envelopes exist unless V1 secret remains configured and a tested rewrap/migration plan is in place. Automated bulk root-secret rewrapping is not yet implemented.
- Cloudflare D1 snapshots have a 900 KB maximum in this prototype. This is not a scalable final account inventory schema; chunked snapshots are a required follow-up before large-scale production.
- Cloudflare recovery requires a verified Firebase email and password reauthentication within five minutes. A thirty-minute cooldown follows successful recovery. Email notifications, passkey/trusted-device step-up, WAF/IP rate controls, and server-side device/session registry are not yet implemented.
- Manual recovery remains independent of Cloudflare: keep the five-key TXT/.key exports and encrypted Vault Recovery Bundle outside Cloudflare. The .key file alone is not the vault ciphertext.
- Do not enable provider OAuth or production user onboarding until independent security review, retention policy, abuse controls, backup/restore drills and deployed end-to-end tests are complete.

## 6. What the owner needs to do now

No action is needed while code and CI work continue. When the project reaches deployment setup, create the Firebase and Cloudflare accounts and provide only non-secret identifiers/URLs through the agreed secure configuration route. Never share passwords, root secrets, service-account JSON, recovery keys or passphrases in chat.
