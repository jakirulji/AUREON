# AUREON App

This directory contains the shared Flutter application layer. Android and Windows host projects are generated in CI while platform integration is being developed.

## Current scope

- Responsive AUREON navigation and dark visual system.
- Local folder browsing through Android Storage Access Framework (SAF) and the Windows native folder picker.
- Selected folder bookmarks persist across launches. Android's persisted SAF read grant remains the authority to access the folder.
- In-folder name search, sorting by name/size/modified time/file type, hidden-entry filtering, file size and modified-time metadata.
- File open hand-off to the Android system viewer or Windows' default associated application; Windows validates root containment.
- Verified same-root file copy, safe parent-folder move, and Trash/restore flows. Android uses provider-native Trash when supported or an AUREON-managed folder; Windows uses the Recycle Bin. No silent permanent-delete fallback.
- AUREON Master Account email/password authentication via Firebase Identity Toolkit REST; email verification, saved refresh-token restoration, token refresh, password reauthentication and local sign-out. Passwords and ID tokens are not persisted.
- Cloudflare credential-vault sync/recovery UI connected to the HTTPS client. It requires compile-time Firebase and Worker URL configuration plus a deployed Worker/D1 database.
- Storage overview and recent-file cards still contain sample data.

## Validation

The app validation workflow runs Flutter dependency resolution, static analysis, widget tests and platform compilation for Android and Windows. It does **not** upload or retain APK/EXE artifacts. Final installable builds will be produced once the agreed implementation scope is complete.

## Important limitations

The Files screen supports verified copy, safe parent moves and Trash/restore, but not yet file-content preview inside AUREON. Provider OAuth account connection, provider file upload/download and cross-provider sync are not implemented yet. Android may report that no compatible viewer is installed for a particular file type. Storage overview and recent-file cards still use sample data. AUREON is not yet a finished replacement for Windows File Explorer.

## Local validation

Generate the desired platform scaffolding, then run:

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build apk --debug` or `flutter build windows --release` when platform compilation is needed.
\n## Owner configuration\n\nSee [Firebase and Cloudflare owner setup](../docs/OWNER-SETUP-FIREBASE-CLOUDFLARE.md) for the Spark/Workers/D1 setup and compile-time configuration.\n