# AUREON owner setup — Firebase + Cloudflare free-tier foundation

This guide is for the project owner. Do not send passwords, service-account JSON, Worker root secrets, private keys, recovery keys or recovery passphrases in chat or GitHub issues.

## 1. Firebase Authentication (Spark)

1. Create a Firebase project under an owner-controlled Google account with MFA enabled.
2. Keep the project on the no-cost Spark plan. Do not enable billing solely for AUREON setup.
3. Open Authentication → Sign-in method and enable **Email/Password** and **Email link (passwordless sign-in)**. Do not enable SMS/phone authentication.
4. Open Project settings → General and copy:
   - Firebase Project ID
   - Web API Key
5. The Web API Key is public client configuration, not a service-account secret. Do not use a service-account key in the app. Restrict the API key to Firebase Authentication / Identity Toolkit and Secure Token APIs where the Google Cloud console permits; verify restrictions do not block Android/Windows native requests.
6. Email verification is required by the Worker. Configure the Firebase verification email template and sender settings in Firebase. Check the spam folder during initial tests.
7. Email Link provider enablement is only Firebase-side configuration. The AUREON app must separately implement the passwordless email-link request/completion flow, Android App Links and Windows link handoff before users can sign in passwordlessly. This flow is tracked in A2 of `AUREON-PLAN.md`; do not mark it complete merely because the provider is enabled.

The Flutter app uses Firebase Identity Toolkit and Secure Token REST endpoints directly so the same email/password flow works on Android and Windows without a Firebase native plugin dependency. Passwords are sent only to Firebase over HTTPS and are not persisted by AUREON. The rotating refresh token is stored using flutter_secure_storage (Android Keystore-backed storage / Windows DPAPI-backed storage); ID tokens remain in memory. Signing out clears this device's local refresh token. It does not revoke the Firebase refresh token server-side.

## 2. Configure AUREON with your own backend profile

AUREON does not ship with a shared developer-hosted Firebase or Cloudflare backend. Each user must create and own their Firebase project and Cloudflare Worker/D1 deployment.

After building/installing the app:

1. Open **Account → Your backend**.
2. Enter a profile name, Firebase Web API Key, Firebase Project ID and the HTTPS URL of your own deployed Cloudflare Worker.
3. Save and use the profile, then create/sign in to the AUREON Master Account in that Firebase project.
4. AUREON binds the saved profile to the Firebase issuer/project ID, authenticated UID and canonical Worker identity. A profile already bound to a different identity cannot be silently reused; create a separate profile for another identity.
5. The active profile is saved locally and restored on later launches. Firebase refresh tokens are stored in secure storage under a project-and-UID-specific namespace, so tokens from one Firebase project cannot be reused against another.

The Firebase Web API Key, project ID and Worker URL are public client configuration—not secrets. Never enter or store service-account JSON, Firebase private keys, Cloudflare Worker Secrets, passwords, OAuth refresh tokens or recovery keys in a backend profile. Profile records remain device-local; they are not uploaded to a shared AUREON service.

The preview CI intentionally has no owner backend configuration. A green preview build does not mean a Firebase project or Worker has been deployed or tested. Compile-time `AUREON_FIREBASE_API_KEY`, `AUREON_FIREBASE_PROJECT_ID` and `AUREON_CLOUDFLARE_API_URL` are not required for normal user setup; the app's default configuration is empty and fails closed until a user saves their own profile.


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

## 4. Recovery secret custody and production cautions

- Keep an offline emergency copy of the Worker root secret under owner control. Cloudflare Worker Secrets are not an HSM/KMS; the Worker runtime can access the secret.
- Never rotate AUREON_VAULT_ACTIVE_ROOT_VERSION to V2 while V1 envelopes exist unless V1 secret remains configured and a tested rewrap/migration plan is in place. Automated bulk root-secret rewrapping is not yet implemented.
- Cloudflare D1 snapshots have a 900 KB maximum in this prototype. This is not a scalable final account inventory schema; chunked snapshots are a required follow-up before large-scale production.
- Cloudflare recovery requires a verified Firebase email and password reauthentication within five minutes. A thirty-minute cooldown follows successful recovery. Email notifications, passkey/trusted-device step-up, WAF/IP rate controls, and server-side device/session registry are not yet implemented.
- Manual recovery remains independent of Cloudflare: keep the five-key TXT/.key exports and encrypted Vault Recovery Bundle outside Cloudflare. The .key file alone is not the vault ciphertext.
- Do not enable provider OAuth or production user onboarding until independent security review, retention policy, abuse controls, backup/restore drills and deployed end-to-end tests are complete.

## 5. What the owner needs to do now

No action is needed while code and CI work continue. When the project reaches deployment setup, create the Firebase and Cloudflare accounts and provide only non-secret identifiers/URLs through the agreed secure configuration route. Never share passwords, root secrets, service-account JSON, recovery keys or passphrases in chat.
