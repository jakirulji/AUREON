# ADR-0002 — Master Account Authentication and Recovery

**Status:** Provisional recommendation; product/security approval required before production identity implementation  
**Date:** 2026-11-07

## Decision

Use a passkey-first Master Account with a separate, high-entropy recovery-code path. Keep Master Account authentication, provider OAuth authorization and E2E content-key recovery as three separate security domains.

### Proposed authentication model

1. **Primary sign-in:** WebAuthn/FIDO2 passkeys using platform authenticators or cross-device passkeys. Validate challenge, origin, RP ID, signature counter/backup eligibility where applicable, user verification policy and credential revocation server-side.
2. **Additional sign-in method:** optional password fallback only if product research shows it is necessary. If enabled, store only a modern password hash (Argon2id with reviewed parameters), enforce breached-password checks where feasible, rate limits and credential-stuffing protections. Never store plaintext or reversible passwords.
3. **Recovery:** generate multiple one-time high-entropy recovery codes. Store only salted/hashed verifiers server-side, display once, support rotation and revoke all previously issued codes after recovery. Encourage offline storage.
4. **Email:** verified email is a notification and recovery-contact channel, not sufficient by itself to unlock the credential vault or recover E2E content keys. Email account compromise must not silently grant provider-token or E2E-key access.
5. **Device binding:** register a per-device public key. Bind sessions to the registered device and require reauthentication for device revocation, recovery changes, vault consent changes and other sensitive operations.
6. **Sessions:** short-lived access credentials plus opaque rotating refresh sessions stored hashed server-side, with device association, expiry, reuse detection, rotation and remote revocation. Do not reuse provider refresh tokens as AUREON sessions.
7. **Step-up:** require recent strong authentication for new provider linking, credential-vault consent changes, recovery-code rotation and destructive account actions.

## Recovery boundaries

- Recovering the Master Account restores the AUREON account, device inventory, provider-account inventory and encrypted metadata.
- It does **not** automatically recover E2E file-content keys. E2E recovery must use the separate user-controlled recovery mechanism in the E2E encryption design.
- A user who loses all passkeys and recovery codes may need a separately reviewed account-recovery process. Support staff must never be able to decrypt E2E files or read provider refresh credentials.
- Provider refresh credentials are held in the explicit-consent backend vault; an AUREON account recovery event must not silently bypass provider reauthentication or provider-side revocation.

## Threat controls

- Generic login errors to reduce account enumeration.
- Per-account, per-device and network-aware rate limiting with abuse monitoring.
- Short-lived, single-use challenges with cryptographically secure random values.
- CSRF/state protections for browser-based authentication and OAuth callback flows.
- Session rotation and refresh-token reuse detection.
- Audit events for passkey enrollment/removal, recovery use, device changes, provider consent and session revocation.
- Notifications for new-device login, recovery use and security-setting changes.
- No secrets in logs, analytics, crash reports or support tickets.

## Why this recommendation

Passkeys reduce password reuse and phishing exposure, while offline recovery codes avoid making email the sole root of trust. Separating account recovery from E2E key recovery prevents a support or email compromise from silently exposing encrypted file contents.

## Open decisions requiring owner approval

- Whether password fallback is offered at launch.
- Whether email is used for account recovery initiation and which assurance checks are required.
- Recovery-code count, format, rotation UX and delayed-recovery policy.
- Whether enterprise/team accounts require a different policy.
- Legal jurisdiction and retention requirements for identity and audit data.

Do not implement production login or claim account recovery is complete until these decisions, the threat model and an independent security review are approved.
