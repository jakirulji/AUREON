# AUREON A1 — First Vertical-Slice Backlog

**Status:** Draft backlog; A0 exit review still required  
**Goal:** Deliver the first end-to-end Android path while establishing a parallel Windows desktop file-manager workstream after shared contracts are stable.

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

## Parallel Windows workstream (after shared contracts freeze)

This workstream may proceed alongside Android implementation. It does not block the first Android vertical slice, and Windows-specific code must not redefine shared contracts independently.

- [ ] Approve the Explorer-style Windows information architecture and interaction specification.
- [ ] Create Flutter Windows desktop shell with navigation pane, address/breadcrumb bar, tabs, file list/details, preview, search and sorting/grouping.
- [ ] Define keyboard shortcuts, context-menu actions, drag/drop, clipboard, file properties and accessibility behavior.
- [ ] Implement a native C++ filesystem adapter for safe local listing and file operations, including recycle-bin semantics, permissions, locked files and conflict handling.
- [ ] Prototype Cloud Files API sync-root registration, placeholders, hydration/dehydration, pin/unpin and progress mapping.
- [ ] Add supported Windows shell entry points: file/folder associations where permitted, Open With, context menu, Send To and pinned shortcuts.
- [ ] Test local and cloud files together while preserving canonical provider/account provenance and no-auto-delete rules.
- [ ] Package, sign and test the Windows installer/update path.
- [ ] Keep Windows Explorer available for OS shell/system surfaces; do not patch or terminate explorer.exe.

## Explicitly out of first vertical slice
- OneDrive/Dropbox production integrations.
- Production-grade Windows Cloud Files API integration (a prototype may proceed in parallel after shared contracts freeze).
- Root/FUSE filesystem.
- AI file classification or content analysis.
- Automatic provider quota pooling or file sharding.
- Automatic deletion of local originals.


## Shared platform contract gate

Before substantial Windows and Android feature work proceeds in parallel, both adapters must align with [Shared Android/Windows Platform Contracts](./SHARED-PLATFORM-CONTRACTS.md). The contract covers logical file/version identity, provider capability reporting, durable transfer states, verification evidence, error taxonomy, encryption envelope interoperability and the no-auto-delete invariant. It is a proposed freeze baseline, not a claim of completed implementation.
