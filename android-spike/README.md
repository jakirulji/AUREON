# AUREON Android Storage Spike

This is an A0 proof-of-concept for the Kotlin-owned local storage boundary. It is not the production Android app.

## Scope

- Android library module: compileSdk 36 for the current prototype, minSdk 26. Move to API 37 when the stable SDK package is published and validated.
- Room 2.8.5 stores durable transfer checkpoints. Kotlin is pinned to 2.3.10 because this Room compiler version does not yet parse Kotlin 2.4 metadata.
- WorkManager 2.12.0 transfer constraints require connected network, battery not low and storage not low.
- Pigeon 29.1.1 interface contract is checked in under pigeon/; CI generates matching Dart and Kotlin APIs from the same pinned package version and analyzes/compiles both sides.
- Generated Dart API is written to `pigeon/lib/src/aureon_storage_api.g.dart`; generated Kotlin API is written into the Android storage module under `com.aureon.storage.generated`.
- The generated Kotlin API compiles against Flutter’s Android embedding (`flutter.jar`); the prototype still has no registered runtime handler or Flutter application shell.
- Tests close and reopen the Room database to verify persisted checkpoint state.
- Source cleanup can only be offered after remote verification, explicit user opt-in and a granted OS permission.

## Security and lifecycle boundaries

- Source URI and provider upload-session references are represented as encrypted-envelope byte arrays in the schema; the byte arrays in this spike are test fixtures, not production ciphertext.
- No method deletes a local source file. This prototype only computes whether a cleanup offer is eligible.
- No actual provider transfer, Android Keystore wrapping, Pigeon code generation, WorkManager scheduling, SAF picker or Flutter UI is implemented yet.
- A database close/reopen test is not a full Android process-death/reboot/OEM test.

## Build

Requires Flutter stable (Dart 3.11+), JDK 21, Android SDK API 36 and Gradle 8.13+.

```bash
cd android-spike
cd pigeon
flutter pub get
mkdir -p lib/src ../storage/src/main/kotlin/com/aureon/storage/generated
dart run pigeon --input aureon_storage_api.dart \\
  --dart_out lib/src/aureon_storage_api.g.dart \\
  --kotlin_out ../storage/src/main/kotlin/com/aureon/storage/generated/AureonStorageApi.g.kt \\
  --kotlin_package com.aureon.storage.generated
flutter analyze --no-pub
cd ..
gradle :storage:testDebugUnitTest
gradle :storage:compileDebugKotlin
gradle :storage:assembleDebug
```

The GitHub Actions workflow runs both commands on every relevant change.
