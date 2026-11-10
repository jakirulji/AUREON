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

## 2. Shared backend configuration (maintainer-only)

AUREON uses one centrally operated Firebase project (`aureon-7f612`) and one Cloudflare Worker/D1 deployment for all end users. The Flutter app contains only public Firebase client configuration and the HTTPS Worker base URL. End users create/sign in to an AUREON Master Account and then connect their own cloud-provider accounts; they never create, paste, save or select Firebase/Cloudflare backend profiles.

The production app is configured with the maintainer's Firebase Web API key, project ID and Worker URL. The Firebase Web API key is a public client identifier, not a server secret. Restrict it to the required Firebase Authentication APIs where compatible with Android and Windows clients. Never embed Firebase service-account credentials, Cloudflare API tokens or Worker root secrets in the app.

The shared Worker verifies Firebase ID tokens, derives the account UID from the signed token subject, and scopes every vault snapshot, recovery challenge, cooldown and audit operation to that UID. Never accept a client-supplied UID as the authorization identity. A successful app build does not prove the deployed Worker, D1 binding or root secret is healthy; the maintainer must verify `/health/ready` and perform authenticated cross-account isolation tests before onboarding users.

The preview CI uses the same public client configuration as the release build, but does not prove the live Firebase/Cloudflare deployment is available. User-specific refresh tokens remain in platform secure storage, not in the shared Worker.


## 3. Cloudflare Workers + D1 (no paid domain required)

1. Create an owner-controlled Cloudflare account and enable MFA.
2. Use the default workers.dev subdomain initially. No custom domain is required.
3. Create the D1 database:

~~~bash
cd backend/cloudflare-worker
npm ci
npx wrangler d1 create aureon-db
~~~

4. The existing owner database `aureon-db` is configured in `backend/cloudflare-worker/wrangler.toml` with Database ID `eec1ed1f-048e-4774-8c4d-0d1b08c0b5c4`. Verify this exact ID in the Cloudflare dashboard before deployment. The `database_name` must remain `aureon-db`.
5. The Worker is configured for Firebase Project ID `aureon-7f612`; verify it matches the owner's Firebase project.
6. Generate a random 32-byte Worker root secret locally and encode it as unpadded base64url. For example, in Windows PowerShell:

~~~powershell
$bytes = New-Object byte[] 32
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($bytes)
$secret = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
$rng.Dispose()
Set-Clipboard -Value $secret
~~~

Paste the clipboard value directly into the Cloudflare Secret prompt. Do not use standard Base64; the Worker expects unpadded base64url.

7. Set the secret directly through Wrangler. The CLI prompts for the value; do not paste it into source files or chat. The deployed Worker expects the exact binding name `AUREON_VAULT_ROOT_SECRET_V1` (not `WORKER_ROOT_SECRET`):

~~~bash
npx wrangler secret put AUREON_VAULT_ROOT_SECRET_V1
~~~

8. Apply migrations and deploy:

~~~bash
npx wrangler d1 migrations apply aureon-db --remote
npx wrangler deploy
~~~

9. Open /health/ready on the deployed Worker. It must return HTTP 200 and {"ready":true} before enabling the app's Cloudflare URL.

The `wrangler.toml` currently points to D1 database ID `eec1ed1f-048e-4774-8c4d-0d1b08c0b5c4`. Before deployment, the maintainer must confirm that this is the intended `aureon-db` resource in the Cloudflare account. The Worker is pinned to Firebase project `aureon-7f612`; do not change one side without updating and reviewing the other.

## 4. Recovery secret custody and production cautions

- Keep an offline emergency copy of the Worker root secret under owner control. Cloudflare Worker Secrets are not an HSM/KMS; the Worker runtime can access the secret.
- Never rotate AUREON_VAULT_ACTIVE_ROOT_VERSION to V2 while V1 envelopes exist unless V1 secret remains configured and a tested rewrap/migration plan is in place. Automated bulk root-secret rewrapping is not yet implemented.
- Cloudflare D1 snapshots have a 900 KB maximum in this prototype. This is not a scalable final account inventory schema; chunked snapshots are a required follow-up before large-scale production.
- Cloudflare recovery requires a verified Firebase email and password reauthentication within five minutes. A thirty-minute cooldown follows successful recovery. Email notifications, passkey/trusted-device step-up, WAF/IP rate controls, and server-side device/session registry are not yet implemented.
- Manual recovery remains independent of Cloudflare: keep the five-key TXT/.key exports and encrypted Vault Recovery Bundle outside Cloudflare. The .key file alone is not the vault ciphertext.
- Do not enable provider OAuth or production user onboarding until independent security review, retention policy, abuse controls, backup/restore drills and deployed end-to-end tests are complete.

## 5. What the owner needs to do now

No action is needed while code and CI work continue. When the project reaches deployment setup, create the Firebase and Cloudflare accounts and provide only non-secret identifiers/URLs through the agreed secure configuration route. Never share passwords, root secrets, service-account JSON, recovery keys or passphrases in chat.
