# AUREON Android Storage Spike

This is an A0 proof-of-concept for the Kotlin-owned local storage boundary. It is not the production Android app.

## Scope

- Android library module: compileSdk 36 for the current prototype, minSdk 26. Move to API 37 when the stable SDK package is published and validated.
- Room 2.8.5 stores durable transfer checkpoints. Kotlin is pinned to 2.3.10 because this Room compiler version does not yet parse Kotlin 2.4 metadata.
- WorkManager 2.12.0 transfer constraints require connected network, battery not low and storage not low. A unique-work scheduler persists one work request per operation ID and carries the ID in input data; it accepts a provider-aware Worker from the integration layer.
- Pigeon 29.1.1 interface contract is checked in under pigeon/; CI generates matching Dart and Kotlin APIs from the same pinned package version and analyzes/compiles both sides.
- Generated Dart API is written to `pigeon/lib/src/aureon_storage_api.g.dart`; generated Kotlin API is written into the Android storage module under `com.aureon.storage.generated`.
- `AureonStorageHostApiImpl` implements the generated Kotlin host contract and connects transfer lookup/pause/resume calls to the Room repository. The generated Kotlin API compiles against Flutter’s Android embedding (`flutter.jar`).
- AureonStoragePlugin registers and unregisters the generated Pigeon handler per FlutterEngine. Plugin lifecycle and host implementation are compile/unit-test validated; a live FlutterEngine-to-Dart round trip and Flutter application shell are still open.
- Tests close and reopen the Room database, verify persisted checkpoint state, and build a read-only recovery plan. In-flight uploads are marked for provider-session reconciliation, not blindly re-enqueued; auth-blocked jobs remain held.
- Source cleanup can only be offered after remote verification, explicit user opt-in and a granted OS permission.

## Security and lifecycle boundaries

- Source URI and provider upload-session references are represented as encrypted-envelope byte arrays in the schema; the byte arrays in this spike are test fixtures, not production ciphertext.
- No method deletes a local source file. This prototype only computes whether a cleanup offer is eligible.
- No actual provider transfer Worker, Android Keystore wrapping, SAF picker or Flutter UI is implemented yet. The scheduler and WorkManager persistence path are integration-tested, but provider-aware Worker execution is still open. Pigeon generation is exercised in CI; the generated source files are created during the build.
- The recovery planner is deterministic scaffolding; it does not yet query a real provider session or schedule actual WorkManager execution. A database close/reopen test is not a full Android process-death/reboot/OEM test.

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


## Flutter application integration

The eventual Android Flutter host must register this plugin once per FlutterEngine, before Dart calls the generated API:

```kotlin
flutterEngine.plugins.add(AureonStoragePlugin())
```

If the module is later packaged as a Flutter plugin and included in the generated plugin registrant, use automatic registration instead of manual registration; never do both. Each engine gets its own Pigeon message handler, while all engines share the app-scoped Room database.

The plugin lifecycle registration is compile-validated by CI, but a live FlutterEngine-to-Dart round trip is still an open integration test. No provider transfer, SAF picker, production WorkManager scheduling, Keystore wrapping or Flutter UI is implemented in this spike.
