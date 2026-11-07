# AUREON A1 — First Vertical-Slice Backlog

**Status:** Draft backlog; A0 exit review still required  
**Goal:** Deliver one end-to-end, testable Android-first path before adding multiple providers or advanced sync features.

## A1.0 — Identity and device foundation
- [ ] Implement Master Account registration and passkey-first authentication after ADR-0002 approval.
- [ ] Implement device registration with a per-device public key and revocation.
- [ ] Implement opaque rotating AUREON sessions, device binding, expiry and reuse detection.
- [ ] Add audit events and notification hooks for new-device login and recovery use.
- [ ] Keep provider OAuth credentials and E2E content keys outside identity/session code.

## A1.1 — Android local foundation
- [ ] Flutter app shell with Pigeon API boundary.
- [ ] Kotlin Room database, schema migrations and repository interfaces.
- [ ] Persistent transfer queue and checkpoint model.
- [ ] Process-death/reboot restoration tests.
- [ ] SAF picker integration and persistable URI permission tests.
- [ ] WorkManager unique-work scheduling and visible transfer notifications.

## A1.2 — First provider: Google Drive
- [ ] Complete Google OAuth app registration, exact scope review and consent-screen plan.
- [ ] Prove approved inventory scope eligibility and Google verification requirements before broad inventory is promised.
- [ ] Implement PKCE, state validation, provider account identity and credential-vault consent UX.
- [ ] Implement server credential broker with managed KMS only after security approval.
- [ ] Implement paginated metadata-first inventory with real parent IDs and resumable cursors.
- [ ] Preserve shortcuts, shared items, trashed items, orphan states and duplicates.
- [ ] Display Drive hierarchy and virtual MIME categories without mutating originals.

## A1.3 — First verified transfer
- [ ] Implement one upload path with provider resumable sessions.
- [ ] Persist operation ID, source snapshot, upload session and acknowledged progress before each irreversible step.
- [ ] Implement ambiguous-finalize reconciliation and duplicate detection.
- [ ] Verify exact source/upload bytes using provider checksum or read-back strategy.
- [ ] Keep local original unless user explicitly enabled cleanup and every deletion safety gate passes.
- [ ] Implement resumable download to temporary destination, verification and atomic promotion where supported.

## A1.4 — Security and release gates
- [ ] Threat-model review for Master Account, credential vault and E2E recovery.
- [ ] Independent cryptographic review and cross-platform test vectors.
- [ ] Privacy notice, terms, provider restricted-scope disclosures and data-retention rules.
- [ ] Cost model, hosting/KMS selection, backup restore drill and incident runbook.
- [ ] Accessibility, low-storage, network-loss, token-expiry, process-death and OEM background test matrix.

## Explicitly out of first vertical slice
- OneDrive/Dropbox production integrations.
- Windows Cloud Files API integration.
- Root/FUSE filesystem.
- AI file classification or content analysis.
- Automatic provider quota pooling or file sharding.
- Automatic deletion of local originals.
