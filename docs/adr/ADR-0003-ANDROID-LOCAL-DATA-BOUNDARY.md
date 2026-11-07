# ADR-0003 — Android Local Data and Native Integration Boundary

**Status:** Recommended for A0/A1 implementation; prototype validation pending  
**Date:** 2026-11-07

## Decision

Use **Room 2.8.5 as the authoritative Android local persistence layer**, owned by Kotlin. Use **WorkManager 2.12.0** for durable deferrable work and **Pigeon 29.1.1** for the typed Flutter-to-Kotlin boundary. These are the current stable candidates as of this A0 review; pin and test them in the Android prototype before production. Do not let Flutter UI and Kotlin background workers maintain separate writable databases for the same transfer/catalog state.

## Responsibilities

### Kotlin / Android domain layer
- Room stores the local account/device references, provider account state, encrypted local metadata, sync cursors, transfer queue/checkpoints, conflict state, offline pin index, cache index and pending cleanup intents.
- Repository interfaces own transactions and state transitions.
- WorkManager handles deferrable/retryable synchronization and maintenance.
- A user-initiated long transfer may use an appropriately declared foreground service and notification where current Android policy permits.
- SAF content URIs and persistable URI grants are retained only when the user grants them. A source snapshot/staging copy is used when stable bytes are required for resumable upload.
- Android Keystore protects local wrapping keys/session material. It does not replace the server-side provider credential vault and does not store E2E recovery secrets without a separate user-approved design.
- Native provider adapters perform provider-specific HTTP, upload/download sessions and secure in-memory access-token handling.

### Flutter
- Screens, navigation, accessibility, search/filter presentation and user intent.
- Typed calls through Pigeon for account, file, transfer, cache and system-picker operations.
- No direct SQL access to Room, no provider refresh tokens, no KMS access and no raw E2E key material in widget state.
- Long-running operation state is observed from a repository stream/event contract; UI recreation must not lose the underlying operation.

## Process-death and reboot behavior

- Persist every transfer state transition and provider session checkpoint before acknowledging it to UI.
- On process restart, reconcile local state with provider session status before resuming; do not blindly repeat create/finalize operations.
- WorkManager jobs are idempotent and re-check account auth, network, storage reserve, source availability and cancellation state.
- A revoked permission or missing source pauses the affected job and preserves all known-good data.
- Cache eviction may remove only eligible cache entries, never source originals, staging snapshots, canonical cloud objects or recovery material.
- Notifications report paused/failed/re-auth-required states without exposing filenames or tokens on lock screen by default.

## Proposed support baseline

- **Minimum Android API:** 26 (Android 8.0) provisionally. This avoids carrying legacy platform branches into the first release while retaining a broad Android device base. Revisit only with usage and security evidence.
- **Target API:** 37 for the first public Android 17 release, subject to stable SDK availability and Google Play policy at submission time. CI must build against the selected stable SDK; target SDK is re-evaluated before each release.
- **Background execution:** no promise of uninterrupted background transfers on every OEM. WorkManager/foreground execution is best-effort within Android and OEM restrictions; UI must make pause/retry states explicit.
- **Windows:** later phase, with Flutter desktop UI and a native C++ Cloud Files API adapter. Do not force Android storage abstractions onto Windows.

## Consequences

- One source of truth for transfer and cache state across Flutter UI and Kotlin workers.
- Stronger process-death recovery and fewer cross-database consistency bugs.
- More native Kotlin work and a typed bridge to maintain.
- Pigeon API compatibility and schema migration tests become A0/A1 requirements.

## Proposed Android dependency baseline

- Android Gradle Plugin 9.5.0 with Gradle 9.9.0 or later compatible patch.
- Kotlin 2.4.21 and JDK 21 for the app build toolchain.
- compileSdk/targetSdk 37; minSdk 26.
- Room 2.8.5 with KSP (or the then-supported Room compiler integration) and exported schema JSON committed for migration review.
- WorkManager 2.12.0; use unique work names and explicit constraints/backoff.
- Pigeon 29.1.1; generated Dart/Kotlin bindings are build artifacts from a checked-in interface definition, not hand-maintained string channels.

These versions are candidate pins, not yet validated in an Android build. Re-check current stable SDK and Play policy before release.

## Validation spike

Before A0 exit, demonstrate:
1. Room migrations and repository transaction tests.
2. A transfer checkpoint surviving process death/recreation.
3. WorkManager unique-work scheduling and retry behavior.
4. Persisted SAF permission restoration and revoked-permission handling.
5. Flutter-to-Kotlin Pigeon calls and typed state updates.
6. Keystore-backed local wrapping-key creation and fail-closed behavior on key invalidation.
7. No source deletion when upload verification or authorization is incomplete.

## References

- [AndroidX Room release notes](https://developer.android.com/jetpack/androidx/releases/room) — Room 2.8.5 stable.
- [AndroidX WorkManager release notes](https://developer.android.com/jetpack/androidx/releases/work) — WorkManager 2.12.0 stable.
- [Flutter Pigeon package](https://pub.dev/packages/pigeon) — typed platform API generation; current stable 29.1.1.
- [Android Gradle Plugin 9.5.0 release notes](https://developer.android.com/build/releases/agp-9-5-0-release-notes) — API 37 support and Gradle compatibility.
