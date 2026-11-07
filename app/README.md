# AUREON App

This directory contains the shared Flutter application layer. Android and Windows host projects are generated in CI while the platform integration work is being developed.

## Current scope

- Responsive AUREON navigation and dark visual system.
- Read-only local folder browsing through the Android SAF and Windows native folder picker.
- Selected folder bookmark is stored in app-local preferences and restored on next launch; Android's persisted SAF read grant remains the authority to access it.
- Storage overview and recent-file layout still contain sample data.

## Validation

The app validation workflow runs Flutter dependency resolution, static analysis, widget tests and platform compilation for Android and Windows. It does **not** upload or retain APK/EXE artifacts. Final installable builds will be produced once the agreed implementation scope is complete.

## Important limitation

This is not yet a functional file manager. Real Android SAF browsing, Windows filesystem browsing, cloud OAuth, uploads, downloads, sync and production security integrations are not connected to the UI. Do not use it to manage real files.

## Local validation

Generate the desired platform scaffolding, then run:

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build apk --debug` or `flutter build windows --release` when platform compilation is needed.
