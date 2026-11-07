# AUREON Android Storage Spike

This is an A0 proof-of-concept for the Kotlin-owned local storage boundary. It is not the production Android app.

## Scope

- Android library module: compileSdk 36 for the current prototype, minSdk 26. Move to API 37 when the stable SDK package is published and validated.
- Room 2.8.5 stores durable transfer checkpoints.
- WorkManager 2.12.0 transfer constraints require connected network, battery not low and storage not low.
- Pigeon 29.1.1 interface contract is checked in under pigeon/.
- Tests close and reopen the Room database to verify persisted checkpoint state.
- Source cleanup can only be offered after remote verification, explicit user opt-in and a granted OS permission.

## Security and lifecycle boundaries

- Source URI and provider upload-session references are represented as encrypted-envelope byte arrays in the schema; the byte arrays in this spike are test fixtures, not production ciphertext.
- No method deletes a local source file. This prototype only computes whether a cleanup offer is eligible.
- No actual provider transfer, Android Keystore wrapping, Pigeon code generation, WorkManager scheduling, SAF picker or Flutter UI is implemented yet.
- A database close/reopen test is not a full Android process-death/reboot/OEM test.

## Build

Requires JDK 21, Android SDK API 37 and Gradle 8.13+.

```bash
cd android-spike
gradle :storage:testDebugUnitTest
gradle :storage:assembleDebug
```

The GitHub Actions workflow runs both commands on every relevant change.
