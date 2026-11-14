# ADR: Google Drive client-only transfer engine

**Status:** Accepted design; implementation pending  
**Branch:** `feature/google-drive-client-only-architecture`

## Goal

Implement reliable Android Google Drive uploads and downloads without sending Google credentials, Drive content, or Drive-derived metadata to any AUREON server. Preserve the product rule that a successfully uploaded original is never silently deleted.

## Existing foundation

- Android Google authorization and paginated Drive file listing are implemented in the feature branch.
- The access token is held in the Android process memory and is not sent to AUREON services.
- Android Room stores transfer checkpoints; Pigeon exposes transfer snapshots and pause/resume calls.
- The checkpoint model already has encrypted-envelope fields for the source reference and provider upload-session state, plus byte acknowledgements and remote-verification flags.
- WorkManager scheduling and a recovery planner exist as foundations, but no concrete Google Drive transfer worker is connected yet.

## Security boundaries

- Google Drive API requests execute directly from the Android client to Google.
- Never send Google OAuth tokens, Drive file IDs/names/content, source paths, upload-session URLs, or Drive-derived metadata to Firebase, the AUREON Worker/D1, analytics, or crash reporting.
- Do not persist bearer access tokens. Reacquire authorization through Google Identity Services when a worker runs.
- If Google requires an interactive consent resolution while a background worker is running, transition the operation to `waiting_for_auth`; surface a notification and resume only after the user returns to AUREON and completes authorization.
- Raw SAF content URIs and resumable-session URLs must never be written to Room in plaintext. Store authenticated-encryption envelopes protected by a device-bound key whose lifecycle and backup behavior are explicitly tested.
- AUREON Master Account may synchronize only the already-approved user-managed connection-slot ID, label, and order.

## Upload protocol

1. User explicitly selects one or more local source documents through the Android Storage Access Framework.
2. Create an immutable operation ID and Room checkpoint before scheduling work. Capture a stable source fingerprint (size and SHA-256); reject a changed source during resume.
3. Use the Google Drive resumable upload protocol. Persist the resumable session URI only inside an authenticated-encryption envelope.
4. Transfer aligned chunks, checkpoint only bytes Google has acknowledged, and never advance progress based only on bytes read locally.
5. After interruption, query the provider session for its acknowledged range before sending more bytes. Never blindly replay an uncertain chunk.
6. Finalize and verify the remote object using its returned Drive ID, size, and available checksum. Mark the job verified only after provider-side verification succeeds.
7. Keep the user's original local file. Cleanup is permitted only for an AUREON-created temporary staging copy, only after remote verification, and only when the app can prove that the path is inside its own staging directory. Never auto-delete the original selected file.

## Download protocol

1. Download directly from Drive to an AUREON-owned temporary staging file using range requests where supported.
2. Persist only encrypted local source/destination references and verified byte checkpoints.
3. Resume by reconciling the remote object identity, size, modification/version metadata and server-supported range behavior. If the remote object changed, stop and require a fresh download rather than mixing versions.
4. Verify the completed local file before atomically moving it into the user-selected destination. Never expose a partially downloaded file as complete.
5. On cancellation or unrecoverable failure, retain or remove partial staging data according to an explicit user-visible policy; never modify the remote original.

## Scheduling and recovery

- Use unique WorkManager work per operation ID, with network constraints and foreground execution/notification for long-running user-initiated transfers.
- Recovery must reconcile provider state for any operation previously in `uploading`, `finalizing`, or `verifying` before resuming.
- Respect pause, cancel, authentication-required, network-wait, quota-wait, retry-wait, conflict, and verified states.
- Apply bounded exponential backoff with jitter to transient failures; do not retry permanent permission, quota, or policy errors indefinitely.
- Do not claim background execution is guaranteed by Android. Battery restrictions, force-stop, revoked grants, and OS scheduling can delay or stop work.

## Delivery order

1. Add a tested Google Drive REST adapter and protocol-level tests for resumable upload session creation, chunk acknowledgement, session reconciliation, finalization, and error classification.
2. Add secure envelope/key handling for SAF source references and provider session URIs; test key loss and process restart.
3. Add the concrete WorkManager upload worker and recovery integration.
4. Add verified download worker with range-resume and atomic destination commit.
5. Connect Flutter UI actions, pause/resume/cancel, progress notifications, and transfer history.
6. Add emulator tests and a manual real-account test checklist. Only then prepare Google's Restricted Scope verification evidence.

## Release gates

- Test large files, empty files, duplicate enqueue, source mutation, process death between chunk send and acknowledgement, expired upload sessions, network loss, quota errors, revoked access, and low-storage conditions.
- Verify no Google credential or Drive-derived data reaches AUREON backend endpoints or telemetry.
- Verify that only AUREON staging files can be cleaned up and that original user files remain untouched.
- Google Restricted Scope OAuth verification remains required for public distribution. This architecture does not guarantee a CASA exemption or zero-cost verification.
